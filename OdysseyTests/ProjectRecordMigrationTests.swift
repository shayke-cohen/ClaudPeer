import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class ProjectRecordMigrationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tempRoot: URL!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Project.self, configurations: config)
        context = container.mainContext
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        context = nil
        container = nil
        tempRoot = nil
    }

    func testUpsertProjectRelinksMissingWorkspaceToRenamedSibling() throws {
        let missingPath = tempRoot.appendingPathComponent("ClaudPeer").path
        let renamedPath = tempRoot.appendingPathComponent("Odyssey")
        try makeWorkspaceRoot(at: renamedPath)

        let original = Project(
            name: "ClaudPeer",
            rootPath: missingPath,
            canonicalRootPath: missingPath
        )
        context.insert(original)
        try context.save()

        let relinked = ProjectRecords.upsertProject(
            at: missingPath,
            in: context,
            currentDirectoryPath: renamedPath.path,
            recentDirectories: []
        )

        XCTAssertEqual(relinked.id, original.id)
        XCTAssertEqual(relinked.rootPath, renamedPath.path)
        XCTAssertEqual(relinked.canonicalRootPath, renamedPath.path)
        XCTAssertEqual(relinked.name, "Odyssey")
    }

    func testRepairProjectIfNeededPreservesCustomProjectName() throws {
        let missingPath = tempRoot.appendingPathComponent("ClaudPeer").path
        let renamedPath = tempRoot.appendingPathComponent("Odyssey")
        try makeWorkspaceRoot(at: renamedPath)

        let project = Project(
            name: "Mission Control",
            rootPath: missingPath,
            canonicalRootPath: missingPath
        )
        context.insert(project)
        try context.save()

        let changed = ProjectRecords.repairProjectIfNeeded(
            project,
            currentDirectoryPath: renamedPath.path,
            recentDirectories: []
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(project.rootPath, renamedPath.path)
        XCTAssertEqual(project.canonicalRootPath, renamedPath.path)
        XCTAssertEqual(project.name, "Mission Control")
    }

    private func makeWorkspaceRoot(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("sidecar/src"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.appendingPathComponent("project.yml").path, contents: Data())
        FileManager.default.createFile(atPath: url.appendingPathComponent("sidecar/src/index.ts").path, contents: Data())
        FileManager.default.createFile(atPath: url.appendingPathComponent("Odyssey.xcodeproj").path, contents: Data())
    }
}
