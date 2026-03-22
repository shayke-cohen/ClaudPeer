import type { ServerWebSocket } from "bun";
import type { SidecarCommand, SidecarEvent } from "./types.js";
import type { SessionManager } from "./session-manager.js";
import type { ToolContext } from "./tools/tool-context.js";

export class WsServer {
  private clients = new Set<ServerWebSocket<unknown>>();
  private sessionManager: SessionManager;
  private ctx: ToolContext;
  private server: ReturnType<typeof Bun.serve> | null = null;

  constructor(port: number, sessionManager: SessionManager, ctx: ToolContext) {
    this.sessionManager = sessionManager;
    this.ctx = ctx;

    this.server = Bun.serve({
      port,
      fetch(req, server) {
        if (server.upgrade(req)) return undefined;
        return new Response("WebSocket endpoint", { status: 426 });
      },
      websocket: {
        open: (ws) => {
          this.clients.add(ws);
          console.log(`[ws] Swift client connected (total: ${this.clients.size})`);
          const ready: SidecarEvent = {
            type: "sidecar.ready",
            port,
            version: "0.2.0",
          };
          ws.send(JSON.stringify(ready));
        },
        message: (ws, message) => {
          try {
            const data = typeof message === "string" ? message : new TextDecoder().decode(message);
            console.log("[ws] Received:", data.substring(0, 200));
            const command = JSON.parse(data) as SidecarCommand;
            this.handleCommand(command).catch((err) => {
              console.error("[ws] Command handler error:", err);
            });
          } catch (err) {
            console.error("[ws] Failed to parse command:", err);
          }
        },
        close: (ws) => {
          this.clients.delete(ws);
          console.log(`[ws] Swift client disconnected (total: ${this.clients.size})`);
        },
      },
    });

    console.log(`[ws] WebSocket server listening on ws://localhost:${port}`);
  }

  private async handleCommand(command: SidecarCommand): Promise<void> {
    switch (command.type) {
      case "session.create":
        await this.sessionManager.createSession(
          command.conversationId,
          command.agentConfig,
        );
        break;
      case "session.message":
        await this.sessionManager.sendMessage(
          command.sessionId,
          command.text,
          command.attachments,
        );
        break;
      case "session.resume":
        await this.sessionManager.resumeSession(
          command.sessionId,
          command.claudeSessionId,
        );
        break;
      case "session.fork":
        await this.sessionManager.forkSession(command.sessionId);
        break;
      case "session.pause":
        await this.sessionManager.pauseSession(command.sessionId);
        break;
      case "agent.register":
        for (const def of command.agents) {
          const config = { ...def.config };
          if (def.instancePolicy) {
            if (typeof def.instancePolicy === "string" && def.instancePolicy.startsWith("pool:")) {
              config.instancePolicy = "pool";
              config.instancePolicyPoolMax = parseInt(def.instancePolicy.split(":")[1], 10) || 3;
            } else if (typeof def.instancePolicy === "object" && "pool" in def.instancePolicy) {
              config.instancePolicy = "pool";
              config.instancePolicyPoolMax = def.instancePolicy.pool;
            } else if (def.instancePolicy === "singleton") {
              config.instancePolicy = "singleton";
            } else {
              config.instancePolicy = "spawn";
            }
          }
          this.ctx.agentDefinitions.set(def.name, config);
          console.log(`[ws] Registered agent definition: ${def.name} (policy: ${config.instancePolicy ?? "spawn"})`);
        }
        break;

      case "delegate.task":
        await this.handleDelegateTask(command);
        break;
    }
  }

  private async handleDelegateTask(command: Extract<SidecarCommand, { type: "delegate.task" }>): Promise<void> {
    const config = this.ctx.agentDefinitions.get(command.toAgent);
    if (!config) {
      console.error(`[ws] delegate.task: agent definition not found for "${command.toAgent}"`);
      this.broadcast({
        type: "session.error",
        sessionId: command.sessionId,
        error: `Agent definition not found: ${command.toAgent}`,
      });
      return;
    }

    const policy = config.instancePolicy ?? "spawn";
    const prompt = command.context
      ? `${command.task}\n\n## Context\n${command.context}`
      : command.task;

    let targetSessionId: string | undefined;
    let method = "spawned";

    if (policy === "singleton") {
      const existing = this.ctx.sessions.findByAgentName(command.toAgent);
      if (existing.length > 0) {
        targetSessionId = existing[0].id;
        method = "reused_singleton";
      }
    } else if (policy === "pool") {
      const existing = this.ctx.sessions.findByAgentName(command.toAgent);
      const poolMax = config.instancePolicyPoolMax ?? 3;
      if (existing.length >= poolMax) {
        let minMessages = Infinity;
        for (const s of existing) {
          const count = this.ctx.messages.peek(s.id);
          if (count < minMessages) {
            minMessages = count;
            targetSessionId = s.id;
          }
        }
        method = "pool_routed";
      }
    }

    this.broadcast({
      type: "peer.delegate",
      from: this.ctx.sessions.get(command.sessionId)?.agentName ?? command.sessionId,
      to: command.toAgent,
      task: command.task,
    });

    if (targetSessionId) {
      this.ctx.messages.push(targetSessionId, {
        id: crypto.randomUUID(),
        from: command.sessionId,
        fromAgent: this.ctx.sessions.get(command.sessionId)?.agentName ?? "User",
        to: targetSessionId,
        text: `[Delegated Task] ${prompt}`,
        priority: "urgent",
        timestamp: new Date().toISOString(),
        read: false,
      });
      console.log(`[ws] delegate.task: routed to existing session ${targetSessionId} (${method})`);
    } else {
      const newSessionId = crypto.randomUUID();
      try {
        await this.ctx.spawnSession(newSessionId, config, prompt, command.waitForResult);
        console.log(`[ws] delegate.task: spawned new session ${newSessionId} for ${command.toAgent}`);
      } catch (err: any) {
        console.error(`[ws] delegate.task: spawn failed:`, err);
        this.broadcast({
          type: "session.error",
          sessionId: command.sessionId,
          error: `Delegation to ${command.toAgent} failed: ${err.message}`,
        });
      }
    }
  }

  broadcast(event: SidecarEvent): void {
    const data = JSON.stringify(event);
    for (const client of this.clients) {
      try {
        client.send(data);
      } catch {
        this.clients.delete(client);
      }
    }
  }

  close(): void {
    this.server?.stop();
  }
}
