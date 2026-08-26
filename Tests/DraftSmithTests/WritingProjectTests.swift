import XCTest
@testable import DraftSmith

final class WritingProjectTests: XCTestCase {
    func testCreatesNormalProjectFolderWithLocalMetadataAndStyleGuide() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try WritingProjectDisk.createProject(
            in: parent,
            name: "Harbor Book",
            kind: .fiction
        )
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        XCTAssertEqual(root.lastPathComponent, "Harbor Book")
        XCTAssertEqual(manifest.kind, .fiction)
        XCTAssertEqual(chapters.map(\.relativePath), ["Chapter 1.md"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".kistulentz/project.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Kistulentz Style.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Kistulentz Manuscript Report.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Kistulentz Bible.md").path
        ))
    }

    func testPreparesExistingFolderWithoutChangingMarkdownFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Introduction\n\nExisting prose.\n".write(
            to: root.appendingPathComponent("Introduction.md"),
            atomically: true,
            encoding: .utf8
        )

        try WritingProjectDisk.prepareExistingProject(
            at: root,
            name: "Existing Draft",
            kind: .nonfiction
        )

        let text = try String(
            contentsOf: root.appendingPathComponent("Introduction.md"),
            encoding: .utf8
        )
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        XCTAssertEqual(text, "# Introduction\n\nExisting prose.\n")
        XCTAssertEqual(manifest.kind, .nonfiction)
        XCTAssertEqual(manifest.chapterOrder, ["Introduction.md"])
    }

    @MainActor
    func testProjectStoreAutosavesAndReopensChapterOrderAndHistory() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Novel", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        store.updateText("# Chapter 1\n\nA changed opening.\n")
        store.saveNow()
        store.createChapter(named: "Chapter 2")
        store.updateText("# Chapter 2\n\nThe journey continues.\n")
        store.saveNow()
        store.moveChapters(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        store.closeProject()

        let reopened = WritingProjectStore()
        try reopened.openProject(at: root)

        XCTAssertEqual(reopened.chapters.map(\.relativePath), ["Chapter 2.md", "Chapter 1.md"])
        XCTAssertEqual(reopened.selectedChapterPath, "Chapter 2.md")
        XCTAssertEqual(reopened.text, "# Chapter 2\n\nThe journey continues.\n")
        XCTAssertGreaterThanOrEqual(reopened.snapshots.count, 2)
    }

    func testSearchFindsTextAcrossChaptersWithLocations() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Search", kind: .nonfiction)
        try WritingProjectDisk.writeChapter(
            "# Draft\n\nThe lighthouse appears here.\n",
            relativePath: "Draft.md",
            at: root
        )
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        let results = try WritingProjectDisk.search("lighthouse", chapters: chapters, at: root)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.chapterPath, "Draft.md")
        XCTAssertEqual(results.first?.line, 3)
        XCTAssertEqual(results.first?.range, NSRange(location: 13, length: 10))
    }

    func testStyleGuideLearnsAcceptedAndDeclinedChoicesWithoutOverwritingManualRules() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Style", kind: .fiction)
        var style = try ProjectStyleManager.loadStyle(at: root)
        style += "\n## Manual rule\n\nAlways capitalize the Tide.\n"
        try ProjectStyleManager.saveStyle(style, at: root)

        let text = "She moved quickly toward the Tide."
        let issue = WritingIssue(
            category: .adverb,
            range: (text as NSString).range(of: "quickly"),
            excerpt: "quickly",
            message: "Use a stronger verb.",
            replacement: "hurried"
        )
        try ProjectStyleManager.record(action: .accepted, issue: issue, at: root)
        try ProjectStyleManager.record(action: .declined, issue: issue, at: root)

        let learned = try ProjectStyleManager.loadStyle(at: root)
        XCTAssertTrue(learned.contains("Always capitalize the Tide."))
        XCTAssertTrue(learned.contains("Prefer `hurried` to `quickly`"))
        XCTAssertTrue(learned.contains("Keep `quickly` instead of `hurried`"))
        XCTAssertEqual(try ProjectStyleManager.loadDecisions(at: root).count, 2)
    }

    @MainActor
    func testRestoringSnapshotProtectsCurrentVersionAndRevisionDiffShowsChanges() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "History", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Draft\n\nFirst version.\n")
        store.saveNow()
        store.createSnapshot(name: "First", reason: "Named snapshot")
        let first = try XCTUnwrap(store.snapshots.first { $0.name == "First" })
        store.updateText("# Draft\n\nSecond version.\n")
        store.saveNow()

        let diff = RevisionDiff.compare(
            old: try store.content(for: first),
            new: store.text
        )
        XCTAssertTrue(diff.contains { $0.kind == .removed && $0.text == "First version." })
        XCTAssertTrue(diff.contains { $0.kind == .added && $0.text == "Second version." })

        let countBeforeRestore = store.snapshots.count
        store.restore(first)
        XCTAssertEqual(store.text, "# Draft\n\nFirst version.\n")
        XCTAssertGreaterThan(store.snapshots.count, countBeforeRestore)
    }

    @MainActor
    func testHighlightVisibilityPersistsInSettings() throws {
        let suiteName = "WritingProjectHighlightTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.toggleHighlight(.adverb)
        XCTAssertFalse(settings.isHighlightVisible(.adverb))

        let reopened = AppSettings(defaults: defaults)
        XCTAssertFalse(reopened.isHighlightVisible(.adverb))
        reopened.toggleHighlight(.adverb)
        XCTAssertTrue(reopened.isHighlightVisible(.adverb))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Project-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
