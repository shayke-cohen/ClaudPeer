# Workspace Picker Redesign & Attach GitHub Repo

**Date**: 2026-03-25
**Status**: Draft

## Context

The New Session sheet's workspace selection is fragmented: a GitHub workspace section only appears for agents with a `githubRepo` field, while the directory field is buried inside the Session Options disclosure. Users also have no way to select from recent directories/repos, and cannot attach a GitHub repo to an existing conversation.

This spec unifies workspace selection into a tabbed UI, adds recent-items chips, and introduces an "Attach GitHub Repo" action for existing chats.

## Three Features

### Feature 1: Recent Directory Chips
Show recently-used directories as clickable chips above the directory text field in the New Session sheet. Uses existing `RecentDirectories` service.

### Feature 2: Tabbed Workspace Picker (Local Directory | GitHub Repo)
Replace the split directory-field + GitHub-workspace-section with a unified tabbed "Workspace" section, always visible, available for any session type (not gated on `agent.githubRepo`).

### Feature 3: Attach GitHub Repo to Existing Chat
Add the ability to attach a GitHub repo to a running conversation via a sheet accessible from both the Chat header menu and the Inspector toolbar.

---

## Data Layer

### New Service: `RecentRepos.swift`
Mirrors `RecentDirectories` structure (but skips `fileExists` check since repos are remote):
- File: `ClaudeStudio/Services/RecentRepos.swift`
- Persists to `~/.claudestudio/recent-repos.json`
- `enum RecentRepos` with static methods: `load() -> [String]`, `add(_ repo: String)`
- Max 10 entries, stores `org/repo` or full URL strings
- Validates format (contains `/` or starts with `https://` / `git@`) instead of filesystem existence

### No Model Changes
Existing `Session.WorkspaceType` enum already covers all cases:
- `.explicit(path:)` for local directories
- `.githubClone(repoUrl:)` for cloned repos
- `.worktree(repoUrl:, branch:)` for worktrees

### Wire Protocol: `session.updateCwd` Command (Feature 3)

Features 1-2 need no wire changes (workspace is resolved before session creation). Feature 3's "Clone & switch" mode requires updating the sidecar's frozen `cwd` for a running session:

- The sidecar's `SessionRegistry` stores `AgentConfig` immutably at creation (`session-registry.ts` line 18). `buildQueryOptions()` reads `config.workingDirectory` on every `query()` call (`session-manager.ts` line 283).
- To change `cwd` mid-session, we need:

  1. **Sidecar**: Add `updateConfig(id, updates)` to `SessionRegistry` — merges partial config updates
  2. **Sidecar**: Add `session.updateCwd` handler in `ws-server.ts` — calls `registry.updateConfig(id, { workingDirectory: newCwd })`
  3. **Swift**: Add `SidecarCommand.sessionUpdateCwd(sessionId: String, workingDirectory: String)` case + encoding
  4. **Swift types**: Add `session.updateCwd` to `SidecarCommand` union in `types.ts`

Files affected:

- `sidecar/src/stores/session-registry.ts` — add `updateConfig()` method
- `sidecar/src/ws-server.ts` — add handler
- `sidecar/src/types.ts` — add command type
- `ClaudeStudio/Services/SidecarProtocol.swift` — add Swift command case + encoding

---

## UI Design

### Workspace Section (Features 1 + 2)

Replaces both the current `githubWorkspaceSection(agent:)` and the directory field inside `optionsSection`. Placed between the agent picker and the Session Options disclosure, always visible.

**State changes in `NewSessionSheet`:**
- Remove `SessionDirMode` enum
- Add `WorkspaceTab` enum: `.localDirectory`, `.githubRepo`
- Add `GitHubWorkspaceMode` enum: `.clone`, `.worktree`
- New `@State`: `workspaceTab`, `githubRepoInput`, `githubBranch`, `githubMode`, `recentDirs`, `recentRepos`
- Remove the `singleAgentWithGithub` computed property and its gating logic

**Layout:**

