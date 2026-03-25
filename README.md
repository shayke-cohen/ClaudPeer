# ClaudeStudio

A native macOS developer tool for orchestrating multiple Claude AI agent sessions. Agents chat with users and with each other, share knowledge through a blackboard, collaborate on files through shared workspaces, and discover each other across the local network.

## Architecture

ClaudeStudio is a **two-process** app:

```
┌─────────────────────────────────┐     WebSocket (JSON)     ┌─────────────────────────────────┐
│     Swift macOS App             │◄────────────────────────►│     TypeScript Sidecar           │
│                                 │      localhost:9849       │                                 │
│  • SwiftUI + SwiftData          │                          │  • Bun runtime                   │
│  • UI, persistence, P2P         │                          │  • Claude Agent SDK sessions     │
│  • Agent provisioning           │                          │  • Blackboard (HTTP + disk)      │
│  • Conversation model           │                          │  • PeerBus tools (planned)       │
└─────────────────────────────────┘                          └─────────────────────────────────┘
```

**Why two processes?** The Claude Agent SDK is TypeScript-only. The Swift app owns the UI and persistence (what SwiftUI/SwiftData do best), while the sidecar owns AI sessions and agent orchestration (what the SDK does best).

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| AI interface | Claude Agent SDK (TypeScript) | Persistent sessions, hooks, custom tools, native subagents |
| Sidecar runtime | Bun | Fast startup, TypeScript-native, single binary |
| App ↔ Sidecar | WebSocket on localhost | Low-latency, bidirectional streaming |
| Persistence | SwiftData | Modern, CloudKit sync potential, Swift-native |
| Concurrency | Swift 6 strict concurrency | `@MainActor` app state, `AsyncStream` for events |

## Project Structure

```
ClaudeStudio/
├── ClaudeStudio.xcodeproj           # Xcode project
├── project.yml                   # XcodeGen spec (macOS 14+, Swift 6)
├── system-plan-vision.md         # Full architecture vision & roadmap
│
├── ClaudeStudio/                    # Swift macOS App
│   ├── App/
│   │   ├── ClaudeStudioApp.swift    # @main, WindowGroup, model container
│   │   └── AppState.swift        # Global state: sidecar status, selections, streaming
│   ├── Models/                   # SwiftData @Model types
│   │   ├── Agent.swift           # Agent template (skills, MCPs, permissions, instance policy)
│   │   ├── Session.swift         # Running agent instance (status, mode, workspace)
│   │   ├── Conversation.swift    # Unified conversation (user↔agent and agent↔agent)
│   │   ├── ConversationMessage.swift
│   │   ├── Participant.swift     # .user or .agentSession
│   │   ├── Skill.swift           # Managed skill in pool
│   │   ├── MCPServer.swift       # MCP server config (.stdio or .http)
│   │   ├── PermissionSet.swift   # Reusable permission presets
│   │   ├── SharedWorkspace.swift # Shared directory for multi-agent collaboration
│   │   ├── BlackboardEntry.swift # Key-value knowledge store entry
│   │   └── Peer.swift            # Discovered network peer
│   ├── Services/
│   │   ├── SidecarManager.swift  # Launch Bun, WebSocket client, reconnect
│   │   ├── SidecarProtocol.swift # Wire types: commands, events, AgentConfig
│   │   ├── AgentProvisioner.swift# Compose AgentConfig from SwiftData models
│   │   ├── GroupPromptBuilder.swift   # Group transcript + user-line prompts; peer-notify text
│   │   └── GroupPeerFanOutContext.swift # Budget/dedup for automatic peer fan-out
│   ├── Views/
│   │   ├── MainWindow/           # NavigationSplitView: sidebar, chat, inspector, new session sheet
│   │   ├── AgentLibrary/         # Agent grid + editor
│   │   └── Components/           # MessageBubble, ToolCallView, TreeNode, etc.
│   └── Resources/
│       ├── Assets.xcassets
│       ├── ClaudeStudio.entitlements
│       ├── DefaultAgents/           # 7 built-in agent definitions (JSON)
│       ├── DefaultSkills/           # 5 ClaudeStudio-specific skills (SKILL.md)
│       │   ├── peer-collaboration/
│       │   ├── blackboard-patterns/
│       │   ├── delegation-patterns/
│       │   ├── workspace-collaboration/
│       │   └── agent-identity/
│       ├── DefaultMCPs.json         # Pre-registered MCP server configs
│       ├── DefaultPermissionPresets.json  # 5 permission presets
│       └── SystemPromptTemplates/   # 3 reusable prompt templates
│
└── sidecar/                      # TypeScript Sidecar (Bun + Agent SDK)
    ├── package.json              # @anthropic-ai/claude-agent-sdk
    ├── tsconfig.json
    ├── src/
    │   ├── index.ts              # Entry: boot WS + HTTP servers
    │   ├── ws-server.ts          # WebSocket command router
    │   ├── http-server.ts        # Blackboard REST API
    │   ├── session-manager.ts    # Agent SDK query() lifecycle
    │   ├── types.ts              # Shared command/event types
    │   └── stores/
    │       ├── blackboard-store.ts   # In-memory + JSON disk persistence
    │       └── session-registry.ts   # Per-session state tracking
    └── test/
        └── sidecar-api.test.ts   # Integration tests (requires running sidecar)
```

## Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 16+** with Swift 6
- **Bun** runtime (`brew install oven-sh/bun/bun` or `curl -fsSL https://bun.sh/install | bash`)
- **Anthropic API key** set as `ANTHROPIC_API_KEY` environment variable (used by the Agent SDK)

## Setup

### 1. Clone and install sidecar dependencies

```bash
git clone <repo-url> ClaudeStudio
cd ClaudeStudio/sidecar
bun install
```

### 2. Open in Xcode

```bash
open ClaudeStudio.xcodeproj
```

Or generate via XcodeGen if needed:

```bash
xcodegen generate
```

### 3. Build and run

Build the `ClaudeStudio` target in Xcode (Cmd+R). The app automatically:
1. Launches the Bun sidecar process
2. Connects via WebSocket on `localhost:9849`
3. Logs sidecar output to `~/.claudestudio/logs/sidecar.log`

### Running the sidecar standalone (development)

```bash
cd sidecar
bun run dev          # watch mode
# or
bun run start        # single run
```

Environment variables:
- `CLAUDESTUDIO_WS_PORT` — WebSocket port (default: `9849`)
- `CLAUDESTUDIO_HTTP_PORT` — Blackboard HTTP API port (default: `9850`)

## Launch Parameters

ClaudeStudio accepts CLI arguments and a `claudestudio://` URL scheme for scripting, automation, and deeplinks.

### CLI arguments

```bash
# Freeform chat (no agent)
open ClaudeStudio.app --args --chat

# Start with a specific agent
open ClaudeStudio.app --args --agent Coder

# Agent with auto-sent prompt and custom working directory
open ClaudeStudio.app --args --agent Coder --prompt "Fix the failing tests" --workdir ~/code/my-project

# Group chat in autonomous mode
open ClaudeStudio.app --args --group "Dev Team" --autonomous --prompt "Ship the login feature"

# Combined with --instance for isolated workspaces
open -n ClaudeStudio.app --args --instance project-x --agent Coder --workdir ~/code/project-x
```

| Flag | Description |
|---|---|
| `--chat` | Open a freeform chat (no agent) |
| `--agent <name>` | Start a session with a named agent (case-insensitive) |
| `--group <name>` | Start a group chat with a named group (case-insensitive) |
| `--prompt <text>` | Initial message, auto-sent when sidecar connects |
| `--workdir <path>` | Override the session working directory |
| `--autonomous` | Start in autonomous mode |
| `--instance <name>` | Run in an isolated instance (existing flag) |

### URL scheme

```bash
open "claudestudio://chat?prompt=Hello"
open "claudestudio://agent/Coder?prompt=Fix%20the%20tests&workdir=/Users/me/project"
open "claudestudio://group/Dev%20Team?autonomous=true"
```

URL format: `claudestudio://<mode>/<name>?prompt=...&workdir=...&autonomous=true`

Where `<mode>` is `chat`, `agent`, or `group`. Query parameters are optional.

## Communication Protocol

### Swift → Sidecar (commands)

| Command | Purpose |
|---|---|
| `session.create` | Start a new Agent SDK session with an `AgentConfig` |
| `session.message` | Send a user message to an active session |
| `session.resume` | Resume a previous session by Claude session ID |
| `session.fork` | Fork a conversation at the current point |
| `session.pause` | Pause/abort a running session |

### Sidecar → Swift (events)

| Event | Purpose |
|---|---|
| `stream.token` | Streaming text token from agent |
| `stream.toolCall` | Agent started a tool call |
| `stream.toolResult` | Tool call completed |
| `session.result` | Agent turn completed (with cost) |
| `session.error` | Error in session |
| `peer.chat` | Inter-agent chat message (planned) |
| `peer.delegate` | Task delegation event (planned) |
| `blackboard.update` | Blackboard key changed |

## Blackboard HTTP API

The sidecar exposes a REST API on `localhost:9850` for external integration:

```bash
# Write a value
curl -X POST http://localhost:9850/blackboard/write \
  -H 'Content-Type: application/json' \
  -d '{"key": "research.results", "value": "[\"item1\", \"item2\"]", "writtenBy": "cli"}'

# Read a value
curl http://localhost:9850/blackboard/read?key=research.results

# Query by glob pattern
curl http://localhost:9850/blackboard/query?pattern=research.*

# List all keys
curl http://localhost:9850/blackboard/keys

# Health check
curl http://localhost:9850/blackboard/health
```

## Data Model

The app uses SwiftData with these core entities:

