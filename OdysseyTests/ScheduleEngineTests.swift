import Foundation
import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class ScheduleEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var appState: AppState!
    private var coordinator: ScheduleRunCoordinator!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: ScheduledMission.self,
            ScheduledMissionRun.self,
            Agent.self,
            Session.self,
            Conversation.self,
            ConversationMessage.self,
            MessageAttachment.self,
            Participant.self,
            AgentGroup.self,
            configurations: config
        )
        context = container.mainContext
        appState = AppState()
        appState.modelContext = context
        coordinator = ScheduleRunCoordinator(appState: appState, modelContext: context)
    }

    override func tearDown() async throws {
        coordinator = nil
        appState = nil
        context = nil
        container = nil
    }

    func testEvaluateCreatesOnlyLatestMissedOccurrence() async throws {
        var executed: [(UUID, Date)] = []
        let executionExpectation = expectation(description: "schedule execution claimed")
        let engine = ScheduleEngine(
            modelContext: context,
            coordinator: coordinator,
            launchdManager: ScheduleLaunchdManager(
                launchAgentsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                scriptsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                launchctlRunner: { _ in }
            ),
            executeHandler: { schedule, run, _ in
                executed.append((schedule.id, run.scheduledFor))
                executionExpectation.fulfill()
            }
        )

        let schedule = ScheduledMission(
            name: "Catch up",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.createdAt = Date(timeIntervalSince1970: 0)
        schedule.intervalHours = 1
        schedule.nextRunAt = Date(timeIntervalSince1970: 3600)
        context.insert(schedule)
        try context.save()

        engine.evaluateDueSchedules(now: Date(timeIntervalSince1970: 4 * 3600 + 1800), triggerSource: .timer)
        await fulfillment(of: [executionExpectation], timeout: 1.0)

        XCTAssertEqual(executed.count, 1)
        XCTAssertEqual(executed.first?.1, Date(timeIntervalSince1970: 4 * 3600))
        XCTAssertEqual(schedule.nextRunAt, Date(timeIntervalSince1970: 5 * 3600))
    }

    func testEvaluateSkipsWhenRunAlreadyActive() throws {
        let engine = ScheduleEngine(
            modelContext: context,
            coordinator: coordinator,
            launchdManager: ScheduleLaunchdManager(
                launchAgentsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                scriptsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                launchctlRunner: { _ in }
            ),
            executeHandler: { _, _, _ in }
        )

        let schedule = ScheduledMission(
            name: "Overlap",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.createdAt = Date(timeIntervalSince1970: 0)
        schedule.intervalHours = 1
        schedule.nextRunAt = Date(timeIntervalSince1970: 3600)
        context.insert(schedule)

        let activeRun = ScheduledMissionRun(
            scheduleId: schedule.id,
            occurrenceKey: "active",
            status: .running,
            triggerSource: .timer,
            scheduledFor: Date(timeIntervalSince1970: 1800)
        )
        context.insert(activeRun)
        try context.save()

        engine.evaluateDueSchedules(now: Date(timeIntervalSince1970: 4000), triggerSource: .timer)

        let runs = try context.fetch(FetchDescriptor<ScheduledMissionRun>())
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first(where: { $0.status == .skipped })?.skipReason, "previousRunStillActive")
    }

    func testEvaluateIgnoresDisabledSchedules() throws {
        var executed = false
        let engine = ScheduleEngine(
            modelContext: context,
            coordinator: coordinator,
            launchdManager: ScheduleLaunchdManager(
                launchAgentsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                scriptsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                launchctlRunner: { _ in }
            ),
            executeHandler: { _, _, _ in
                executed = true
            }
        )

        let schedule = ScheduledMission(
            name: "Disabled",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.isEnabled = false
        schedule.nextRunAt = Date(timeIntervalSince1970: 0)
        context.insert(schedule)
        try context.save()

        engine.evaluateDueSchedules(now: Date(timeIntervalSince1970: 7200), triggerSource: .timer)

        XCTAssertFalse(executed)
        let runs = try context.fetch(FetchDescriptor<ScheduledMissionRun>())
        XCTAssertTrue(runs.isEmpty)
    }

    func testRecoverMarksStaleRunsFailed() throws {
        let engine = ScheduleEngine(
            modelContext: context,
            coordinator: coordinator,
            launchdManager: ScheduleLaunchdManager(
                launchAgentsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                scriptsDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString),
                launchctlRunner: { _ in }
            ),
            executeHandler: { _, _, _ in }
        )

        let schedule = ScheduledMission(
            name: "Recovery",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        context.insert(schedule)

        let staleRun = ScheduledMissionRun(
            scheduleId: schedule.id,
            occurrenceKey: "stale",
            status: .running,
            triggerSource: .timer,
            scheduledFor: Date(timeIntervalSince1970: 0),
            startedAt: Date(timeIntervalSinceNow: -(ScheduleEngine.staleRunTimeout + 30))
        )
        context.insert(staleRun)
        try context.save()

        engine.evaluateDueSchedules(now: Date(), triggerSource: .timer)

        XCTAssertEqual(staleRun.status, .failed)
        XCTAssertEqual(staleRun.errorMessage, "schedulerRecoveryTimeout")
        XCTAssertNotNil(schedule.lastFailedAt)
    }
}
