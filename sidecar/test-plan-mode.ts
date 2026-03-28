/**
 * Test plan mode via the sidecar's WebSocket API — the exact same path the app uses.
 * Sends session.create + session.message with planMode=true/false and logs tool calls.
 */
import WebSocket from "ws";

const WS_PORT = 9849;

function connect(): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${WS_PORT}`);
    ws.on("open", () => resolve(ws));
    ws.on("error", reject);
  });
}

function send(ws: WebSocket, data: any) {
  ws.send(JSON.stringify(data));
}

function collectEvents(ws: WebSocket, sessionId: string, timeoutMs = 60000): Promise<any[]> {
  return new Promise((resolve) => {
    const events: any[] = [];
    const timer = setTimeout(() => {
      ws.removeAllListeners("message");
      resolve(events);
    }, timeoutMs);

    ws.on("message", (raw: Buffer) => {
      const msg = JSON.parse(raw.toString());
      if (msg.sessionId === sessionId) {
        events.push(msg);
        if (msg.type === "session.result" || msg.type === "session.error") {
          clearTimeout(timer);
          ws.removeAllListeners("message");
          resolve(events);
        }
      }
    });
  });
}

async function runTest(label: string, planMode: boolean, userMessage: string) {
  console.log(`\n=== ${label} ===\n`);

  const ws = await connect();
  const sessionId = `plan-test-${planMode ? "plan" : "noplan"}-${Date.now()}`;

  // Create session
  send(ws, {
    type: "session.create",
    conversationId: sessionId,
    agentConfig: {
      name: "PlanTestBot",
      systemPrompt: "",
      allowedTools: [],
      mcpServers: [],
      model: "claude-opus-4-6",
      maxTurns: 5,
      workingDirectory: "/tmp",
      skills: [],
      interactive: true,
    },
  });

  await new Promise(r => setTimeout(r, 500));

  // Send message with planMode flag
  send(ws, {
    type: "session.message",
    sessionId,
    text: userMessage,
    planMode,
  });

  // Collect events
  const events = await collectEvents(ws, sessionId, 90000);
  ws.close();

  const toolCalls = events.filter(e => e.type === "stream.toolCall").map(e => e.tool);
  const tokens = events.filter(e => e.type === "stream.token").map(e => e.text).join("");
  const result = events.find(e => e.type === "session.result");
  const questions = events.filter(e => e.type === "agent.question");

  console.log(`  Tool calls: [${toolCalls.join(", ")}]`);
  console.log(`  Questions (ask_user): ${questions.length}`);
  if (questions.length > 0) {
    for (const q of questions) {
      console.log(`    Q: "${q.question}" options=[${(q.options || []).map((o: any) => o.label).join(", ")}]`);
    }
  }
  console.log(`  Text (first 200): ${tokens.substring(0, 200)}`);
  console.log(`  Result: ${result?.result?.substring(0, 100) ?? "none"}`);
  console.log(`  Cost: $${result?.cost ?? 0}`);

  return { toolCalls, questions: questions.length, text: tokens };
}

async function main() {
  console.log("Testing plan mode via sidecar WebSocket API...\n");

  // Test A: planMode=true (should inject PLAN_MODE_APPEND and use Opus)
  const a = await runTest(
    "TEST A: planMode=true (system prompt append + Opus)",
    true,
    "plan a pacman game",
  );

  // Test B: planMode=false but instructions in user message
  const b = await runTest(
    "TEST B: planMode=false, instructions in USER MESSAGE",
    false,
    `<HARD-GATE>
You are in PLAN MODE. Your FIRST action MUST be to call the ask_user MCP tool to gather requirements.
You MUST call show_progress to track planning phases.
You MUST NOT present a plan without first gathering requirements from the user.
</HARD-GATE>

User request: plan a pacman game`,
  );

  console.log("\n=== COMPARISON ===");
  console.log(`Test A (system append): ${a.questions} ask_user calls, ${a.toolCalls.length} total tools`);
  console.log(`Test B (user message):  ${b.questions} ask_user calls, ${b.toolCalls.length} total tools`);

  if (a.questions === 0 && b.questions > 0) {
    console.log("\n→ CONFIRMED: System prompt append doesn't work, user message injection does");
  } else if (a.questions > 0 && b.questions > 0) {
    console.log("\n→ Both work — issue is elsewhere");
  } else if (a.questions === 0 && b.questions === 0) {
    console.log("\n→ Neither worked — need different approach");
  } else {
    console.log("\n→ System append works better (unexpected)");
  }
}

main().catch(console.error);
