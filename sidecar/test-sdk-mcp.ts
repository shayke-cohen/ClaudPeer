import { query, createSdkMcpServer, tool } from "/Users/shayco/ClaudeStudio/sidecar/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs";
import { z } from "zod";

let toolCalled = false;

const server = createSdkMcpServer({
  name: "test",
  tools: [
    tool("say_hello", "Say hello to someone. YOU MUST CALL THIS TOOL when asked to say hello.", 
      { name: z.string().describe("The name to say hello to") }, 
      async (args: { name: string }) => {
        toolCalled = true;
        console.error("[TEST] say_hello CALLED with name:", args.name);
        return { content: [{ type: "text" as const, text: `Hello, ${args.name}!` }] };
      }
    )
  ]
});

console.error("[TEST] SDK MCP server:", JSON.stringify({ type: server.type, name: server.name, hasInstance: !!server.instance }));

const stream = query({
  prompt: "Call the say_hello tool with name='World'. You MUST use the say_hello tool.",
  options: {
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    mcpServers: { test: server },
    maxTurns: 3,
    model: "claude-haiku-4-5-20251001",
  }
});

for await (const msg of stream as AsyncIterable<any>) {
  if (msg.type === "result") {
    console.error("[TEST] Result:", msg.result?.substring(0, 200));
    console.error("[TEST] Tool called:", toolCalled);
    console.error("[TEST] num_turns:", msg.num_turns);
  } else if (msg.type !== "system") {
    console.error("[TEST] msg type:", msg.type, "name:", msg.name ?? "");
  }
}
