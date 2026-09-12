import XCTest
@testable import Kistulentz

/// `WritingProjectStore`'s five sub-stores (`researchStore`, `publicationStore`,
/// `betaReadersStore`, `styleLearningStore`, `searchStore`) are each constructed once, lazily,
/// with closures that wire them back into the parent store's `rootURL`/`chapters`/`outlineNodes`/
/// `text`/`errorMessage`. Every existing test that wants "realistic" sub-store behavior either
/// constructs the sub-store directly with its own hand-written fakes (`ProjectSubstoreTests.swift`),
/// or — for `SearchStore` — hand-copies the same closures WritingProjectStore.swift already
/// defines. Either way, the actual production wiring on `WritingProjectStore` itself never runs.
/// These tests go through the real `store.<subStore>` properties instead, so a break in that
/// wiring (a wrong capture, a typo'd key path) would actually fail a test.
final class WritingProjectStoreWiringTests: XCTestCase {
    @MainActor
    func testOpenProjectThrowsWhenTheCurrentProjectFailsToSaveFirst() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let currentRoot = try WritingProjectDisk.createProject(in: parent, name: "Current Locked", kind: .fiction)
        let otherRoot = try WritingProjectDisk.createProject(in: parent, name: "Other Project", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: currentRoot)
        store.updateText("# Chapter 1\n\nA change that cannot be saved.\n")
        let chapterURL = currentRoot.appendingPathComponent("Chapter 1.md")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: chapterURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: chapterURL.path) }

        XCTAssertThrowsError(try store.openProject(at: otherRoot)) { error in
            XCTAssertEqual(error as? WritingProjectError, .unsavedCurrentProject)
        }
        // The store should still be looking at the original (unsaved) project, not a half-opened
        // new one.
        XCTAssertEqual(store.rootURL, currentRoot.standardizedFileURL)
        XCTAssertTrue(store.isDirty)
    }

    @MainActor
    func testResearchStoreWiringReportsARealSaveFailureThroughTheParentStore() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Research Wiring", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        let notesURL = root.appendingPathComponent("Kistulentz Research Notes.md")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: notesURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: notesURL.path) }

        store.researchStore.updateResearchNotes("New notes that cannot be saved.")

        XCTAssertNotNil(store.errorMessage)
        XCTAssertNotEqual(store.researchStore.researchNotesText, "New notes that cannot be saved.")
    }

    @MainActor
    func testPublicationStoreWiringBuildsAPlanFromTheStoresLiveOutlineAndBibliography() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Publication Wiring", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        let source = ResearchSource(citeKey: "wiring2026", title: "Wiring Reference")
        store.researchStore.addResearchSource(source.id)
        let profileID = try XCTUnwrap(store.publicationStore.publicationArchive.profiles.first?.id)

        let plan = try store.publicationStore.publicationPlan(sources: [source], profileID: profileID, format: .epub)

        // The outline lives on the parent store; the bibliography lives on researchStore. Both
        // flow into the plan only if publicationStore's projectOutline/bibliography closures
        // actually read the live parent state rather than some stale or default value.
        XCTAssertTrue(plan.items.contains { $0.title == "Chapter 1" })
        XCTAssertEqual(plan.bibliography.sourceIDs, [source.id])
        XCTAssertEqual(plan.sources.map(\.id), [source.id])
    }

    @MainActor
    func testPublicationStoreWiringReportsARealSaveFailureThroughTheParentStore() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Publication Save Failure", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        let publicationURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent("publication.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: publicationURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: publicationURL.path) }
        var archive = store.publicationStore.publicationArchive
        archive.metadata.authors = ["Someone New"]

        store.publicationStore.updatePublicationArchive(archive)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertNotEqual(store.publicationStore.publicationArchive.metadata.authors, ["Someone New"])
    }

    @MainActor
    func testBetaReadersStoreWiringBuildsDocumentsFromTheCurrentChapterAndTheFullManuscript() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Beta Reader Wiring", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nA passage a beta reader can see.\n")

        let chapterDocuments = try store.betaReadersStore.documents(for: .chapter, selection: nil)
        let manuscriptDocuments = try store.betaReadersStore.documents(for: .manuscript, selection: nil)

        XCTAssertEqual(chapterDocuments.first?.relativePath, "Chapter 1.md")
        XCTAssertEqual(chapterDocuments.first?.text, "# Chapter 1\n\nA passage a beta reader can see.\n")
        XCTAssertEqual(manuscriptDocuments.map(\.relativePath), ["Chapter 1.md"])
    }

    @MainActor
    func testBetaReadersStoreFallsBackToSafeDefaultsAfterTheParentStoreIsDeallocated() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Beta Reader Dealloc Safety", kind: .fiction)
        var store: WritingProjectStore? = WritingProjectStore()
        try store?.openProject(at: root)
        // Hold the sub-store beyond the parent's lifetime -- its `[weak self]` closures should
        // degrade to safe defaults rather than crash once `store` is the only strong owner and
        // that reference goes away.
        let betaReadersStore = store!.betaReadersStore

        store = nil

        let chapterDocuments = try betaReadersStore.documents(for: .chapter, selection: nil)
        let manuscriptDocuments = try betaReadersStore.documents(for: .manuscript, selection: nil)

        XCTAssertEqual(chapterDocuments, [ManuscriptDocument(relativePath: "Chapter", title: "Chapter", text: "")])
        XCTAssertEqual(manuscriptDocuments, [])
    }

    @MainActor
    func testBetaReadersStoreWiringReportsARealSaveFailureThroughTheParentStore() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Beta Reader Save Failure", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        // The readers file doesn't exist until the first save, so create it once up front and
        // only then lock it -- an immutable *directory* would also block the atomic write's
        // temporary file, which isn't the failure this test wants to isolate.
        try ManuscriptProjectDisk.saveCustomBetaReaders([], at: root)
        let readersURL = WritingProjectDisk.metadataURL(at: root).appendingPathComponent("beta-readers.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: readersURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: readersURL.path) }

        store.betaReadersStore.addCustomBetaReader(name: "The Skeptic", focus: "plot holes", audience: .fiction)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.betaReadersStore.customBetaReaders.isEmpty)
    }

    @MainActor
    func testStyleLearningStoreWiringReportsARealSaveFailureThroughTheParentStore() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Style Wiring", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        let styleURL = root.appendingPathComponent("Kistulentz Style.md")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: styleURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: styleURL.path) }

        store.styleLearningStore.saveStyle("A style guide that cannot be saved.")

        XCTAssertNotNil(store.errorMessage)
        XCTAssertNotEqual(store.styleLearningStore.styleText, "A style guide that cannot be saved.")
    }

    @MainActor
    func testSearchStoreWiringSearchesTheStoresLiveChaptersAndSavesTheCurrentDocumentFirst() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Search Wiring", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nThe lighthouse keeper counted the waves.\n")

        store.searchStore.search("lighthouse")
        try await waitUntil { !store.searchStore.isSearching }

        // saveCurrentDocument() ran before the search, so the live edit (not yet explicitly
        // saved) was already on disk for chapters() + the real searcher to find.
        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(store.searchStore.searchResults.first?.chapterPath, "Chapter 1.md")
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testSearchStoreWiringReportsARealSearchFailureThroughTheParentStore() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Search Failure Wiring", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        // store.chapters still lists "Chapter 1.md" even after the file underneath it is gone,
        // exactly like a chapter deleted or moved outside the app.
        try FileManager.default.removeItem(at: root.appendingPathComponent("Chapter 1.md"))

        store.searchStore.search("lighthouse")
        try await waitUntil { !store.searchStore.isSearching }

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.searchStore.searchResults.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Store-Wiring-Test-\(UUID().uuidString)", isDirectory: true)
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
            if clock.now >= deadline { throw ExpectedWiringTestError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum ExpectedWiringTestError: LocalizedError {
    case timedOut

    var errorDescription: String? { "Timed out waiting for the search to finish." }
}
