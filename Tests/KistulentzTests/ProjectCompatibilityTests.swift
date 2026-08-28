import Foundation
import XCTest
@testable import Kistulentz

final class ProjectCompatibilityTests: XCTestCase {
    func testMigratesV09MetadataAfterCreatingAPreMigrationSnapshot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Legacy Book", kind: .fiction)
        let originalMarkdown = try WritingProjectDisk.readChapter("Chapter 1.md", at: root)
        let manifest = WritingProjectManifest(
            formatVersion: 1,
            name: "Legacy Book",
            kind: .fiction,
            chapterOrder: ["Chapter 1.md"],
            lastOpenedChapter: "Chapter 1.md"
        )
        try WritingProjectDisk.saveManifest(manifest, at: root)

        let result = try ProjectCompatibilityManager.prepareForOpen(at: root)

        XCTAssertTrue(result.didMigrate)
        XCTAssertEqual(result.fromVersion, 1)
        XCTAssertEqual(result.toVersion, KistulentzProjectFormat.currentVersion)
        XCTAssertEqual(result.backup?.reason, .preMigration)
        XCTAssertEqual(
            try WritingProjectDisk.loadManifest(at: root).formatVersion,
            KistulentzProjectFormat.currentVersion
        )
        XCTAssertEqual(try WritingProjectDisk.readChapter("Chapter 1.md", at: root), originalMarkdown)

        let backup = try XCTUnwrap(result.backup)
        let archivedManifest = ProjectCompatibilityManager.backupsURL(at: root)
            .appendingPathComponent(backup.directoryName)
            .appendingPathComponent("metadata/project.json")
        XCTAssertEqual(try integerField("formatVersion", in: archivedManifest), 1)
    }

    @MainActor
    func testStoreOpensAProjectFromBeforeOutlineResearchAndPublishingExisted() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Opening\n\nThe manuscript remains ordinary Markdown.\n".write(
            to: root.appendingPathComponent("Opening.md"),
            atomically: true,
            encoding: .utf8
        )
        try WritingProjectDisk.saveManifest(
            WritingProjectManifest(
                formatVersion: 1,
                name: "Old Project",
                kind: .nonfiction,
                chapterOrder: ["Opening.md"],
                lastOpenedChapter: "Opening.md"
            ),
            at: root
        )
        try ProjectStyleManager.prepare(at: root, projectName: "Old Project", kind: .nonfiction)

        let store = WritingProjectStore()
        try store.openProject(at: root)

        XCTAssertTrue(store.isOpen)
        XCTAssertEqual(store.manifest?.formatVersion, KistulentzProjectFormat.currentVersion)
        XCTAssertEqual(store.selectedChapterPath, "Opening.md")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: WritingProjectDisk.metadataURL(at: root).appendingPathComponent("outline.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: WritingProjectDisk.metadataURL(at: root).appendingPathComponent("publication.json").path
        ))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("Opening.md"), encoding: .utf8),
            "# Opening\n\nThe manuscript remains ordinary Markdown.\n"
        )
    }

    func testFutureProjectVersionIsRejectedWithoutChangingFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Future Book", kind: .fiction)
        let manifestURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent("project.json")
        try setIntegerField("formatVersion", to: 99, in: manifestURL)
        let before = try Data(contentsOf: manifestURL)

        XCTAssertThrowsError(try ProjectCompatibilityManager.prepareForOpen(at: root)) { error in
            XCTAssertEqual(
                error as? ProjectCompatibilityError,
                .unsupportedProjectVersion(found: 99, supported: KistulentzProjectFormat.currentVersion)
            )
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), before)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ProjectCompatibilityManager.backupsURL(at: root).path
        ))
    }

    @MainActor
    func testCorruptMetadataCanBeRestoredAndPreservesFailedCopyAndMarkdown() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Recovery Book", kind: .fiction)
        try PublicationDisk.prepare(at: root, projectName: "Recovery Book", projectKind: .fiction)
        let expectedOutline = try ProjectOutlineDisk.load(at: root)
        let markdownURL = root.appendingPathComponent("Chapter 1.md")
        let expectedMarkdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let knownGood = try ProjectCompatibilityManager.captureKnownGoodSnapshot(at: root)
        let outlineURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent("outline.json")
        let corruptBytes = Data("{broken".utf8)
        try corruptBytes.write(to: outlineURL, options: .atomic)

        XCTAssertThrowsError(try ProjectCompatibilityManager.prepareForOpen(at: root))
        try ProjectCompatibilityManager.restore(knownGood, at: root)

        XCTAssertEqual(try ProjectOutlineDisk.load(at: root), expectedOutline)
        XCTAssertEqual(try String(contentsOf: markdownURL, encoding: .utf8), expectedMarkdown)
        let beforeRecovery = try XCTUnwrap(
            ProjectCompatibilityManager.availableBackups(at: root)
                .first { $0.reason == .beforeRecovery }
        )
        let preservedFailure = ProjectCompatibilityManager.backupsURL(at: root)
            .appendingPathComponent(beforeRecovery.directoryName)
            .appendingPathComponent("metadata/outline.json")
        XCTAssertEqual(try Data(contentsOf: preservedFailure), corruptBytes)

        let store = WritingProjectStore()
        try corruptBytes.write(to: outlineURL, options: .atomic)
        XCTAssertThrowsError(try store.openProject(at: root))
        XCTAssertFalse(store.recoveryRequest?.backups.isEmpty ?? true)
        let selected = try XCTUnwrap(store.recoveryRequest?.backups.first { $0.reason == .knownGood })
        try store.restoreProject(from: selected)
        XCTAssertTrue(store.isOpen)
        XCTAssertNil(store.recoveryRequest)
        XCTAssertEqual(store.text, expectedMarkdown)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Compatibility-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func setIntegerField(_ key: String, to value: Int, in url: URL) throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        object[key] = value
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }

    private func integerField(_ key: String, in url: URL) throws -> Int {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(object[key] as? Int)
    }
}
