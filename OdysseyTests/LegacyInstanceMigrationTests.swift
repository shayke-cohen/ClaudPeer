import Foundation
import SQLite3
import XCTest
@testable import Odyssey

final class LegacyInstanceMigrationTests: XCTestCase {
    private var tempHome: URL!
    private var destinationBaseDirectory: URL!
    private var destinationSuiteName: String!
    private var sourceSuiteName: String!
    private var destinationDefaults: UserDefaults!

    override func setUp() async throws {
        tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        destinationBaseDirectory = tempHome.appendingPathComponent(".odyssey/instances/default", isDirectory: true)
        destinationSuiteName = "test.odyssey.destination.\(UUID().uuidString)"
        sourceSuiteName = "test.odyssey.legacy.\(UUID().uuidString)"
        destinationDefaults = UserDefaults(suiteName: destinationSuiteName)

        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: destinationSuiteName)
        UserDefaults().removePersistentDomain(forName: sourceSuiteName)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: destinationSuiteName)
        UserDefaults().removePersistentDomain(forName: sourceSuiteName)
        try? FileManager.default.removeItem(at: tempHome)

        destinationDefaults = nil
        sourceSuiteName = nil
        destinationSuiteName = nil
        destinationBaseDirectory = nil
        tempHome = nil
    }

    func testMigratesLegacyStoreIntoEffectivelyEmptyOdysseyInstance() throws {
        let sourceRoot = tempHome.appendingPathComponent(".claudestudio/instances/default", isDirectory: true)
        try makeStore(
            at: sourceRoot.appendingPathComponent("data/ClaudeStudio.store"),
            projectCount: 3,
            conversationCount: 4,
            taskCount: 2
        )
        try makeStore(
            at: destinationBaseDirectory.appendingPathComponent("data/Odyssey.store"),
            projectCount: 1,
            conversationCount: 0,
            taskCount: 0
        )

        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: sourceSuiteName))
        sourceDefaults.set("/Users/shayco/Odyssey", forKey: "claudestudio.instanceWorkingDirectory")
        sourceDefaults.set("dark", forKey: "claudestudio.appearance")

        let migrated = LegacyInstanceMigration.migrateIfNeeded(
            instanceName: "default",
            destinationBaseDirectory: destinationBaseDirectory,
            destinationDefaults: destinationDefaults,
            homeDirectory: tempHome,
            legacySources: [
                .init(
                    rootDirectory: sourceRoot,
                    storeFileName: "ClaudeStudio.store",
                    defaultsSuiteName: sourceSuiteName,
                    keyPrefix: "claudestudio"
                ),
            ]
        )

        XCTAssertTrue(migrated)

        let snapshot = try XCTUnwrap(
            LegacyInstanceMigration.storeSnapshot(
                at: destinationBaseDirectory.appendingPathComponent("data/Odyssey.store")
            )
        )
        XCTAssertEqual(snapshot.projectCount, 3)
        XCTAssertEqual(snapshot.conversationCount, 4)
        XCTAssertEqual(snapshot.taskCount, 2)
        XCTAssertEqual(
            destinationDefaults.string(forKey: AppSettings.instanceWorkingDirectoryKey),
            "/Users/shayco/Odyssey"
        )
        XCTAssertEqual(destinationDefaults.string(forKey: AppSettings.appearanceKey), "dark")
    }

    func testDoesNotOverwriteOdysseyStoreWithExistingConversations() throws {
        let sourceRoot = tempHome.appendingPathComponent(".claudestudio/instances/default", isDirectory: true)
        try makeStore(
            at: sourceRoot.appendingPathComponent("data/ClaudeStudio.store"),
            projectCount: 3,
            conversationCount: 4,
            taskCount: 2
        )
        try makeStore(
            at: destinationBaseDirectory.appendingPathComponent("data/Odyssey.store"),
            projectCount: 1,
            conversationCount: 1,
            taskCount: 0
        )

        let migrated = LegacyInstanceMigration.migrateIfNeeded(
            instanceName: "default",
            destinationBaseDirectory: destinationBaseDirectory,
            destinationDefaults: destinationDefaults,
            homeDirectory: tempHome,
            legacySources: [
                .init(
                    rootDirectory: sourceRoot,
                    storeFileName: "ClaudeStudio.store",
                    defaultsSuiteName: sourceSuiteName,
                    keyPrefix: "claudestudio"
                ),
            ]
        )

        XCTAssertFalse(migrated)

        let snapshot = try XCTUnwrap(
            LegacyInstanceMigration.storeSnapshot(
                at: destinationBaseDirectory.appendingPathComponent("data/Odyssey.store")
            )
        )
        XCTAssertEqual(snapshot.projectCount, 1)
        XCTAssertEqual(snapshot.conversationCount, 1)
        XCTAssertEqual(snapshot.taskCount, 0)
    }

    private func makeStore(
        at url: URL,
        projectCount: Int,
        conversationCount: Int,
        taskCount: Int
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }

        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ZPROJECT (Z_PK INTEGER PRIMARY KEY);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ZCONVERSATION (Z_PK INTEGER PRIMARY KEY);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE ZTASKITEM (Z_PK INTEGER PRIMARY KEY);", nil, nil, nil), SQLITE_OK)

        for index in 0..<projectCount {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZPROJECT (Z_PK) VALUES (\(index + 1));", nil, nil, nil), SQLITE_OK)
        }
        for index in 0..<conversationCount {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZCONVERSATION (Z_PK) VALUES (\(index + 1));", nil, nil, nil), SQLITE_OK)
        }
        for index in 0..<taskCount {
            XCTAssertEqual(sqlite3_exec(database, "INSERT INTO ZTASKITEM (Z_PK) VALUES (\(index + 1));", nil, nil, nil), SQLITE_OK)
        }
    }
}
