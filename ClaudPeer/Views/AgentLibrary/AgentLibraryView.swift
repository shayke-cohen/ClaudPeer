import SwiftUI
import SwiftData

struct AgentLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Agent.name) private var agents: [Agent]
    @State private var searchText = ""
    @State private var filterOrigin: AgentOriginFilter = .all
    @State private var showingNewAgent = false
    @State private var editingAgent: Agent?

    enum AgentOriginFilter: String, CaseIterable {
        case all = "All"
        case mine = "Mine"
        case shared = "Shared"
    }

    private var filteredAgents: [Agent] {
        agents.filter { agent in
            let matchesSearch = searchText.isEmpty ||
                agent.name.localizedCaseInsensitiveContains(searchText) ||
                agent.agentDescription.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filterOrigin {
            case .all: matchesFilter = true
            case .mine: matchesFilter = agent.origin == .local || agent.origin == .builtin
            case .shared:
                if case .peer = agent.origin { matchesFilter = true }
                else if agent.origin == .imported { matchesFilter = true }
                else { matchesFilter = false }
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
                ], spacing: 16) {
                    ForEach(filteredAgents) { agent in
                        AgentCardView(agent: agent, onStart: {
                            startSession(with: agent)
                        }) {
                            editingAgent = agent
                        }
                        .contextMenu {
                            Button("Edit") {
                                editingAgent = agent
                            }
                            Button("Duplicate") { duplicateAgent(agent) }
                            Divider()
                            Button("Delete", role: .destructive) { deleteAgent(agent) }
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(item: $editingAgent) { agent in
            AgentEditorView(agent: agent) { _ in
                editingAgent = nil
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .sheet(isPresented: $showingNewAgent) {
            AgentEditorView(agent: nil) { _ in
                showingNewAgent = false
            }
            .frame(minWidth: 600, minHeight: 500)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Agent Library")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()

            Picker("Filter", selection: $filterOrigin) {
                ForEach(AgentOriginFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Button {
                showingNewAgent = true
            } label: {
                Label("New Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private func duplicateAgent(_ agent: Agent) {
        let copy = Agent(
            name: "\(agent.name) Copy",
            agentDescription: agent.agentDescription,
            systemPrompt: agent.systemPrompt,
            model: agent.model,
            icon: agent.icon,
            color: agent.color
        )
        copy.skillIds = agent.skillIds
        copy.mcpServerIds = agent.mcpServerIds
        copy.permissionSetId = agent.permissionSetId
        copy.instancePolicy = agent.instancePolicy
        copy.defaultWorkingDirectory = agent.defaultWorkingDirectory
        copy.githubRepo = agent.githubRepo
        copy.githubDefaultBranch = agent.githubDefaultBranch
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func deleteAgent(_ agent: Agent) {
        modelContext.delete(agent)
        try? modelContext.save()
    }

    private func startSession(with agent: Agent) {
        let session = Session(agent: agent, mode: .interactive)
        let conversation = Conversation(topic: agent.name, session: session)
        let userParticipant = Participant(type: .user, displayName: "You")
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: agent.name
        )
        userParticipant.conversation = conversation
        agentParticipant.conversation = conversation
        conversation.participants = [userParticipant, agentParticipant]
        session.conversations = [conversation]

        modelContext.insert(session)
        modelContext.insert(conversation)
        try? modelContext.save()
        appState.selectedConversationId = conversation.id
        dismiss()
    }
}