```
Workspace (headline)

[ Local Directory | GitHub Repo ]     ← segmented picker

── Local Directory tab ──
Recent: [ClaudeStudio] [appxray] [project-x]    ← capsule chips, horizontal scroll
Directory: [__/path/to/dir__________] 📁      ← text field + browse button

── GitHub Repo tab ──
Recent: [acme/backend] [acme/frontend]        ← capsule chips
Repo:   [__org/repo or URL__________]         ← text field
Branch: [__main___________]                   ← text field, default "main"
Mode:   [ Clone | Worktree ]                  ← segmented picker
Path:   ~/.claudestudio/repos/acme-backend       ← computed, read-only
[Validate / Clone]                            ← action button
── Issue (optional) ──
Issue: [#__] [Fetch]                          ← same as existing
```

**Behavior:**
- Agent's `githubRepo` pre-populates `githubRepoInput` when selecting a single agent with a repo (but always editable)
- Agent's `defaultWorkingDirectory` pre-populates the directory field
- Recent chips: max ~6 visible, show short name, full path as tooltip, tap fills field
- GitHub tab available for ALL sessions (freeform, multi-agent, any agent)
- The directory field is removed from `optionsSection`
- Sheet height: use a fixed height (~620) since workspace section is always visible, no conditional sizing

**Empty directory field fallback:** When the Local Directory tab's text field is empty, fall through to existing defaults: `agent.defaultWorkingDirectory` → `appState.instanceWorkingDirectory` → empty string (same as current `inheritOrDefault` behavior).

**Multi-agent (group) sessions with GitHub tab:**

- All agents in a group share one GitHub clone (single repo input, one clone operation)
- After creating sessions, `GroupWorkingDirectory.ensureShared()` still runs to normalize paths
- Each session gets `workspaceType = .githubClone(repoUrl:)` with the same clone path
- If agents have different `githubRepo` fields, the user's explicit input takes precedence

**`createSessionAsync()` simplification:**

```swift
switch workspaceTab {
case .localDirectory:
    // Use workingDirectory text field → workspaceType = .explicit(path:)
    // Empty field → fall through to agent/instance defaults
case .githubRepo:
    if githubMode == .clone:
        // ensureClone once → all sessions get .githubClone(repoUrl:)
    else:
        // ensureWorktree once → all sessions get .worktree(repoUrl:, branch:)
    RecentRepos.add(repo)
}
// For multi-agent: GroupWorkingDirectory.ensureShared() normalizes afterward
```

**Recent chips accessibility:** Each chip gets both `.accessibilityIdentifier` and `.accessibilityLabel` — e.g., `"Select recent directory: ClaudeStudio at /Users/shayco/ClaudeStudio"`.

### Attach Repo Sheet (Feature 3)

**New file**: `ClaudeStudio/Views/MainWindow/AttachRepoSheet.swift`

**Entry points (both):**

1. Chat view — "..." header menu item: "Attach GitHub Repo..."
2. Inspector view — button in workspace section toolbar. Note: the Inspector's workspace section currently only renders when `hasWorkingDirectory` is true. The "Attach Repo" button must be shown regardless — either by always rendering a minimal workspace section, or by placing the button outside the `hasWorkingDirectory` guard (e.g., in the inspector's top toolbar).

**Layout:**
```
Attach GitHub Repository (headline)

Recent: [acme/backend] [acme/frontend]    ← capsule chips

Repo:   [__org/repo or URL__________]
Branch: [__main___________]

(●) Clone & work in repo
    Changes working directory to clone path
( ) Clone as reference
    Keeps current directory, agent gets repo context

[For group chats: ☑ Apply to all sessions]

              [Cancel]    [Attach]
```

**Behavior:**
- **Clone & switch**: `GitHubIntegration.ensureClone()` → update `Session.workingDirectory` + `workspaceType` → send system message → refresh inspector file tree
- **Reference only**: `GitHubIntegration.ensureClone()` → send system message with clone path info → working dir unchanged
- Group chats: checkbox to apply to all sessions or just primary (default: all)
- Warning if overwriting an existing working directory in "clone & switch" mode
- Freeform chats (no sessions): only "reference only" available
- Uses `RecentRepos.add()` on successful attach

---

## Files to Change

### New Files (2)

| File | Purpose |
|------|---------|
| `ClaudeStudio/Services/RecentRepos.swift` | Recent GitHub repos persistence (mirrors `RecentDirectories`) |
| `ClaudeStudio/Views/MainWindow/AttachRepoSheet.swift` | Sheet for attaching a repo to existing conversations |

