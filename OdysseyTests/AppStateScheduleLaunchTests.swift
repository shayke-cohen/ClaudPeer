import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class AppStateScheduleLaunchTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Project.self,
            ScheduledMission.self,
            ScheduledMissionRun.self,
            Agent.self,
            Session.self,
            Conversation.self,
            ConversationMessage.self,
            MessageAttachment.self,
            Participant.self,
            AgentGroup.self,
            Skill.self,
            MCPServer.self,
            PermissionSet.self,
            configurations: config
        )
        context = container.mainContext
        appState = AppState()
        appState.modelContext = context
    }

    override func tearDown() async throws {
        appState = nil
        context = nil
        container = nil
    }

    func testExecuteLaunchIntentRunsScheduledOccurrence() async throws {
        let expectation = expectation(description: "schedule launched")
        let project = Project(
            name: "Repo",
            rootPath: "/tmp/repo",
            canonicalRootPath: "/tmp/repo"
        )
        context.insert(project)
        let schedule = ScheduledMission(
            name: "CLI schedule",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.projectId = project.id
        context.insert(schedule)
        try context.save()

        let coordinator = ScheduleRunCoordinator(appState: appState, modelContext: context)
        let engine = ScheduleEngine(
            modelContext: context,
            coordinator: coordinator,
            launchdManager: ScheduleLaunchdManager(
                launchAgentsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                scriptsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                launchctlRunner: { _ in }
            ),
            executeHandler: { _, run, _ in
                XCTAssertEqual(run.scheduledFor, Date(timeIntervalSince1970: 7_200))
                expectation.fulfill()
            }
        )
        appState.setScheduleTestingHooks(engine: engine, coordinator: coordinator)

        let intent = try XCTUnwrap(LaunchIntent.fromArguments([
            "Odyssey",
            "--schedule", schedule.id.uuidString,
            "--occurrence", "1970-01-01T02:00:00Z"
        ]))
        let windowState = WindowState(project: project)

        appState.executeLaunchIntent(intent, modelContext: context, windowState: windowState)
        await fulfillment(of: [expectation], timeout: 1.0)

        let runs = try context.fetch(FetchDescriptor<ScheduledMissionRun>())
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.scheduledFor, Date(timeIntervalSince1970: 7_200))
    }
}
