import { query } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "crypto";
import type { AgentConfig, SidecarEvent } from "./types.js";
import { SessionRegistry } from "./stores/session-registry.js";
import { ChatHandler } from "./chat-handler.js";

type EventEmitter = (event: SidecarEvent) => void;

export class SessionManager {
  private registry = new SessionRegistry();
  private chatHandler: ChatHandler;
  private emit: EventEmitter;
  private activeAborts = new Map<string, AbortController>();

  constructor(emit: EventEmitter) {
    this.emit = emit;
    this.chatHandler = new ChatHandler(emit);
  }

  async createSession(conversationId: string, config: AgentConfig): Promise<void> {
    this.registry.create(conversationId, config);

    if (ChatHandler.isSimpleChat(config)) {
      this.chatHandler.register(conversationId, config);
      console.log(`[session] Created SIMPLE CHAT session ${conversationId} for "${config.name}"`);
    } else {
      console.log(`[session] Created AGENT session ${conversationId} for "${config.name}"`);
    }
  }

  async sendMessage(sessionId: string, text: string): Promise<void> {
    if (this.chatHandler.has(sessionId)) {
      await this.chatHandler.sendMessage(sessionId, text);
      return;
    }

    const config = this.registry.getConfig(sessionId);
    if (!config) {
      this.emit({ type: "session.error", sessionId, error: "Session not found" });
      return;
    }

    const state = this.registry.get(sessionId);
    if (!state) {
      this.emit({ type: "session.error", sessionId, error: "Session state not found" });
      return;
    }

    const abortController = new AbortController();
    this.activeAborts.set(sessionId, abortController);
    this.registry.update(sessionId, { status: "active" });

    try {
      const options = this.buildQueryOptions(sessionId, config, state.claudeSessionId, abortController);
      const sdkSessionId = options.sessionId ?? options.resume;

      console.log(`[session] Starting Agent SDK query for session ${sessionId}`);
      const stream = query({ prompt: text, options });
      let resultText = "";

      for await (const message of stream) {
        if (abortController.signal.aborted) break;
        this.handleSDKMessage(sessionId, message, (t) => { resultText += t; });
      }

      if (sdkSessionId && !state.claudeSessionId) {
        this.registry.update(sessionId, { claudeSessionId: sdkSessionId });
      }

      this.emit({
        type: "session.result",
        sessionId,
        result: resultText || "(no text response)",
        cost: 0,
      });
    } catch (err: any) {
      if (abortController.signal.aborted) {
        this.registry.update(sessionId, { status: "paused" });
      } else {
        const errMsg = err.message ?? String(err);
        const errStack = err.stack?.substring(0, 500) ?? "";
        console.error(`[session:${sessionId}] Error: ${errMsg}`);
        if (errStack) console.error(`[session:${sessionId}] Stack: ${errStack}`);
        this.emit({
          type: "session.error",
          sessionId,
          error: errMsg,
        });
        this.registry.update(sessionId, { status: "failed" });
      }
    } finally {
      this.activeAborts.delete(sessionId);
    }
  }

  async resumeSession(sessionId: string, claudeSessionId: string): Promise<void> {
    this.registry.update(sessionId, { claudeSessionId, status: "active" });
    this.emit({
      type: "stream.token",
      sessionId,
      text: "Session context restored. Send a message to continue.\n",
    });
  }

  async forkSession(sessionId: string): Promise<string> {
    const config = this.registry.getConfig(sessionId);
    const forkedId = `${sessionId}-fork-${Date.now()}`;
    if (config) {
      this.registry.create(forkedId, config);
    }
    this.emit({
      type: "stream.token",
      sessionId: forkedId,
      text: `Forked from session ${sessionId}.\n`,
    });
    return forkedId;
  }

  async pauseSession(sessionId: string): Promise<void> {
    const abort = this.activeAborts.get(sessionId);
    if (abort) {
      abort.abort();
    }
    this.registry.update(sessionId, { status: "paused" });
  }

  listSessions() {
    return this.registry.list();
  }

  private buildQueryOptions(
    sessionId: string,
    config: AgentConfig,
    claudeSessionId: string | undefined,
    abortController: AbortController,
  ): Record<string, any> {
    const options: Record<string, any> = {
      model: config.model || "claude-sonnet-4-6",
      maxTurns: config.maxTurns ?? 30,
      abortController,
      cwd: config.workingDirectory || undefined,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
    };

    if (config.systemPrompt) {
      options.systemPrompt = {
        type: "preset" as const,
        preset: "claude_code" as const,
        append: this.buildSystemPromptAppend(config),
      };
    } else {
      options.systemPrompt = { type: "preset" as const, preset: "claude_code" as const };
    }

    if (config.allowedTools.length > 0) {
      options.allowedTools = config.allowedTools;
    }

    if (config.maxBudget) {
      options.maxBudgetUsd = config.maxBudget;
    }

    // MCP servers
    if (config.mcpServers.length > 0) {
      const mcpServers: Record<string, any> = {};
      for (const mcp of config.mcpServers) {
        if (mcp.command) {
          mcpServers[mcp.name] = {
            type: "stdio",
            command: mcp.command,
            args: mcp.args ?? [],
            env: mcp.env ?? {},
          };
        } else if (mcp.url) {
          mcpServers[mcp.name] = {
            type: "sse",
            url: mcp.url,
          };
        }
      }
      if (Object.keys(mcpServers).length > 0) {
        options.mcpServers = mcpServers;
      }
    }

    // Session management: resume or assign a stable SDK session ID (must be UUID)
    if (claudeSessionId) {
      options.resume = claudeSessionId;
    } else {
      options.sessionId = randomUUID();
    }

    return options;
  }

  private buildSystemPromptAppend(config: AgentConfig): string {
    let append = config.systemPrompt || "";

    if (config.skills && config.skills.length > 0) {
      append += "\n\n## Skills\n\n";
      for (const skill of config.skills) {
        append += `### ${skill.name}\n${skill.content}\n\n`;
      }
    }

    return append;
  }

  private handleSDKMessage(
    sessionId: string,
    message: any,
    collectText: (text: string) => void,
  ): void {
    switch (message.type) {
      case "assistant":
        if (message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === "text" && block.text) {
              collectText(block.text);
              this.emit({ type: "stream.token", sessionId, text: block.text });
            }
          }
        }
        break;

      case "tool_use":
        this.emit({
          type: "stream.toolCall",
          sessionId,
          tool: message.name ?? "unknown",
          input: typeof message.input === "string"
            ? message.input
            : JSON.stringify(message.input ?? {}),
        });
        break;

      case "tool_result":
        this.emit({
          type: "stream.toolResult",
          sessionId,
          tool: message.name ?? "unknown",
          output: typeof message.content === "string"
            ? message.content
            : JSON.stringify(message.content ?? {}),
        });
        break;

      case "result":
        if (message.cost_usd != null) {
          const state = this.registry.get(sessionId);
          this.registry.update(sessionId, {
            cost: (state?.cost ?? 0) + message.cost_usd,
          });
        }
        if (message.session_id) {
          this.registry.update(sessionId, { claudeSessionId: message.session_id });
        }
        break;

      case "error":
        this.emit({
          type: "session.error",
          sessionId,
          error: message.error?.message ?? "SDK error",
        });
        break;

      default:
        // Other message types (system, thinking, etc.) are not forwarded to UI for now
        break;
    }
  }
}
