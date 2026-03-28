import Foundation
import XCTest
@testable import ClaudeStudio

@MainActor
final class ScheduledMissionSupportTests: XCTestCase {

    func testPromptRendererSubstitutesVariables() {
        let schedule = ScheduledMission(
            name: "Bug triage",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "{{now}}|{{lastRunAt}}|{{lastSuccessAt}}|{{runCount}}|{{projectDirectory}}"
        )
        schedule.lastStartedAt = Date(timeIntervalSince1970: 100)
        schedule.lastSucceededAt = Date(timeIntervalSince1970: 200)

        let text = ScheduledMissionPromptRenderer.render(
            schedule: schedule,
            runCount: 3,
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertTrue(text.contains("1970-01-01T00:05:00Z"))
        XCTAssertTrue(text.contains("1970-01-01T00:01:40Z"))
        XCTAssertTrue(text.contains("1970-01-01T00:03:20Z"))
        XCTAssertTrue(text.contains("|3|/tmp/repo"))
    }

    func testPromptRendererUsesNeverForFirstRun() {
        let schedule = ScheduledMission(
            name: "Feature sweep",
            targetKind: .group,
            projectDirectory: "/tmp/repo",
            promptTemplate: "{{lastRunAt}} {{lastSuccessAt}}"
        )

        let text = ScheduledMissionPromptRenderer.render(schedule: schedule, runCount: 1, now: .init(timeIntervalSince1970: 0))
        XCTAssertEqual(text, "never never")
    }

    func testHourlyCadenceComputesNextOccurrence() {
        let schedule = ScheduledMission(
            name: "Hourly",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.createdAt = Date(timeIntervalSince1970: 0)
        schedule.intervalHours = 4

        let next = ScheduledMissionCadence.nextOccurrence(
            for: schedule,
            after: Date(timeIntervalSince1970: 5 * 3600)
        )

        XCTAssertEqual(next, Date(timeIntervalSince1970: 8 * 3600))
    }

    func testDailyCadenceRespectsWeekdaysAndTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let schedule = ScheduledMission(
            name: "Weekdays",
            targetKind: .group,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.cadenceKind = .dailyTime
        schedule.localHour = 9
        schedule.localMinute = 0
        schedule.daysOfWeek = [.monday, .wednesday, .friday]

        let reference = ISO8601DateFormatter().date(from: "2026-03-31T10:00:00Z")! // Tuesday
        let next = ScheduledMissionCadence.nextOccurrence(for: schedule, after: reference, calendar: calendar)

        XCTAssertEqual(ISO8601DateFormatter().string(from: next!), "2026-04-01T09:00:00Z")
    }

    func testDraftValidationRejectsReuseWithoutConversation() {
        var draft = ScheduledMissionDraft(
            name: "Reuse",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        draft.targetAgentId = UUID()
        draft.runMode = .reuseConversation

        XCTAssertEqual(draft.validationError, "Reuse conversation mode requires a conversation target.")
    }

    func testLaunchdManagerWritesAndRemovesFiles() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let launchAgents = temp.appendingPathComponent("LaunchAgents")
        let scripts = temp.appendingPathComponent("Scripts")
        let manager = ScheduleLaunchdManager(
            launchAgentsDirectory: launchAgents,
            scriptsDirectory: scripts,
            launchctlRunner: { _ in }
        )

        let schedule = ScheduledMission(
            name: "Closed app",
            targetKind: .agent,
            projectDirectory: "/tmp/repo",
            promptTemplate: "Prompt"
        )
        schedule.runWhenAppClosed = true

        manager.sync(schedule: schedule)

        let plistPath = launchAgents.appendingPathComponent("\(manager.jobLabel(for: schedule)).plist").path
        let scriptPath = scripts.appendingPathComponent("\(schedule.id.uuidString).sh").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptPath))

        manager.remove(schedule: schedule)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptPath))
    }
}

