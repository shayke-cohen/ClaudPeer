# Agent Groups — Design Spec

> Stale note (2026-03-29): this design predates the project-first shell. Groups still exist as reusable team templates, but they are no longer a primary top-level sidebar section; they now surface inside each project's Team subsection and start project-owned threads.

**Date:** 2026-03-24
**Status:** Approved

---

## Context

Odyssey supports multi-agent conversations today — users select multiple agents in NewSessionSheet and a group chat begins. But there's no concept of a saved group: no way to name a team, give it a shared instruction, re-use it, or share it with peers. Every group must be reconstituted from scratch each time.

This spec adds Agent Groups as first-class entities: named, reusable team templates with a shared instruction, per-group icon/color, a default mission, conversation history, and peer sharing.

**Outcome:** Users can define "Dev Squad", "Product Crew", etc. once, then start group chats from the sidebar in one click.

---

## Decisions Made

| Question | Decision |
|---|---|
| Group instruction delivery | Injected as a `.system` ConversationMessage at conversation start |
| Navigation placement | Dedicated "Groups" section in SidebarView (above Agents) |
| Start chat flow | Click group row → immediate new conversation (no sheet) |
| New default agents | Product Manager, Analyst, Designer (total: 10 agents) |
| Additional features | Icon + color, default mission, group history, peer sharing |

---

## Data Model

### New: `AgentGroup` SwiftData model

**File:** `Odyssey/Models/AgentGroup.swift`

```swift
@Model final class AgentGroup {
    var id: UUID
    var name: String
    var groupDescription: String
    var icon: String           // emoji
    var color: String          // named color matching Agent.color convention
    var groupInstruction: String
    var defaultMission: String?
    var agentIds: [UUID]       // ordered
    var sortOrder: Int
    var createdAt: Date
    // Origin (enum-flattened per SwiftData pattern):
    var originKind: String     // "local" | "peer" | "imported" | "builtin"
    var originPeerName: String?
    var originRemoteId: UUID?
    @Transient var origin: AgentGroupOrigin { … }
}
```

### Modified: `Conversation`

**File:** `Odyssey/Models/Conversation.swift`

Add `var sourceGroupId: UUID?` — links a conversation back to the group that spawned it. Optional, nil for all existing conversations (lightweight migration safe).

### Model Container

**File:** `Odyssey/App/OdysseyApp.swift`

Add `AgentGroup.self` to the `ModelContainer(for:...)` list.

---

## New Default Agents (3)

New JSON files in `Odyssey/Resources/DefaultAgents/`:

| File | Name | Icon | Color | Role |
|---|---|---|---|---|
| `product-manager.json` | Product Manager | `chart.bar.doc.horizontal` | indigo | Product strategy, PRDs, roadmap |
| `analyst.json` | Analyst | `chart.pie` | teal | Data analysis, SQL, insights |
| `designer.json` | Designer | `paintpalette` | pink | UX/UI feedback, design systems |

`DefaultsSeeder.agentFiles` updated to include these 3.

---

## 12 Built-in Groups

Seeded by a new `DefaultsSeeder.seedGroupsIfNeeded(container:)` method (separate UserDefaults key: `odyssey.groupsSeeded` so existing users get groups seeded on next launch even if agents were already seeded).

| # | Name | Agents | Category |
|---|---|---|---|
| 1 | Dev Squad | Coder · Reviewer · Tester | Engineering |
| 2 | Code Review Pair | Coder · Reviewer | Engineering |
| 3 | Full Stack Team | Coder · Reviewer · Tester · DevOps | Engineering |
| 4 | DevOps Pipeline | Coder · Tester · DevOps | Engineering |
| 5 | Security Audit | Coder · Reviewer · Tester | Engineering |
| 6 | Plan & Build | Orchestrator · Coder · Tester | Planning |
| 7 | Product Crew | Product Manager · Researcher · Analyst | Planning |
| 8 | PM + Dev | Product Manager · Coder · Reviewer · Tester | Planning |
| 9 | Content Studio | Researcher · Writer · Reviewer | Content |
| 10 | Growth Team | Product Manager · Analyst · Writer | Content |
| 11 | Design Review | Designer · Coder · Reviewer | Design |
| 12 | Full Ensemble | All 10 agents | Full |

---

## Group Instruction Injection

**File:** `Odyssey/Services/GroupPromptBuilder.swift`

Add `groupInstruction: String? = nil` parameter to `buildMessageText(...)`. When present, prepend:

```
[Group Context]
{instruction}
---
```

before the delta transcript block.

**File:** `Odyssey/Views/MainWindow/ChatView.swift`

Before calling `buildMessageText`, fetch `groupInstruction` from `Conversation.sourceGroupId`:

```swift
let groupInstruction: String? = {
    guard let gid = conversation.sourceGroupId else { return nil }
    let desc = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == gid })
    return (try? modelContext.fetch(desc).first)?.groupInstruction
}()
```

---

## AppState Changes

**File:** `Odyssey/App/AppState.swift`

