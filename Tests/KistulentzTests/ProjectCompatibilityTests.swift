import Foundation
import XCTest
@testable import Kistulentz

final class ProjectCompatibilityTests: XCTestCase {
    func testFrozenUpgradeFixtureMatrixCoversEveryPriorProjectFormatAndPreservesMarkdownBytes() throws {
        let fixturesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/UpgradeProjects", isDirectory: true)
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: fixturesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        var coveredVersions: Set<Int> = []

        for fixture in fixtureURLs {
            let manifestURL = fixture.appendingPathComponent(".kistulentz/project.json")
            let version = try integerField("formatVersion", in: manifestURL)
            coveredVersions.insert(version)
            let root = temporaryDirectory()
            try FileManager.default.removeItem(at: root)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.copyItem(at: fixture, to: root)
            let markdownBefore = try markdownFingerprints(at: root)

            _ = try ProjectCompatibilityManager.prepareForOpen(at: root)

            XCTAssertEqual(try markdownFingerprints(at: root), markdownBefore, fixture.lastPathComponent)
            XCTAssertEqual(try WritingProjectDisk.loadManifest(at: root).formatVersion, KistulentzProjectFormat.currentVersion)
        }

        XCTAssertEqual(
            coveredVersions,
            Set(1..<KistulentzProjectFormat.currentVersion),
            "Every prior project schema must retain a frozen on-disk fixture before the format version advances."
        )
    }

    @MainActor
    func testFrozenV09ProjectFixtureUpgradesAndReopensWithoutChangingMarkdown() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/UpgradeProjects/v0.9", isDirectory: true)
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root)
        try FileManager.default.copyItem(at: fixture, to: root)
        let openingURL = root.appendingPathComponent("Opening.md")
        let originalMarkdown = try Data(contentsOf: openingURL)

        let firstStore = WritingProjectStore()
        try firstStore.openProject(at: root)

        XCTAssertTrue(firstStore.lastMigrationResult?.didMigrate == true)
        XCTAssertEqual(firstStore.manifest?.formatVersion, KistulentzProjectFormat.currentVersion)
        XCTAssertEqual(firstStore.selectedChapterPath, "Opening.md")
        XCTAssertEqual(try Data(contentsOf: openingURL), originalMarkdown)
        XCTAssertNotNil(
            try ProjectCompatibilityManager.availableBackups(at: root)
                .first { $0.reason == .preMigration && $0.formatVersion == 1 }
        )

        firstStore.closeProject()
        let reopenedStore = WritingProjectStore()
        try reopenedStore.openProject(at: root)

        XCTAssertTrue(reopenedStore.isOpen)
        XCTAssertFalse(reopenedStore.lastMigrationResult?.didMigrate == true)
        XCTAssertEqual(reopenedStore.text, String(decoding: originalMarkdown, as: UTF8.self))
        XCTAssertEqual(try Data(contentsOf: openingURL), originalMarkdown)
    }

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

    func testMigrationEscalatesTheErrorWhenItsOwnAutomaticRollbackAlsoFails() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Locked Rollback", kind: .fiction)
        let projectURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent("project.json")
        let outlineURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent("outline.json")
        try setIntegerField("formatVersion", to: 1, in: projectURL)
        try setIntegerField("formatVersion", to: 1, in: outlineURL)

        // project.json is migrated before outline.json, so it's already been bumped to the
        // current version by the time outline.json's update fails here. The automatic rollback
        // (restoreJSONFiles) restores its backed-up files in alphabetical order and stops at the
        // first failure -- "outline.json" sorts before "project.json" -- so locking outline.json
        // blocks its own restore *and*, because the rollback never gets to project.json, leaves
        // project.json's already-bumped version un-rolled-back too.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: outlineURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: outlineURL.path) }

        XCTAssertThrowsError(try ProjectCompatibilityManager.prepareForOpen(at: root)) { error in
            guard case ProjectCompatibilityError.migrationFailedAndRollbackIncomplete = error else {
                return XCTFail("Expected migrationFailedAndRollbackIncomplete, got \(error)")
            }
        }
        // This is the real-world consequence the escalated error above is disclosing -- the fix
        // makes the error tell the truth about it, not undo it (restoreJSONFiles's own recovery
        // logic is unchanged; it stops at the first failure the same way it always has).
        XCTAssertEqual(try integerField("formatVersion", in: projectURL), KistulentzProjectFormat.currentVersion)
        XCTAssertEqual(try integerField("formatVersion", in: outlineURL), 1)
    }

    func testMigrationRollbackErrorDescriptionNamesBothFailuresDistinctly() {
        let error = ProjectCompatibilityError.migrationFailedAndRollbackIncomplete(
            migrationReason: "outline.json could not be updated",
            rollbackReason: "the backup copy of outline.json is missing"
        )

        let description = try? XCTUnwrap(error.errorDescription)

        XCTAssertTrue(description?.contains("outline.json could not be updated") == true)
        XCTAssertTrue(description?.contains("the backup copy of outline.json is missing") == true)
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

    private func markdownFingerprints(at root: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator where url.pathExtension.caseInsensitiveCompare("md") == .orderedSame {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            result[relative] = try Data(contentsOf: url)
        }
        return result
    }
}
