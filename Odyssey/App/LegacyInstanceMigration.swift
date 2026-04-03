import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum LegacyInstanceMigration {
    struct Source {
        let rootDirectory: URL
        let storeFileName: String
        let defaultsSuiteName: String
        let keyPrefix: String
    }

    struct StoreSnapshot: Equatable {
        let projectCount: Int
        let conversationCount: Int
        let taskCount: Int
        let hasProjectTable: Bool
        let hasConversationTable: Bool
        let hasTaskTable: Bool

        var isEffectivelyEmpty: Bool {
            conversationCount == 0 && taskCount == 0
        }

        var isCurrentSchemaCompatible: Bool {
            hasProjectTable && hasConversationTable && hasTaskTable
        }

        var activityScore: Int {
            (conversationCount * 100) + (taskCount * 10) + projectCount
        }
    }

    @discardableResult
    static func migrateIfNeeded(
        instanceName: String,
        destinationBaseDirectory: URL,
        destinationDefaults: UserDefaults,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        legacySources: [Source]? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let sources = legacySources ?? defaultSources(homeDirectory: homeDirectory, instanceName: instanceName)

        var changed = migrateMissingDefaultsIfNeeded(
            from: sources,
            to: destinationDefaults
        )
        changed = copyRecentDirectoriesIfNeeded(
            from: sources,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        ) || changed

        let destinationStoreURL = destinationBaseDirectory
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent("Odyssey.store")
        let destinationSnapshot = storeSnapshot(at: destinationStoreURL)

        guard destinationSnapshot?.isEffectivelyEmpty ?? true else {
            return changed
        }

        guard let source = bestSource(from: sources) else {
            return changed
        }

        do {
            try copyLegacyInstance(
                from: source,
                to: destinationBaseDirectory,
                fileManager: fileManager
            )
            return true
        } catch {
            return changed
        }
    }

    static func storeSnapshot(at url: URL) -> StoreSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        let hasProjectTable = tableExists("ZPROJECT", in: database)
        let hasConversationTable = tableExists("ZCONVERSATION", in: database)
        let hasTaskTable = tableExists("ZTASKITEM", in: database)

        return StoreSnapshot(
            projectCount: hasProjectTable ? rowCount(in: "ZPROJECT", database: database) : 0,
            conversationCount: hasConversationTable ? rowCount(in: "ZCONVERSATION", database: database) : 0,
            taskCount: hasTaskTable ? rowCount(in: "ZTASKITEM", database: database) : 0,
            hasProjectTable: hasProjectTable,
            hasConversationTable: hasConversationTable,
            hasTaskTable: hasTaskTable
        )
    }

    private static func defaultSources(homeDirectory: URL, instanceName: String) -> [Source] {
        [
            Source(
                rootDirectory: homeDirectory.appendingPathComponent(".claudestudio/instances/\(instanceName)", isDirectory: true),
                storeFileName: "ClaudeStudio.store",
                defaultsSuiteName: "com.claudestudio.app.\(instanceName)",
                keyPrefix: "claudestudio"
            ),
            Source(
                rootDirectory: homeDirectory.appendingPathComponent(".claudpeer/instances/\(instanceName)", isDirectory: true),
                storeFileName: "ClaudPeer.store",
                defaultsSuiteName: "com.claudpeer.app.\(instanceName)",
                keyPrefix: "claudpeer"
            ),
        ]
    }

    private static func bestSource(from sources: [Source]) -> Source? {
        sources
            .compactMap { source -> (Source, StoreSnapshot)? in
                let storeURL = source.rootDirectory
                    .appendingPathComponent("data", isDirectory: true)
                    .appendingPathComponent(source.storeFileName)
                guard let snapshot = storeSnapshot(at: storeURL),
                      snapshot.isCurrentSchemaCompatible,
                      snapshot.activityScore > 0 else {
                    return nil
                }
                return (source, snapshot)
            }
            .sorted { lhs, rhs in
                lhs.1.activityScore > rhs.1.activityScore
            }
            .first?
            .0
    }

    private static func migrateMissingDefaultsIfNeeded(
        from sources: [Source],
        to destinationDefaults: UserDefaults
    ) -> Bool {
        var changed = false

        for source in sources {
            guard let legacyDefaults = UserDefaults(suiteName: source.defaultsSuiteName) else {
                continue
            }
            for key in AppSettings.allKeys {
                guard destinationDefaults.object(forKey: key) == nil else { continue }
                guard let legacyKey = legacyKey(for: key, keyPrefix: source.keyPrefix) else { continue }
                guard let value = legacyDefaults.object(forKey: legacyKey) else { continue }
                destinationDefaults.set(value, forKey: key)
                changed = true
            }
        }

        return changed
    }

    private static func copyRecentDirectoriesIfNeeded(
        from sources: [Source],
        homeDirectory: URL,
        fileManager: FileManager
    ) -> Bool {
        let destinationURL = homeDirectory.appendingPathComponent(".odyssey/recent-directories.json")
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            return false
        }

        for source in sources {
            let sourceBase = source.rootDirectory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = sourceBase.appendingPathComponent("recent-directories.json")
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            do {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return true
            } catch {
                return false
            }
        }

        return false
    }

    private static func copyLegacyInstance(
        from source: Source,
        to destinationBaseDirectory: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: destinationBaseDirectory, withIntermediateDirectories: true)

        let destinationDataDirectory = destinationBaseDirectory.appendingPathComponent("data", isDirectory: true)
        try fileManager.createDirectory(at: destinationDataDirectory, withIntermediateDirectories: true)

        let sourceStoreBaseURL = source.rootDirectory
            .appendingPathComponent("data", isDirectory: true)
            .appendingPathComponent(source.storeFileName)
        let destinationStoreBaseURL = destinationDataDirectory.appendingPathComponent("Odyssey.store")

        try copyStoreFamily(
            from: sourceStoreBaseURL,
            to: destinationStoreBaseURL,
            fileManager: fileManager
        )

        try copyDirectoryIfMissing(
            from: source.rootDirectory.appendingPathComponent("blackboard", isDirectory: true),
            to: destinationBaseDirectory.appendingPathComponent("blackboard", isDirectory: true),
            fileManager: fileManager
        )
        try copyDirectoryIfMissing(
            from: source.rootDirectory.appendingPathComponent("taskboard", isDirectory: true),
            to: destinationBaseDirectory.appendingPathComponent("taskboard", isDirectory: true),
            fileManager: fileManager
        )
    }

    private static func copyStoreFamily(
        from sourceStoreBaseURL: URL,
        to destinationStoreBaseURL: URL,
        fileManager: FileManager
    ) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = URL(fileURLWithPath: sourceStoreBaseURL.path + suffix)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            let destinationURL = URL(fileURLWithPath: destinationStoreBaseURL.path + suffix)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func copyDirectoryIfMissing(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func legacyKey(for odysseyKey: String, keyPrefix: String) -> String? {
        guard odysseyKey.hasPrefix("odyssey.") else { return nil }
        return keyPrefix + "." + odysseyKey.dropFirst("odyssey.".count)
    }

    private static func tableExists(_ name: String, in database: OpaquePointer?) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func rowCount(in table: String, database: OpaquePointer?) -> Int {
        let sql = "SELECT COUNT(*) FROM \(table);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