### Modified Files (7)

| File | Changes |
|------|---------|
| `ClaudeStudio/Views/MainWindow/NewSessionSheet.swift` | Replace `SessionDirMode` with `WorkspaceTab` + `GitHubWorkspaceMode`; remove `singleAgentWithGithub` gating; add tabbed workspace section with chips; remove directory from optionsSection; simplify `createSessionAsync()` |
| `ClaudeStudio/Views/MainWindow/ChatView.swift` | Add "Attach GitHub Repo" menu item in header menu; add `@State showAttachRepoSheet`; add `.sheet` modifier |
| `ClaudeStudio/Views/MainWindow/InspectorView.swift` | Add "Attach Repo" button (outside `hasWorkingDirectory` guard); add `@State showAttachRepoSheet`; add `.sheet` modifier |
| `ClaudeStudio/Services/SidecarProtocol.swift` | Add `sessionUpdateCwd` case to `SidecarCommand` + encoding |
| `sidecar/src/types.ts` | Add `session.updateCwd` to `SidecarCommand` union |
| `sidecar/src/stores/session-registry.ts` | Add `updateConfig(id, updates)` method |
| `sidecar/src/ws-server.ts` | Add `session.updateCwd` handler |

Also update `ClaudeStudio/CLAUDE.md` — add `AttachRepoSheet` to accessibility identifier prefix map.

### Unchanged (reused as-is)

- `Session.swift` — existing `WorkspaceType` covers all cases
- `Agent.swift` — `githubRepo` becomes a pre-population hint, not a gate
- `WorkspaceResolver.swift` — all path resolution already works
- `GitHubIntegration.swift` — all clone/worktree/issue operations already work
- `RecentDirectories.swift` — used as-is from new chip locations
- `AgentProvisioner.swift` — receives resolved paths, unaffected

---

## Accessibility Identifiers

| Element | Identifier |
|---------|------------|
| Workspace tab picker | `newSession.workspaceTabPicker` |
| Recent dir chip | `newSession.recentDirChip.{index}` |
| Recent repo chip (new session) | `newSession.recentRepoChip.{index}` |
| Repo input field | `newSession.githubRepoField` |
| Branch input field | `newSession.githubBranchField` |
| GitHub mode picker | `newSession.githubModePicker` |
| Validate/Clone button | `newSession.githubValidateButton` (existing) |
| Attach Repo sheet | `attachRepo.*` |
| Attach Repo - repo field | `attachRepo.repoField` |
| Attach Repo - branch field | `attachRepo.branchField` |
| Attach Repo - mode picker | `attachRepo.modePicker` |
| Attach Repo - apply all toggle | `attachRepo.applyAllToggle` |
| Attach Repo - attach button | `attachRepo.attachButton` |
| Attach Repo - cancel button | `attachRepo.cancelButton` |
| Chat menu item | `chat.moreOptions.attachRepo` |
| Inspector button | `inspector.attachRepoButton` |

---

## Verification

1. **New Session — Local Directory tab**: Open New Session sheet → verify recent dir chips appear → click a chip → verify directory field fills → browse still works → start session → verify directory is used
2. **New Session — GitHub Repo tab**: Switch to GitHub tab → verify recent repo chips → enter a repo → clone → verify session starts in clone path → verify repo added to recent repos
3. **New Session — Agent pre-population**: Select an agent with `githubRepo` → verify tab auto-switches to GitHub and repo field is pre-populated → deselect → verify fields clear or stay as user-edited
4. **New Session — Multi-agent**: Select 2+ agents → verify both tabs still available → verify GitHub tab works for group sessions
5. **Attach Repo — Clone & switch**: Open existing chat → menu → Attach GitHub Repo → enter repo → select "Clone & work in repo" → verify clone → verify working dir updates → verify inspector refreshes → verify agent receives system message
6. **Attach Repo — Reference only**: Same flow but select "Reference only" → verify working dir unchanged → verify agent receives repo path info
7. **Attach Repo — Group chat**: Open group chat → attach → verify "Apply to all sessions" checkbox → test both states
8. **Recent items persistence**: Start multiple sessions with different dirs/repos → verify recent lists persist across app restarts