- Add `@Published var showGroupLibrary = false`
- Add `func startGroupChat(group: AgentGroup, modelContext: ModelContext)`:
  1. Resolve agents from `group.agentIds`
  2. Create `Conversation` with `topic = group.name`, `sourceGroupId = group.id`
  3. Inject group instruction as `.system` ConversationMessage
  4. Create one `Session` per agent + matching `Participant`
  5. Call `GroupWorkingDirectory.ensureShared(...)`
  6. `try? modelContext.save()`
  7. Set `selectedConversationId = conversation.id`

---

## New Views

**Directory:** `Odyssey/Views/GroupLibrary/`

| File | Description |
|---|---|
| `GroupCardView.swift` | Card showing icon, name, agent chips, Start/Edit buttons. Pattern: `AgentCardView` |
| `GroupLibraryView.swift` | Sheet with search, filter (All/Mine/Built-in/Imported), grid of cards. Pattern: `AgentLibraryView` |
| `GroupEditorView.swift` | Form sheet: name, emoji icon picker, color swatches, instruction TextEditor, default mission field, agent multi-select, past chats (read-only list of conversations with matching sourceGroupId). |
| `GroupSidebarRowView.swift` | Compact row for SidebarView: icon + name + "N agents" badge. |

---

## SidebarView Changes

**File:** `Odyssey/Views/MainWindow/SidebarView.swift`

Add "Groups" section above the Agents section:
- `@Query(sort: \AgentGroup.sortOrder) var groups: [AgentGroup]`
- Section header "Groups" with `+` button → `appState.showGroupLibrary = true`
- One `GroupSidebarRowView` per group
- Clicking a row → `appState.startGroupChat(group:, modelContext:)`
- Right-click context menu: Edit, Duplicate, Share, Delete

---

## MainWindowView Changes

**File:** `Odyssey/Views/MainWindow/MainWindowView.swift`

Add `.sheet(isPresented: $appState.showGroupLibrary) { GroupLibraryView() }` alongside existing `showAgentLibrary` sheet.

---

## Peer Sharing

**File:** `Odyssey/Services/PeerCatalogServer.swift`

Extend the catalog HTTP response to include groups:
- Fetch `AgentGroup` entities with `originKind != "peer"`
- Serialize to JSON (id, name, description, icon, color, groupInstruction, defaultMission, agentIds mapped to agent names)
- Add to catalog payload under `"groups"` key

**File:** `Odyssey/Views/P2P/PeerNetworkView.swift` (or `PeerAgentImporter.swift`)

Add "Import Groups" alongside existing agent import:
- Decode groups from peer catalog
- Create `AgentGroup` with `originKind = "imported"`, `originPeerName = peerName`, `originRemoteId = group.id`

---

## Accessibility Identifiers

| Identifier | Element |
|---|---|
| `sidebar.groupsSection` | Groups section container |
| `sidebar.groupRow.{id}` | Each group row |
| `sidebar.groupsAddButton` | + button in Groups section header |
| `groupLibrary.list` | Group card grid |
| `groupLibrary.searchField` | Search bar |
| `groupLibrary.newGroupButton` | New Group button |
| `groupCard.startButton` | Start Chat button |
| `groupCard.editButton` | Edit button |
| `groupCard.name` | Group name label |
| `groupEditor.nameField` | Name text field |
| `groupEditor.instructionField` | Group instruction TextEditor |
| `groupEditor.defaultMissionField` | Default mission field |
| `groupEditor.agentPicker` | Agent selection area |
| `groupEditor.saveButton` | Save button |
| `groupEditor.cancelButton` | Cancel button |

---

## project.yml

Add all new Swift source files to the `Odyssey` target sources in `project.yml`. After changes, run `xcodegen generate`.

New source paths to add:
- `Odyssey/Models/AgentGroup.swift`
- `Odyssey/Views/GroupLibrary/GroupCardView.swift`
- `Odyssey/Views/GroupLibrary/GroupLibraryView.swift`
- `Odyssey/Views/GroupLibrary/GroupEditorView.swift`
- `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift`

---

## Verification

1. **First launch (clean state):** Delete app data, launch → confirm 10 agents and 12 groups seeded in DefaultsSeeder output
2. **Existing install:** Launch with existing data (agents already seeded) → confirm groups are seeded without duplicating agents
3. **Sidebar:** Groups section appears with 12 built-in rows
4. **Start chat:** Click "Dev Squad" → new conversation opens with Coder, Reviewer, Tester as participants; first message in thread is the group instruction system message
5. **Group instruction in prompt:** Send a message → confirm GroupPromptBuilder prepends `[Group Context]` block in the constructed prompt
6. **CRUD:** Create new group → appears in sidebar and Group Library; edit name → updates everywhere; delete → removed from sidebar
7. **Default mission:** Set a default mission on a group → when starting a chat from that group, the mission field is pre-filled
8. **Group history:** Past conversations started from a group appear in the editor's history section
9. **Peer sharing:** Export group from PeerCatalogServer catalog → import on another instance → group appears with `originKind = "imported"`
10. **Accessibility:** `xcodegen generate` → build → run `mcp__appxray__inspect` on GroupLibraryView elements
