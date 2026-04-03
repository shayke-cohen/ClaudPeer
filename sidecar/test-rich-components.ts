#!/usr/bin/env bun
/**
 * Test script for rich chat components via WebSocket.
 * Creates a session and sends a prompt that triggers each rich component type.
 * Run: bun run test-rich-components.ts
 */

const WS_URL = "ws://localhost:9849";

function uuid() {
  return crypto.randomUUID().toUpperCase();
}

async function main() {
  console.log("🧪 Rich Component Test Suite\n");

  const ws = new WebSocket(WS_URL);

  await new Promise<void>((resolve, reject) => {
    ws.onopen = () => resolve();
    ws.onerror = (e) => reject(e);
  });

  // Wait for sidecar.ready handshake
  await new Promise<void>((resolve) => {
    ws.onmessage = (ev) => {
      console.log("🤝 Handshake:", String(ev.data).substring(0, 80));
      resolve();
    };
  });

  const sessionId = uuid();
  console.log(`\n📋 Session ID: ${sessionId}`);
  console.log("   Open this session in Odyssey to see the test.\n");

  // Create session with comprehensive test instructions
  ws.send(JSON.stringify({
    type: "session.create",
    conversationId: sessionId,
    agentConfig: {
      name: "Component Tester",
      systemPrompt: `You are a visual component testing agent. Your job is to demonstrate each rich display tool available to you, one at a time, with a brief text explanation before each.

IMPORTANT: After each tool call, output a short text line confirming what was displayed before moving to the next tool.

## Test Sequence

Step 1: Call render_content with format="html" and this content:
<div style="padding:20px; background:linear-gradient(135deg,#667eea,#764ba2); border-radius:12px; color:white; font-family:system-ui;">
  <h2 style="margin:0 0 8px">✅ HTML Rendering Works!</h2>
  <p style="margin:0; opacity:0.9">This card was rendered inline via the render_content tool.</p>
  <div style="margin-top:12px; display:flex; gap:8px;">
    <span style="background:rgba(255,255,255,0.2); padding:4px 12px; border-radius:20px; font-size:13px;">Rich Content</span>
    <span style="background:rgba(255,255,255,0.2); padding:4px 12px; border-radius:20px; font-size:13px;">Inline Cards</span>
  </div>
</div>

Step 2: Call render_content with format="mermaid" and title="Architecture Diagram":
graph TD
    A[User] --> B[Odyssey]
    B --> C[Sidecar]
    C --> D[Claude API]
    C --> E[MCP Tools]
    E --> F[ask_user]
    E --> G[render_content]
    E --> H[show_progress]

Step 3: Call show_progress with id="test-progress", title="Build Pipeline", and steps:
- "Compile sources" status="done"
- "Run tests" status="running"
- "Deploy staging" status="pending"
- "Smoke tests" status="pending"

Step 4: Call suggest_actions with these suggestions:
- label="Run all tests", message="run all component tests again"
- label="Show HTML demo", message="show me a styled HTML card"
- label="Try ask_user", message="ask me a question"

Step 5: Call ask_user with input_type="toggle", question="Did all the visual components above render correctly?"

Step 6: Call ask_user with input_type="rating", question="Rate the visual quality of the components", input_config={max_rating: 5, rating_labels: ["Poor", "Fair", "Good", "Great", "Excellent"]}

Step 7: Call ask_user with input_type="slider", question="How confident are you that everything works?", input_config={min: 0, max: 100, step: 10, unit: "%"}

Step 8: Call ask_user with input_type="form", question="Quick feedback form", input_config={fields: [{name: "favorite", label: "Favorite component", type: "text", required: true, placeholder: "e.g. HTML card"}, {name: "score", label: "Overall score", type: "number", placeholder: "1-10"}, {name: "newsletter", label: "Subscribe to updates", type: "toggle"}]}

Step 9: Call ask_user with input_type="dropdown", question="Pick your favorite color theme", options: [{label: "Ocean Blue", description: "Cool, professional"}, {label: "Forest Green", description: "Natural, calm"}, {label: "Sunset Orange", description: "Warm, energetic"}, {label: "Royal Purple", description: "Creative, bold"}, {label: "Midnight Dark", description: "Sleek, modern"}]

Step 10: Call ask_user with regular options (default input_type), question="What should we test next?", options: [{label: "Repeat all tests", description: "Run the full suite again"}, {label: "HTML stress test", description: "Complex HTML with tables, charts"}, {label: "Done", description: "All tests complete"}]

EXECUTE ALL 10 STEPS IN ORDER. Do not skip any.`,
      allowedTools: [],
      mcpServers: [],
      model: "claude-sonnet-4-6",
      maxTurns: 30,
      maxThinkingTokens: 5000,
      workingDirectory: "/tmp",
      skills: [],
      interactive: true,
    },
  }));

  // Listen for events
  const events: string[] = [];
  ws.onmessage = (ev) => {
    const data = JSON.parse(String(ev.data));
    if (data.sessionId === sessionId) {
      const brief = `${data.type}${data.tool ? ` tool=${data.tool}` : ""}${data.format ? ` format=${data.format}` : ""}`;
      events.push(brief);

      if (data.type === "stream.richContent") {
        console.log(`  ✅ Rich content: format=${data.format} title="${data.title ?? ""}" (${data.content?.length ?? 0} chars)`);
      } else if (data.type === "stream.progress") {
        console.log(`  ✅ Progress: "${data.title}" (${data.steps?.length ?? 0} steps)`);
      } else if (data.type === "stream.suggestions") {
        console.log(`  ✅ Suggestions: ${data.suggestions?.map((s: any) => s.label).join(", ")}`);
      } else if (data.type === "agent.question") {
        const inputType = data.inputType ?? "options";
        console.log(`  ✅ Question (${inputType}): "${data.question?.substring(0, 60)}"`);
        // Auto-answer questions so the test continues
        setTimeout(() => {
          ws.send(JSON.stringify({
            type: "session.questionAnswer",
            sessionId,
            questionId: data.questionId,
            answer: inputType === "toggle" ? "Yes" : inputType === "rating" ? "4" : inputType === "slider" ? "75%" : "looks good",
            selectedOptions: inputType === "toggle" ? ["yes"] : undefined,
          }));
          console.log(`  📤 Auto-answered: "${inputType}"`);
        }, 2000);
      } else if (data.type === "stream.toolCall") {
        console.log(`  🔧 Tool call: ${data.tool}`);
      } else if (data.type === "session.result") {
        console.log(`\n✅ Session complete. Cost: $${data.cost?.toFixed(4)}`);
      }
    }
  };

  // Send the test prompt
  await new Promise((r) => setTimeout(r, 500));
  ws.send(JSON.stringify({
    type: "session.message",
    sessionId,
    text: "Execute the test sequence now. Start with step 1.",
  }));

  console.log("📤 Test prompt sent. Watching for events...\n");
  console.log("Checklist:");
  console.log("  □ HTML rich content card");
  console.log("  □ Mermaid diagram");
  console.log("  □ Progress tracker");
  console.log("  □ Suggestion chips");
  console.log("  □ Toggle (Yes/No)");
  console.log("  □ Star rating");
  console.log("  □ Slider");
  console.log("  □ Form (multi-field)");
  console.log("  □ Dropdown");
  console.log("  □ Options (button list)");
  console.log("");

  // Wait for completion (max 5 min)
  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => {
      console.log("\n⏰ Timeout after 5 minutes");
      resolve();
    }, 5 * 60 * 1000);

    const check = setInterval(() => {
      if (events.some((e) => e.includes("session.result"))) {
        clearInterval(check);
        clearTimeout(timeout);
        setTimeout(resolve, 1000);
      }
    }, 500);
  });

  // Summary
  console.log("\n📊 Event Summary:");
  const richContent = events.filter((e) => e.includes("stream.richContent")).length;
  const progress = events.filter((e) => e.includes("stream.progress")).length;
  const suggestions = events.filter((e) => e.includes("stream.suggestions")).length;
  const questions = events.filter((e) => e.includes("agent.question")).length;
  const toolCalls = events.filter((e) => e.includes("stream.toolCall")).length;

  console.log(`  Rich content cards: ${richContent}/2 (html + mermaid)`);
  console.log(`  Progress trackers:  ${progress}/1`);
  console.log(`  Suggestion chips:   ${suggestions}/1`);
  console.log(`  Questions asked:    ${questions}/5 (toggle, rating, slider, form, dropdown, options)`);
  console.log(`  Total tool calls:   ${toolCalls}`);

  const allPassed = richContent >= 2 && progress >= 1 && suggestions >= 1 && questions >= 5;
  console.log(`\n${allPassed ? "✅ ALL COMPONENTS TESTED" : "⚠️  SOME COMPONENTS MISSING"}`);

  ws.close();
}

main().catch(console.error);
