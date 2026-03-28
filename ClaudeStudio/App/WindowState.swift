import SwiftUI
import SwiftData
import Foundation

enum ProjectRecords {
    static func canonicalPath(for path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func displayName(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Project" }
        return (trimmed as NSString).lastPathComponent
    }

    @discardableResult
    static func upsertProject(at path: String, in modelContext: ModelContext) -> Project {
        let canonical = canonicalPath(for: path)
        let descriptor = FetchDescriptor<Project>()
        let existing = (try? modelContext.fetch(descriptor))?.first {
            $0.canonicalRootPath == canonical
        }

        let project = existing ?? Project(
            name: displayName(for: canonical),
            rootPath: canonical,
            canonicalRootPath: canonical
        )
        project.name = displayName(for: canonical)
        project.rootPath = canonical
        project.canonicalRootPath = canonical
        project.lastOpenedAt = Date()

        if existing == nil {
            modelContext.insert(project)
        }
        try? modelContext.save()
        return project
    }
}

/// Per-window state for the project-first shell.
@MainActor @Observable
final class WindowState {
    /// Reference to the shared AppState for cross-window coordination.
    weak var appState: AppState?

    private(set) var selectedProjectId: UUID?

    private var currentProjectDirectory: String
    private var currentProjectDisplayName: String

    var selectedConversationId: UUID? {
        didSet {
            if selectedConversationId != nil { selectedGroupId = nil }
            // Update AppState's visible set for notification gating
            if let old = oldValue { appState?.visibleConversationIds.remove(old) }
            if let new = selectedConversationId {
                appState?.visibleConversationIds.insert(new)
                markConversationRead(id: new)
            }
        }
    }
    var selectedGroupId: UUID? {
        didSet { if selectedGroupId != nil { selectedConversationId = nil } }
    }

    var showNewSessionSheet = false
    var showAgentLibrary = false
    var showGroupLibrary = false
    var showScheduleLibrary = false
    var showPeerNetwork = false
    var showAgentComms = false
    var showWorkshop = false

    var launchError: String?
    var autoSendText: String?

    init(project: Project) {
        self.selectedProjectId = project.id
        self.currentProjectDirectory = project.rootPath
        self.currentProjectDisplayName = project.name
    }

    var projectName: String {
        currentProjectDisplayName
    }

    var projectDirectory: String {
        currentProjectDirectory
    }

    func selectProject(_ project: Project, preserveSelection: Bool = false) {
        apply(project: project, preserveSelection: preserveSelection)
    }

    func selectProject(id: UUID, preserveSelection: Bool = false) {
        guard let ctx = appState?.modelContext else { return }
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.id == id
        })
        guard let project = try? ctx.fetch(descriptor).first else { return }
        apply(project: project, preserveSelection: preserveSelection)
    }

    private func apply(project: Project, preserveSelection: Bool) {
        selectedProjectId = project.id
        currentProjectDirectory = project.rootPath
        currentProjectDisplayName = project.name
        project.lastOpenedAt = Date()
        try? appState?.modelContext?.save()

        if !preserveSelection {
            selectedConversationId = nil
            selectedGroupId = nil
        }
    }

    private func markConversationRead(id: UUID) {
        guard let ctx = appState?.modelContext else { return }
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { c in c.id == id })
        guard let convo = try? ctx.fetch(descriptor).first, convo.isUnread else { return }
        convo.isUnread = false
        try? ctx.save()
    }
}