- **Agent** — reusable template (like a class): skills, MCPs, permissions, model, instance policy
- **Session** — running instance (like an object): status, mode, workspace, cost tracking
- **Conversation** — unified communication primitive for user↔agent and agent↔agent; **group chats** attach multiple `Session`s, send each user message to every agent, and **fan out** each assistant reply to other agents via extra `session.message` calls (see `SPEC.md` FR-4.9)
- **Participant** — member of a conversation (`.user` or `.agentSession`)
- **Skill / MCPServer / PermissionSet** — composable building blocks for agents
- **BlackboardEntry** — shared structured knowledge (key-value + metadata)
- **SharedWorkspace** — directory shared between multiple agent sessions
- **Peer** — discovered network peer (P2P, planned)

## Built-in Ecosystem

ClaudeStudio ships with 7 default agents, 5 multi-agent skills, MCP integrations, permission presets, and system prompt templates -- all designed to work together out of the box. Users can modify, duplicate, or delete any default.

### Default Agents

| Agent | Role | Model | Instance Policy | Permissions |
|---|---|---|---|---|
| **Orchestrator** | Breaks tasks into subtasks, delegates to specialists, synthesizes results | opus | `.spawn` | Full Access |
| **Coder** | Writes, edits, and refactors code in shared workspaces | sonnet | `.pool(3)` | Full Access |
| **Reviewer** | Reviews code and PRs; never writes production code | sonnet | `.singleton` | Read Only + git |
| **Researcher** | Gathers information from web, docs, codebases; writes to blackboard | sonnet | `.spawn` | Read Only + web |
| **Tester** | Writes/runs tests, uses Argus for UI testing | sonnet | `.pool(2)` | Full Access |
| **DevOps** | Git workflows, CI/CD, deployment, environment setup | haiku | `.singleton` | Git Only |
| **Writer** | Documentation, READMEs, specs, PRDs, UX copy | sonnet | `.spawn` | Read + Write Docs |

### ClaudeStudio-Specific Skills

- **`peer-collaboration`** -- PeerBus usage: blocking chat vs async, deadlock avoidance, group chat etiquette
- **`blackboard-patterns`** -- Key naming conventions, structured data patterns, subscription strategies
- **`delegation-patterns`** -- Task decomposition, wait strategies, pipeline templates (sequential, parallel, iterative)
- **`workspace-collaboration`** -- Multi-agent file conventions, locking, readiness signaling
- **`agent-identity`** -- ClaudeStudio context injection, peer discovery, self-introduction protocol

### MCP Integrations (pre-registered, user-enabled per agent)

Argus (UI testing), AppXray (runtime inspection), GitHub (issues/PRs), Sentry (error monitoring), Linear/Jira (issue tracking), Slack/Discord (notifications).

### Permission Presets

Full Access, Read Only, Read + Write Docs, Git Only, Sandbox.

See [`system-plan-vision.md` Section 11](system-plan-vision.md#11-built-in-ecosystem) for full specifications.

## Current Status

**Implemented (Phase 1-2):**
- Swift project with SwiftData models for all core entities
- Bun sidecar with Agent SDK `query()` integration
- WebSocket communication (commands + streaming events)
- SidecarManager with process lifecycle and auto-reconnect
- AgentProvisioner composing configs from SwiftData models
- Main window with NavigationSplitView (sidebar, chat, inspector)
- Agent library with editor (Start button launches sessions)
- Blackboard with HTTP REST API and disk persistence
- Working directory resolution (explicit, GitHub clone, agent default, ephemeral)
- New Session sheet with agent picker, model/mode/mission/directory options (Cmd+N)
- Smart conversation auto-naming from first message
- Conversation management: rename, pin, archive, close, delete, duplicate via context menus
- Sidebar polish: pinned section, archived section (collapsible), relative timestamps, message previews, agent icons, swipe actions, empty state
- Chat header: inline rename, close/resume, clear, model pill, live cost display
- Inspector actions: pause/resume/stop buttons, editable topic, "Open in Editor" link
- Group chat: shared transcript per session, sequential user-turn replies, automatic peer notify (`Group chat: peer message`) with bounded extra turns

**Planned (see `system-plan-vision.md`):**
- PeerBus custom tools (peer_chat, peer_delegate, blackboard SDK tools)
- Hook engine (PreToolUse/PostToolUse → real-time UI events)
- Agent-to-agent conversations and delegation
- Shared workspaces
- Built-in ecosystem: 7 default agents, 5 multi-agent skills, MCP configs, permission presets, prompt templates
- First-launch SwiftData seeding from bundled resources
- P2P networking via Bonjour (agent/skill sharing, cross-machine collaboration)

## Runtime Paths

| Path | Purpose |
|---|---|
| `~/.claudestudio/logs/` | Sidecar stdout/stderr logs |
| `~/.claudestudio/blackboard/` | Persisted blackboard JSON files |
| `~/.claudestudio/repos/` | Cloned GitHub repositories |
| `~/.claudestudio/sandboxes/` | Ephemeral session working directories |
| `~/.claudestudio/workspaces/` | Shared multi-agent workspaces |

## License

Private — not yet open-sourced.
