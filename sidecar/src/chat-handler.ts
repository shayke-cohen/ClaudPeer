import { spawn } from "child_process";
import type { AgentConfig, SidecarEvent } from "./types.js";

type EventEmitter = (event: SidecarEvent) => void;

export class ChatHandler {
  private configs = new Map<string, AgentConfig>();
  private histories = new Map<string, string[]>();
  private emit: EventEmitter;

  constructor(emit: EventEmitter) {
    this.emit = emit;
  }

  register(sessionId: string, config: AgentConfig): void {
    this.configs.set(sessionId, config);
    this.histories.set(sessionId, []);
    console.log(`[chat] Registered simple chat session ${sessionId}`);
  }

  has(sessionId: string): boolean {
    return this.configs.has(sessionId);
  }

  async sendMessage(sessionId: string, text: string): Promise<void> {
    const config = this.configs.get(sessionId);
    if (!config) {
      this.emit({ type: "session.error", sessionId, error: "Chat session not found" });
      return;
    }

    const history = this.histories.get(sessionId) ?? [];

    const prompt = history.length > 0
      ? `${history.join("\n")}\n\nUser: ${text}`
      : text;

    history.push(`User: ${text}`);

    try {
      console.log(`[chat] Sending to claude --print for session ${sessionId}`);

      const args = [
        "--print",
        "--model", config.model || "claude-sonnet-4-6",
      ];

      if (config.systemPrompt) {
        args.push("--system-prompt", config.systemPrompt);
      }

      if (config.maxTurns && config.maxTurns > 0) {
        args.push("--max-turns", String(config.maxTurns));
      }

      const child = spawn("claude", args, {
        stdio: ["pipe", "pipe", "pipe"],
        env: { ...process.env },
      });

      let fullResponse = "";
      let errorOutput = "";

      child.stdout.on("data", (chunk: Buffer) => {
        const text = chunk.toString();
        fullResponse += text;
        this.emit({ type: "stream.token", sessionId, text });
      });

      child.stderr.on("data", (chunk: Buffer) => {
        errorOutput += chunk.toString();
      });

      child.stdin.write(prompt);
      child.stdin.end();

      await new Promise<void>((resolve, reject) => {
        child.on("close", (code) => {
          if (code === 0) {
            resolve();
          } else {
            reject(new Error(`claude exited with code ${code}: ${errorOutput}`));
          }
        });
        child.on("error", reject);
      });

      const trimmed = fullResponse.trim();
      history.push(`Assistant: ${trimmed}`);

      this.emit({
        type: "session.result",
        sessionId,
        result: trimmed || "(no response)",
        cost: 0,
      });

      console.log(`[chat] Response complete for session ${sessionId} (${trimmed.length} chars)`);
    } catch (err: any) {
      const errMsg = err.message ?? String(err);
      console.error(`[chat:${sessionId}] Error: ${errMsg}`);
      this.emit({ type: "session.error", sessionId, error: errMsg });
    }
  }

  static isSimpleChat(config: AgentConfig): boolean {
    return (
      config.allowedTools.length === 0 &&
      config.mcpServers.length === 0 &&
      (!config.skills || config.skills.length === 0)
    );
  }
}
