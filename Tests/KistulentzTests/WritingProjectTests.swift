import XCTest
@testable import Kistulentz

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

    func testChapterIndexReusesUnchangedMetadataAndInvalidatesChangedFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Indexed", kind: .nonfiction)
        var manifest = try WritingProjectDisk.loadManifest(at: root)

        let first = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)
        XCTAssertEqual(first.first?.title, "Draft")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".kistulentz/chapter-index.json").path
        ))

        let draftURL = root.appendingPathComponent("Draft.md")
        try "# Revised Title\n\nMore words now appear here.\n".write(
            to: draftURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: draftURL.path
        )
        manifest = try WritingProjectDisk.loadManifest(at: root)
        let refreshed = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        XCTAssertEqual(refreshed.first?.title, "Revised Title")
        XCTAssertEqual(refreshed.first?.wordCount, 7)
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

    @MainActor
    func testFailedLateProjectLoadLeavesAFreshStoreClosed() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(
            in: parent,
            name: "Corrupt Target",
            kind: .fiction
        )
        try Data("not valid JSON".utf8).write(
            to: WritingProjectDisk.metadataURL(at: root)
                .appendingPathComponent("beta-readers.json"),
            options: .atomic
        )
        let store = WritingProjectStore()

        XCTAssertThrowsError(try store.openProject(at: root))

        XCTAssertFalse(store.isOpen)
        XCTAssertNil(store.rootURL)
        XCTAssertNil(store.manifest)
        XCTAssertTrue(store.chapters.isEmpty)
        XCTAssertNil(store.selectedChapterPath)
        XCTAssertEqual(store.text, "")
        XCTAssertTrue(store.betaReadersStore.customBetaReaders.isEmpty)
    }

    @MainActor
    func testFailedLateProjectLoadPreservesTheCurrentProjectAndSavesItsDraft() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let currentRoot = try WritingProjectDisk.createProject(
            in: parent,
            name: "Current Project",
            kind: .nonfiction
        )
        let corruptRoot = try WritingProjectDisk.createProject(
            in: parent,
            name: "Corrupt Project",
            kind: .fiction
        )
        try Data("not valid JSON".utf8).write(
            to: WritingProjectDisk.metadataURL(at: corruptRoot)
                .appendingPathComponent("beta-readers.json"),
            options: .atomic
        )

        let store = WritingProjectStore()
        try store.openProject(at: currentRoot)
        let updatedText = "# Draft\n\nThe current project must survive.\n"
        store.updateText(updatedText)
        let originalStyle = store.styleLearningStore.styleText
        let originalMigration = store.lastMigrationResult

        XCTAssertThrowsError(try store.openProject(at: corruptRoot))

        XCTAssertTrue(store.isOpen)
        XCTAssertEqual(store.rootURL, currentRoot.standardizedFileURL)
        XCTAssertEqual(store.projectName, "Current Project")
        XCTAssertEqual(store.selectedChapterPath, "Draft.md")
        XCTAssertEqual(store.text, updatedText)
        XCTAssertEqual(store.styleLearningStore.styleText, originalStyle)
        XCTAssertEqual(store.lastMigrationResult, originalMigration)
        XCTAssertFalse(store.hasUnsavedChapterChanges)
        XCTAssertEqual(
            try WritingProjectDisk.readChapter("Draft.md", at: currentRoot),
            updatedText
        )
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

    @MainActor
    func testSearchStoreKeepsOnlyTheNewestQueryResult() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Search", kind: .nonfiction)
        let core = WritingProjectStore()
        try core.openProject(at: root)
        let search = makeSearchStore(core: core) { query, _, _ in
            if query == "slow" {
                try? await Task.sleep(for: .milliseconds(120))
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
            return [ProjectSearchResult(
                chapterPath: "Draft.md",
                chapterTitle: "Draft",
                line: 1,
                preview: query,
                range: NSRange(location: 0, length: query.utf16.count)
            )]
        }
        search.search("slow")
        try await Task.sleep(for: .milliseconds(10))
        search.search("newest")
        try await waitUntil { !search.isSearching }

        XCTAssertEqual(search.searchResults.map(\.preview), ["newest"])
        XCTAssertNil(core.errorMessage)
    }

    @MainActor
    func testSearchStoreResetCancelsWorkAndClearsProgress() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Search", kind: .nonfiction)
        let core = WritingProjectStore()
        try core.openProject(at: root)
        let search = makeSearchStore(core: core) { _, _, _ in
            try await Task.sleep(for: .seconds(5))
            return []
        }
        search.search("unfinished")
        await Task.yield()
        XCTAssertTrue(search.isSearching)

        search.reset()

        XCTAssertFalse(search.isSearching)
        XCTAssertTrue(search.searchResults.isEmpty)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(search.isSearching)
    }

    @MainActor
    func testSearchStoreReportsFailureAndStopsProgress() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Search", kind: .nonfiction)
        let core = WritingProjectStore()
        try core.openProject(at: root)
        let search = makeSearchStore(core: core) { _, _, _ in
            throw ExpectedSearchError.failed
        }

        search.search("failure")
        try await waitUntil { !search.isSearching }

        XCTAssertTrue(search.searchResults.isEmpty)
        XCTAssertEqual(core.errorMessage, ExpectedSearchError.failed.localizedDescription)
    }

    /// Every other `SearchStore` test above injects a fake `searcher`, so `SearchStore`'s own
    /// default -- the real, disk-backed, `Task.detached`/`withTaskCancellationHandler`-wrapped
    /// `searchDisk` actually used in production -- has never run. This constructs the store
    /// without overriding it.
    @MainActor
    func testSearchStoreWithTheRealDefaultSearcherFindsMatchesOnDisk() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Search", kind: .nonfiction)
        try WritingProjectDisk.writeChapter(
            "# Draft\n\nThe lighthouse appears here.\n",
            relativePath: "Draft.md",
            at: root
        )
        let core = WritingProjectStore()
        try core.openProject(at: root)
        let search = SearchStore(
            debounceDuration: .zero,
            projectRoot: { [weak core] in core?.rootURL },
            chapters: { [weak core] in core?.chapters ?? [] },
            saveCurrentDocument: { [weak core] in core?.saveNow() },
            reportError: { [weak core] error in core?.errorMessage = error.localizedDescription }
        )

        search.search("lighthouse")
        try await waitUntil { !search.isSearching }

        XCTAssertNil(core.errorMessage)
        XCTAssertEqual(search.searchResults.first?.chapterPath, "Draft.md")
    }

    @MainActor
    private func makeSearchStore(
        core: WritingProjectStore,
        searcher: @escaping SearchStore.Searcher
    ) -> SearchStore {
        SearchStore(
            debounceDuration: .zero,
            projectRoot: { [weak core] in core?.rootURL },
            chapters: { [weak core] in core?.chapters ?? [] },
            saveCurrentDocument: { [weak core] in core?.saveNow() },
            reportError: { [weak core] error in
                core?.errorMessage = error.localizedDescription
            },
            searcher: searcher
        )
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

    /// The restore above only ever restores a snapshot of the *currently selected* chapter.
    /// `restore(_:)` also has a branch for a snapshot belonging to some other chapter, which must
    /// flush the chapter being left before switching selection to the one being restored.
    @MainActor
    func testRestoringASnapshotFromAnotherChapterSwitchesSelectionAndSavesThePendingEdit() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "CrossChapterRestore", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nOriginal chapter one.\n")
        store.saveNow()
        store.createSnapshot(name: "Chapter1-Original", reason: "Named snapshot")
        let chapterOneSnapshot = try XCTUnwrap(store.snapshots.first { $0.name == "Chapter1-Original" })
        store.updateText("# Chapter 1\n\nEdited chapter one.\n")
        store.saveNow()

        store.createChapter(named: "Chapter 2")
        XCTAssertEqual(store.selectedChapterPath, "Chapter 2.md")
        store.updateText("# Chapter 2\n\nUnsaved chapter two edit.\n")

        store.restore(chapterOneSnapshot)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.selectedChapterPath, "Chapter 1.md", "restoring a snapshot from another chapter must switch selection to it")
        XCTAssertEqual(store.text, "# Chapter 1\n\nOriginal chapter one.\n")
        XCTAssertEqual(
            try WritingProjectDisk.readChapter("Chapter 2.md", at: root),
            "# Chapter 2\n\nUnsaved chapter two edit.\n",
            "the pending edit on the chapter being left must be saved before switching away from it"
        )
    }

    /// `restore(_:)` special-cases a Bible snapshot: rather than treating it as a chapter, it
    /// routes through `applyBibleUpdate`. No existing test restored a Bible snapshot.
    @MainActor
    func testRestoringABibleSnapshotRoutesThroughApplyBibleUpdate() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "BibleRestore", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        let originalBible = store.bibleText
        store.applyBibleUpdate(
            originalBible + "\nFirst bible fact.\n",
            reason: "Before first update",
            summary: "Added a fact.",
            forceSnapshot: true
        )
        let bibleSnapshot = try XCTUnwrap(store.snapshots.first { $0.chapterPath == ManuscriptProjectDisk.bibleFileName })
        store.applyBibleUpdate(
            originalBible + "\nFirst bible fact.\nSecond bible fact.\n",
            reason: "Before second update",
            summary: "Added another fact.",
            forceSnapshot: true
        )

        store.restore(bibleSnapshot)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.bibleText, originalBible, "restoring must roll the Bible back to the snapshot's content")
        XCTAssertEqual(try ManuscriptProjectDisk.loadBible(at: root), originalBible)
        XCTAssertEqual(store.lastBibleUpdate?.summary, "Restored Bible snapshot “\(bibleSnapshot.name)”.")
    }

    /// `currentContent(for:)` special-cases the Bible file and the manuscript report before
    /// falling back to the live in-memory buffer (for the selected chapter) or disk (for any
    /// other chapter) -- none of its four branches had a direct test.
    @MainActor
    func testCurrentContentDispatchesToBibleReportSelectedChapterOrDisk() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "CurrentContent", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        store.updateBibleText("Unsaved Bible edit.")
        XCTAssertEqual(try store.currentContent(for: ManuscriptProjectDisk.bibleFileName), "Unsaved Bible edit.")

        store.manuscriptReportText = "Unsaved report content."
        XCTAssertEqual(try store.currentContent(for: ManuscriptProjectDisk.reportFileName), "Unsaved report content.")

        store.updateText("# Chapter 1\n\nUnsaved chapter edit.\n")
        let selectedPath = try XCTUnwrap(store.selectedChapterPath)
        XCTAssertEqual(try store.currentContent(for: selectedPath), "# Chapter 1\n\nUnsaved chapter edit.\n")
        store.saveNow()

        store.createChapter(named: "Chapter 2")
        XCTAssertEqual(store.selectedChapterPath, "Chapter 2.md")
        XCTAssertEqual(
            try store.currentContent(for: "Chapter 1.md"),
            "# Chapter 1\n\nUnsaved chapter edit.\n",
            "a chapter other than the one selected must be read from disk"
        )
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

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { throw ExpectedSearchError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum ExpectedSearchError: LocalizedError {
    case failed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .failed: "Expected search failure."
        case .timedOut: "The test timed out waiting for search state."
        }
    }
}
