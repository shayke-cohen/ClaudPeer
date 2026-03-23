import SwiftUI
import SwiftData

struct NewSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @Query(sort: \Session.startedAt, order: .reverse) private var recentSessions: [Session]

    /// Agents selected for this conversation (one or more = group-capable).
    @State private var selectedAgentIds: Set<UUID> = []
    @State private var isFreeformChat = false
    @State private var modelOverride = ""
    @State private var sessionMode: SessionMode = .interactive
    @State private var mission = ""
    @State private var workingDirectory = ""
    @State private var showOptions = false
    @State private var didSetInitialDir = false

    private enum SessionDirMode: Int, Hashable {
        case inheritOrDefault = 0
        case customFolder = 1
        case githubClone = 2
        case worktree = 3
    }

    @State private var dirMode: SessionDirMode = .inheritOrDefault
    @State private var worktreeBranch = ""
    @State private var githubIssueNumber = ""
    @State private var fetchedIssueTitle: String?
    @State private var isWorkspacePreparing = false
    @State private var workspacePrepError: String?
    @State private var showCreateFromPrompt = false
    @State private var createFromPromptText = ""
    @Query(sort: \Skill.name) private var allSkills: [Skill]
    @Query(sort: \MCPServer.name) private var allMCPs: [MCPServer]

    private var recentAgents: [Agent] {
        var seen = Set<UUID>()
        var result: [Agent] = []
        for session in recentSessions {
            guard let agent = session.agent, !seen.contains(agent.id) else { continue }
            seen.insert(agent.id)
            result.append(agent)
            if result.count >= 3 { break }
        }
        return result
    }

    private var orderedSelectedAgents: [Agent] {
        agents.filter { selectedAgentIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var singleAgentWithGithub: Agent? {
        guard orderedSelectedAgents.count == 1,
              let a = orderedSelectedAgents.first,
              let r = a.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !r.isEmpty else { return nil }
        return a
    }

    private var canStartSession: Bool {
        (isFreeformChat || !selectedAgentIds.isEmpty) && !isWorkspacePreparing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    createFromPromptSection
                    if !recentAgents.isEmpty {
                        recentAgentsRow
                    }
                    agentPicker
                    if !orderedSelectedAgents.isEmpty {
                        Text("Selected: \(orderedSelectedAgents.map(\.name).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .xrayId("newSession.selectedAgentsSummary")
                    }
                    if orderedSelectedAgents.count == 1, let agent = orderedSelectedAgents.first {
                        if agent.instancePolicyKind == "singleton" {
                            Label("Singleton — new sessions reuse the existing one", systemImage: "1.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .xrayId("newSession.policyLabel")
                        } else if agent.instancePolicyKind == "pool" {
                            Label("Pool (\(agent.instancePolicyPoolMax ?? 3) max) — sessions are load-balanced", systemImage: "square.3.layers.3d")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .xrayId("newSession.policyLabel")
                        }
                    }
                    if let ga = singleAgentWithGithub {
                        githubWorkspaceSection(agent: ga)
                    }
                    optionsSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: singleAgentWithGithub != nil ? 640 : 560)
        .onAppear {
            if !didSetInitialDir, workingDirectory.isEmpty,
               let instanceDir = appState.instanceWorkingDirectory {
                workingDirectory = instanceDir
                didSetInitialDir = true
            }
        }
        .onChange(of: selectedAgentIds.count) { _, count in
            if count != 1 {
                dirMode = .inheritOrDefault
                workspacePrepError = nil
            }
        }
    }

    // MARK: - GitHub workspace (single agent with repo)

    @ViewBuilder
    private func githubWorkspaceSection(agent: Agent) -> some View {
        let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
        VStack(alignment: .leading, spacing: 10) {
            Text("Working directory")
                .font(.headline)
            Picker("", selection: $dirMode) {
                Text("Default").tag(SessionDirMode.inheritOrDefault)
                Text("Custom").tag(SessionDirMode.customFolder)
                Text("Clone").tag(SessionDirMode.githubClone)
                Text("Worktree").tag(SessionDirMode.worktree)
            }
            .pickerStyle(.segmented)
            .xrayId("newSession.githubWorkspaceModePicker")

            Group {
                Text("Repo: \(repo)")
                    .font(.caption)
                    .textSelection(.enabled)
                Text("Local: \(path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if dirMode == .githubClone {
                    Text("Branch: \(githubBranchLabel(agent))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .xrayId("newSession.githubStatusSummary")

            if let workspacePrepError {
                Text(workspacePrepError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .xrayId("newSession.githubWorkspaceError")
            }

            if dirMode == .githubClone {
                HStack {
                    if isWorkspacePreparing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Updating clone…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Validate / update clone") {
                        Task { await prepareGithubClone(agent: agent) }
                    }
                    .disabled(isWorkspacePreparing)
                    .xrayId("newSession.githubValidateButton")
                }
            }

            if dirMode == .worktree {
                HStack {
                    Text("Branch:")
                        .font(.caption)
                    TextField("feature/my-branch", text: $worktreeBranch)
                        .textFieldStyle(.roundedBorder)
                        .xrayId("newSession.worktreeBranchField")
                }
                let wtPath = WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: worktreeBranch.isEmpty ? "branch" : worktreeBranch)
                Text("Worktree: \(wtPath)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text("Creates an isolated copy on this branch. The base clone is shared.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // GitHub issue (optional, for any git workspace mode)
            Divider()
            HStack {
                Text("Issue:")
                    .font(.caption)
                TextField("#123", text: $githubIssueNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .xrayId("newSession.githubIssueField")
                if let title = fetchedIssueTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Fetch") {
                    Task { await fetchIssue(agent: agent) }
                }
                .disabled(githubIssueNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .xrayId("newSession.githubIssueFetchButton")
            }
            Text("Optional — fetches issue context into the agent's system prompt")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func githubBranchLabel(_ agent: Agent) -> String {
        let b = agent.githubDefaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return b.isEmpty ? "main" : b
    }

    private func fetchIssue(agent: Agent) async {
        let numberStr = githubIssueNumber.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard let number = Int(numberStr),
              let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else {
            workspacePrepError = "Enter a valid issue number"
            return
        }
        do {
            let issue = try await GitHubIntegration.fetchIssue(repoInput: repo, issueNumber: number)
            fetchedIssueTitle = issue.title
            if mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mission = issue.body
            }
        } catch {
            workspacePrepError = error.localizedDescription
        }
    }

    private func prepareGithubClone(agent: Agent) async {
        guard let repo = agent.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty else { return }
        isWorkspacePreparing = true
        workspacePrepError = nil
        defer { isWorkspacePreparing = false }
        let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
        let b = agent.githubDefaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let branch = b.isEmpty ? "main" : b
        do {
            try await GitHubIntegration.ensureClone(repoInput: repo, branch: branch, destinationPath: path)
        } catch {
            workspacePrepError = error.localizedDescription
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("New Session")
                .font(.title2)
                .fontWeight(.semibold)
                .xrayId("newSession.title")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Close")
            .xrayId("newSession.closeButton")
            .accessibilityLabel("Close")
        }
        .padding(16)
    }

    // MARK: - Create from Prompt

    @ViewBuilder
    private var createFromPromptSection: some View {
        DisclosureGroup("Create agent from prompt", isExpanded: $showCreateFromPrompt) {
            VStack(alignment: .leading, spacing: 10) {
                if appState.generatedAgentSpec == nil && !appState.isGeneratingAgent {
                    HStack(spacing: 8) {
                        TextField("Describe an agent to create...", text: $createFromPromptText)
                            .textFieldStyle(.roundedBorder)
                            .xrayId("newSession.fromPrompt.textField")
                        Button {
                            generateAgentFromPrompt()
                        } label: {
                            Label("Generate", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .xrayId("newSession.fromPrompt.generateButton")
                    }
                    Text("e.g. \"A code reviewer focused on security\"")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if appState.isGeneratingAgent {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .xrayId("newSession.fromPrompt.loading")
                }

                if let error = appState.generateAgentError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Button("Retry") { generateAgentFromPrompt() }
                            .controlSize(.small)
                            .xrayId("newSession.fromPrompt.retryButton")
                    }
                }

                if let spec = appState.generatedAgentSpec {
                    AgentPreviewCard(
                        spec: spec,
                        onSave: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        },
                        onSaveAndStart: { agent in
                            modelContext.insert(agent)
                            try? modelContext.save()
                            isFreeformChat = false
                            selectedAgentIds = [agent.id]
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                            Task { await createSessionAsync() }
                        },
                        onCancel: {
                            appState.generatedAgentSpec = nil
                            appState.generateAgentError = nil
                        }
                    )
                }
            }
            .padding(.top, 8)
        }
        .font(.headline)
        .xrayId("newSession.fromPrompt.disclosure")
    }

    private func generateAgentFromPrompt() {
        let skillEntries = allSkills.map { skill in
            SkillCatalogEntry(
                id: skill.id.uuidString,
                name: skill.name,
                description: skill.skillDescription,
                category: skill.category
            )
        }
        let mcpEntries = allMCPs.map { mcp in
            MCPCatalogEntry(
                id: mcp.id.uuidString,
                name: mcp.name,
                description: mcp.serverDescription
            )
        }
        appState.requestAgentGeneration(
            prompt: createFromPromptText.trimmingCharacters(in: .whitespacesAndNewlines),
            skills: skillEntries,
            mcps: mcpEntries
        )
    }

    // MARK: - Recent Agents

    @ViewBuilder
    private var recentAgentsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(recentAgents) { agent in
                    Button {
                        isFreeformChat = false
                        selectedAgentIds = [agent.id]
                        modelOverride = ""
                        if let dir = agent.defaultWorkingDirectory, !dir.isEmpty {
                            workingDirectory = dir
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: agent.icon)
                                .foregroundStyle(Color.fromAgentColor(agent.color))
                            Text(agent.name)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedAgentIds == [agent.id] && !isFreeformChat
                            ? Color.fromAgentColor(agent.color).opacity(0.12)
                            : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    selectedAgentIds == [agent.id] && !isFreeformChat
                                        ? Color.fromAgentColor(agent.color)
                                        : .secondary.opacity(0.3),
                                    lineWidth: selectedAgentIds == [agent.id] && !isFreeformChat ? 2 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .xrayId("newSession.recentAgent.\(agent.id.uuidString)")
                }
                Spacer()
            }
        }
    }

    // MARK: - Agent Picker

    @ViewBuilder
    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Agents (select one or more)")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 10)
            ], spacing: 10) {
                agentPickerCard(
                    icon: "bubble.left.and.bubble.right",
                    name: "Freeform",
                    detail: "No agent",
                    color: .secondary,
                    isSelected: isFreeformChat && selectedAgentIds.isEmpty,
                    identifier: "newSession.agentCard.freeform"
                ) {
                    isFreeformChat = true
                    selectedAgentIds.removeAll()
                    modelOverride = "claude-sonnet-4-6"
                }

                ForEach(agents) { agent in
                    agentPickerCard(
                        icon: agent.icon,
                        name: agent.name,
                        detail: agent.model,
                        color: Color.fromAgentColor(agent.color),
                        isSelected: selectedAgentIds.contains(agent.id),
                        identifier: "newSession.agentCard.\(agent.id.uuidString)"
                    ) {
                        isFreeformChat = false
                        if selectedAgentIds.contains(agent.id) {
                            selectedAgentIds.remove(agent.id)
                        } else {
                            selectedAgentIds.insert(agent.id)
                            modelOverride = ""
                            if let dir = agent.defaultWorkingDirectory, !dir.isEmpty {
                                workingDirectory = dir
                            }
                        }
                    }
                }
            }
        }
    }

    private func agentPickerCard(icon: String, name: String, detail: String, color: Color, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(isSelected ? color.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? color.opacity(1.0) : color.opacity(0.0), lineWidth: 2)
            }
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.secondary.opacity(0.2), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(name)
        .xrayId(identifier)
    }

    // MARK: - Options

    @ViewBuilder
    private var optionsSection: some View {
        DisclosureGroup("Session Options", isExpanded: $showOptions) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Model")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $modelOverride) {
                        if selectedAgentIds.count <= 1 {
                            Text("Inherit from Agent").tag("")
                        }
                        Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Opus 4").tag("claude-opus-4")
                        Text("Haiku 3.5").tag("claude-haiku-3-5")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .xrayId("newSession.modelPicker")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Mode")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sessionMode) {
                        Text("Interactive").tag(SessionMode.interactive)
                            .help("You guide the agent step by step")
                        Text("Autonomous").tag(SessionMode.autonomous)
                            .help("Agent works independently toward a goal")
                        Text("Worker").tag(SessionMode.worker)
                            .help("Background task with no interaction")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    .labelsHidden()
                    .xrayId("newSession.modePicker")
                }

                modeDescription

                HStack(alignment: .top) {
                    Text("Mission")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    TextField("Describe the goal for this session...", text: $mission, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .xrayId("newSession.missionField")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Directory")
                        .frame(width: 80, alignment: .trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("~/projects/my-app", text: $workingDirectory)
                        .textFieldStyle(.roundedBorder)
                        .disabled(singleAgentWithGithub != nil && (dirMode == .githubClone || dirMode == .worktree))
                        .xrayId("newSession.workingDirectoryField")
                    Button {
                        pickDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Browse for directory")
                    .disabled(singleAgentWithGithub != nil && (dirMode == .githubClone || dirMode == .worktree))
                    .xrayId("newSession.browseDirectoryButton")
                    .accessibilityLabel("Browse for directory")
                }
            }
            .padding(.top, 8)
        }
        .xrayId("newSession.optionsDisclosure")
    }

    @ViewBuilder
    private var modeDescription: some View {
        HStack {
            Spacer().frame(width: 84)
            Group {
                switch sessionMode {
                case .interactive:
                    Text("You guide the agent step by step, reviewing each action.")
                case .autonomous:
                    Text("The agent works independently toward a goal you define.")
                case .worker:
                    Text("Background task that runs without interaction.")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .xrayId("newSession.modeDescription")
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text("⌘N this sheet  ·  ⌘⇧N quick chat")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quick Chat") {
                createQuickChat()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .xrayId("newSession.quickChatButton")
            Button("Start Session") {
                Task { await createSessionAsync() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!canStartSession)
            .xrayId("newSession.startSessionButton")
        }
        .padding(16)
    }

    // MARK: - Actions

    private func createSessionAsync() async {
        let missionText = mission.trimmingCharacters(in: .whitespacesAndNewlines)
        let dirText = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ga = singleAgentWithGithub, orderedSelectedAgents.count == 1,
           let repo = ga.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty {
            if dirMode == .githubClone {
                isWorkspacePreparing = true
                workspacePrepError = nil
                defer { isWorkspacePreparing = false }
                let path = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                let branch = githubBranchLabel(ga)
                do {
                    try await GitHubIntegration.ensureClone(repoInput: repo, branch: branch, destinationPath: path)
                } catch {
                    workspacePrepError = error.localizedDescription
                    return
                }
            } else if dirMode == .worktree {
                let branch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !branch.isEmpty else {
                    workspacePrepError = "Branch name is required for worktree mode."
                    return
                }
                isWorkspacePreparing = true
                workspacePrepError = nil
                defer { isWorkspacePreparing = false }
                let baseClonePath = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                let worktreePath = WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: branch)
                do {
                    try await GitHubIntegration.ensureWorktree(
                        repoInput: repo, branch: branch,
                        baseClonePath: baseClonePath, worktreePath: worktreePath
                    )
                } catch {
                    workspacePrepError = error.localizedDescription
                    return
                }
            }
        }

        if !dirText.isEmpty {
            RecentDirectories.add(dirText)
        }

        if isFreeformChat || selectedAgentIds.isEmpty {
            let conversation = Conversation(topic: "New Chat")
            let userParticipant = Participant(type: .user, displayName: "You")
            userParticipant.conversation = conversation
            conversation.participants.append(userParticipant)
            modelContext.insert(conversation)
            try? modelContext.save()
            appState.selectedConversationId = conversation.id
            dismiss()
            return
        }

        let selectedList = orderedSelectedAgents
        guard !selectedList.isEmpty else {
            dismiss()
            return
        }

        let topic: String
        if selectedList.count == 1 {
            topic = selectedList[0].name
        } else {
            topic = selectedList.map(\.name).joined(separator: ", ")
        }

        let conversation = Conversation(topic: topic)
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)

        for agent in selectedList {
            let wd: String
            if let ga = singleAgentWithGithub, selectedList.count == 1,
               let repo = ga.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty {
                if dirMode == .githubClone {
                    wd = WorkspaceResolver.cloneDestinationPath(repoInput: repo)
                } else if dirMode == .worktree {
                    wd = WorkspaceResolver.worktreeDestinationPath(repoInput: repo, branch: worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if !dirText.isEmpty {
                    wd = dirText
                } else {
                    wd = agent.defaultWorkingDirectory ?? appState.instanceWorkingDirectory ?? ""
                }
            } else if !dirText.isEmpty {
                wd = dirText
            } else if selectedList.count > 1 {
                wd = ""
            } else {
                wd = agent.defaultWorkingDirectory ?? appState.instanceWorkingDirectory ?? ""
            }
            let session = Session(
                agent: agent,
                mission: missionText.isEmpty ? nil : missionText,
                mode: sessionMode,
                workingDirectory: wd
            )
            if let ga = singleAgentWithGithub, selectedList.count == 1, agent.id == ga.id,
               let repo = ga.githubRepo?.trimmingCharacters(in: .whitespacesAndNewlines), !repo.isEmpty {
                if dirMode == .githubClone {
                    session.workspaceType = .githubClone(repoUrl: repo)
                } else if dirMode == .worktree {
                    let branch = worktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                    session.workspaceType = .worktree(repoUrl: repo, branch: branch)
                    session.worktreePath = wd
                }
            } else if !dirText.isEmpty {
                session.workspaceType = .explicit(path: dirText)
            }
            session.conversations = [conversation]
            conversation.sessions.append(session)

            let agentParticipant = Participant(
                type: .agentSession(sessionId: session.id),
                displayName: agent.name
            )
            agentParticipant.conversation = conversation
            conversation.participants.append(agentParticipant)

            modelContext.insert(session)
        }

        modelContext.insert(conversation)
        if selectedList.count > 1, dirText.isEmpty {
            GroupWorkingDirectory.ensureShared(
                for: conversation,
                instanceDefault: appState.instanceWorkingDirectory,
                modelContext: modelContext
            )
        }
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
        dismiss()
    }

    private func createQuickChat() {
        let conversation = Conversation(topic: "New Chat")
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = conversation
        conversation.participants.append(userParticipant)
        modelContext.insert(conversation)
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
        dismiss()
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path(percentEncoded: false)
        }
    }
}
