import Foundation
import XCTest
@testable import Kistulentz

final class ReferenceLibraryTests: XCTestCase {
    func testCombinesProfilesUsingBookWordCounts() {
        let first = profile(wordCount: 100, sentenceWords: 10, firstPerson: 0.8, thirdPerson: 0.2)
        let second = profile(wordCount: 300, sentenceWords: 20, firstPerson: 0.7, thirdPerson: 0.3)

        let combined = ReferenceProfileCombiner.merge([first, second])

        XCTAssertEqual(combined.wordCount, 400)
        XCTAssertEqual(combined.averageSentenceWords, 17.5, accuracy: 0.001)
        XCTAssertEqual(combined.voice, "intimate first-person")
    }

    func testGenreInferenceUsesMetadataAndLocalText() {
        let chapter = ReferenceChapter(
            id: 0,
            title: "Chapter",
            text: "Magic filled the kingdom. The wizard used a spell. A dragon guarded the enchanted sword."
        )
        let reference = EPUBReference(
            fileName: "sample.epub",
            title: "Sample",
            author: "Writer",
            subjects: ["Young Adult"],
            chapters: [chapter],
            profile: ReferenceProfileBuilder.build(chapters: [chapter])
        )

        let genres = LocalGenreClassifier.classify(reference: reference)

        XCTAssertTrue(genres.contains("Young Adult"))
        XCTAssertTrue(genres.contains("Fantasy"))
    }

    func testExcerptSelectionIsShortAndAttributed() {
        let text = Array(repeating: "Elara crossed the courtyard. \"Wait for me,\" Tomas said.", count: 80)
            .joined(separator: " ")
        let chapters = (0..<5).map { ReferenceChapter(id: $0, title: "Chapter \($0 + 1)", text: text) }
        let reference = EPUBReference(
            fileName: "sample.epub",
            title: "Sample",
            author: "Writer",
            chapters: chapters,
            profile: ReferenceProfileBuilder.build(chapters: chapters)
        )

        let excerpts = LibraryExcerptBuilder.select(from: reference)

        XCTAssertFalse(excerpts.isEmpty)
        XCTAssertLessThanOrEqual(excerpts.count, 4)
        XCTAssertTrue(excerpts.allSatisfy { $0.text.count <= 901 })
        XCTAssertTrue(excerpts.allSatisfy { !$0.section.isEmpty && !$0.purpose.isEmpty })
    }

    func testWritesAndReloadsMarkdownKnowledgeBase() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = book(title: "First Light", author: "Beau Henry", genres: ["Fantasy"])
        let second = book(title: "River Road", author: "Beau Henry", genres: ["Mystery"])
        let index = ReferenceLibraryIndex(books: [first, second], insights: [])

        try ReferenceLibraryDisk.regenerateKnowledgeBase(index, at: root)
        let reloaded = try ReferenceLibraryDisk.load(from: root)

        XCTAssertEqual(reloaded.books.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Kistulentz Library.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Books/\(first.id.uuidString).md").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Authors/\(ReferenceLibraryDisk.fileName(for: "Beau Henry"))").path
        ))
        let master = try String(contentsOf: root.appendingPathComponent("Kistulentz Library.md"), encoding: .utf8)
        XCTAssertTrue(master.contains("First Light"))
        XCTAssertTrue(master.contains("Fantasy"))
    }

    func testRecoveryJournalPreservesEveryCompletedBookUntilFullRegeneration() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = book(title: "Original", author: "Writer", genres: ["Fiction"])
        let recovered = book(title: "Recovered", author: "Writer", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [original], insights: []), to: root)

        try ReferenceLibraryDisk.appendRecoveryCheckpoint(recovered, at: root)

        let interruptedLoad = try ReferenceLibraryDisk.load(from: root)
        XCTAssertEqual(Set(interruptedLoad.books.map(\.title)), ["Original", "Recovered"])

        try ReferenceLibraryDisk.regenerateKnowledgeBase(interruptedLoad, at: root)
        let reopened = try ReferenceLibraryDisk.load(from: root)
        XCTAssertEqual(Set(reopened.books.map(\.title)), ["Original", "Recovered"])
    }

    func testRecoveryJournalUsesNewestVersionOfAnUpdatedBook() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = book(title: "Draft Title", author: "Writer", genres: ["Fiction"])
        var updated = original
        updated.title = "Corrected Title"
        updated.updatedAt = original.updatedAt.addingTimeInterval(30)
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [original], insights: []), to: root)

        try ReferenceLibraryDisk.appendRecoveryCheckpoint(updated, at: root)

        let reopened = try ReferenceLibraryDisk.load(from: root)
        XCTAssertEqual(reopened.books.count, 1)
        XCTAssertEqual(reopened.books.first?.title, "Corrected Title")
    }

    func testFailedKnowledgeBaseRegenerationDoesNotCommitTheNewIndex() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = book(title: "Persisted", author: "Writer", genres: ["Fiction"])
        try ReferenceLibraryDisk.regenerateKnowledgeBase(
            ReferenceLibraryIndex(books: [original], insights: []),
            at: root
        )

        let replacement = book(title: "Uncommitted", author: "Writer", genres: ["Fiction"])
        let blockedOutput = root.appendingPathComponent("Books/\(replacement.id.uuidString).md", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedOutput, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try ReferenceLibraryDisk.regenerateKnowledgeBase(
                ReferenceLibraryIndex(books: [replacement], insights: []),
                at: root
            )
        )

        let reopened = try ReferenceLibraryDisk.load(from: root)
        XCTAssertEqual(reopened.books.map(\.id), [original.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: blockedOutput.path))
    }

    @MainActor
    func testLoadsThousandsAndBuildsCombinedChoices() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let books = (0..<2_000).map { index in
            book(
                title: "Book \(index)",
                author: "Author \(index % 50)",
                genres: ["Genre \(index % 12)"]
            )
        }
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books, insights: []), to: root)
        let suiteName = "ReferenceLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")

        let store = ReferenceLibraryStore(defaults: defaults)

        XCTAssertEqual(store.books.count, 2_000)
        XCTAssertEqual(store.choices(kind: .author).count, 50)
        XCTAssertEqual(store.choices(kind: .genre).count, 12)
        let selected = Set(store.choices(kind: .author).prefix(2).map(\.id))
        XCTAssertEqual(store.reference(for: selected)?.sourceCount, 80)
    }

    @MainActor
    func testFolderImportCreatesLocalKnowledgeBase() async throws {
        let sourceRoot = temporaryDirectory()
        let libraryRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: libraryRoot)
        }
        _ = try makeFixtureEPUB(in: sourceRoot)
        let suiteName = "ReferenceLibraryImportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)
        store.setLocation(libraryRoot)

        store.importEPUBs(from: [sourceRoot])

        for _ in 0..<200 where store.isImporting || store.isSaving {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(store.isImporting)
        XCTAssertFalse(store.isSaving)
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books.first?.title, "The Lantern Road")
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("Kistulentz Library.md").path))
    }

    @MainActor
    func testImportRequiresALocationAndReportsAnEmptySelection() async throws {
        let suiteName = "ReferenceLibraryGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)

        store.importEPUBs(from: [])
        XCTAssertEqual(
            store.errorMessage,
            "Choose a Reference Library folder before importing EPUBs."
        )
        XCTAssertFalse(store.isImporting)

        let libraryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        store.setLocation(libraryRoot)
        await waitUntil { !store.isSaving }
        store.importEPUBs(from: [])
        await waitUntil { !store.isImporting }

        XCTAssertEqual(store.errorMessage, "No EPUB files were found in that selection.")
        XCTAssertEqual(store.importTotal, 0)
        XCTAssertEqual(store.importCompleted, 0)
    }

    @MainActor
    func testFolderImportContinuesPastBrokenEPUBAndPersistsCompletedBook() async throws {
        let sourceRoot = temporaryDirectory()
        let libraryRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: libraryRoot)
        }
        _ = try makeFixtureEPUB(in: sourceRoot)
        try Data("not an epub archive".utf8).write(
            to: sourceRoot.appendingPathComponent("Broken.epub"),
            options: .atomic
        )
        let suiteName = "ReferenceLibraryPartialImportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)
        store.setLocation(libraryRoot)
        await waitUntil { !store.isSaving }

        store.importEPUBs(from: [sourceRoot])
        await waitUntil(timeoutIterations: 400) { !store.isImporting && !store.isSaving }

        XCTAssertEqual(store.importTotal, 2)
        XCTAssertEqual(store.importCompleted, 2)
        XCTAssertEqual(store.importFailures.count, 1)
        XCTAssertTrue(store.importFailures[0].contains("Broken.epub"))
        XCTAssertEqual(store.books.map(\.title), ["The Lantern Road"])
        let reopened = try ReferenceLibraryDisk.load(from: libraryRoot)
        XCTAssertEqual(reopened.books.map(\.title), ["The Lantern Road"])
    }

    @MainActor
    func testReimportingAnUnchangedEPUBKeepsOneStableBook() async throws {
        let sourceRoot = temporaryDirectory()
        let libraryRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: libraryRoot)
        }
        let epub = try makeFixtureEPUB(in: sourceRoot)
        let suiteName = "ReferenceLibraryReimportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)
        store.setLocation(libraryRoot)
        await waitUntil { !store.isSaving }

        store.importEPUBs(from: [epub])
        await waitUntil(timeoutIterations: 400) { !store.isImporting && !store.isSaving }
        let first = try XCTUnwrap(store.books.first)

        store.importEPUBs(from: [epub])
        await waitUntil(timeoutIterations: 400) { !store.isImporting && !store.isSaving }

        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books.first?.id, first.id)
        XCTAssertEqual(store.books.first?.importedAt, first.importedAt)
        XCTAssertEqual(store.books.first?.updatedAt, first.updatedAt)
        XCTAssertEqual(store.importCompleted, 1)
        XCTAssertTrue(store.importFailures.isEmpty)
    }

    @MainActor
    func testReimportingAModifiedEPUBUpdatesTheExistingBookInPlace() async throws {
        let sourceRoot = temporaryDirectory()
        let libraryRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: libraryRoot)
        }
        let epub = try makeFixtureEPUB(in: sourceRoot)
        let suiteName = "ReferenceLibraryReimportModifiedTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)
        store.setLocation(libraryRoot)
        await waitUntil { !store.isSaving }

        store.importEPUBs(from: [epub])
        await waitUntil(timeoutIterations: 400) { !store.isImporting && !store.isSaving }
        let first = try XCTUnwrap(store.books.first)

        // Rebuild the fixture at the same path and push its modification date forward, so the
        // "unchanged, skip" shortcut can't apply -- this must update the existing book in place
        // rather than skipping it or creating a duplicate.
        try FileManager.default.removeItem(at: epub)
        _ = try makeFixtureEPUB(in: sourceRoot)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: epub.path
        )

        store.importEPUBs(from: [epub])
        await waitUntil(timeoutIterations: 400) { !store.isImporting && !store.isSaving }

        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books.first?.id, first.id, "the same source path must update the existing book's identity, not create a new one")
        let updatedAt = try XCTUnwrap(store.books.first?.updatedAt)
        XCTAssertGreaterThan(updatedAt, first.updatedAt)
        XCTAssertEqual(store.importCompleted, 1)
        XCTAssertTrue(store.importFailures.isEmpty)
    }

    @MainActor
    func testCancellingImportImmediatelyLeavesAUsablePersistedLibrary() async throws {
        let sourceRoot = temporaryDirectory()
        let libraryRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: libraryRoot)
        }
        _ = try makeFixtureEPUB(in: sourceRoot)
        let suiteName = "ReferenceLibraryCancellationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)
        store.setLocation(libraryRoot)
        await waitUntil { !store.isSaving }

        store.importEPUBs(from: [sourceRoot])
        XCTAssertTrue(store.isImporting)
        store.cancelImport()
        await waitUntil { !store.isSaving }

        XCTAssertFalse(store.isImporting)
        XCTAssertEqual(store.currentImportName, "")
        XCTAssertNoThrow(try ReferenceLibraryDisk.load(from: libraryRoot))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: libraryRoot.appendingPathComponent("Kistulentz Library.md").path
        ))
    }

    @MainActor
    func testManualMetadataCorrectionNormalizesDeduplicatesAndPersists() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = book(title: "Original Title", author: "Writer", genres: ["Fiction"])
        try ReferenceLibraryDisk.regenerateKnowledgeBase(
            ReferenceLibraryIndex(books: [original], insights: []),
            at: root
        )
        let suiteName = "ReferenceLibraryCorrectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)

        await store.updateBook(
            id: original.id,
            title: "   ",
            author: "   ",
            genres: [" Mystery ", "mystery", "", "  Thriller  "]
        )

        let corrected = try XCTUnwrap(store.book(id: original.id))
        XCTAssertEqual(corrected.title, "Original Title")
        XCTAssertEqual(corrected.author, "Unknown Author")
        XCTAssertEqual(corrected.genres, ["Mystery", "Thriller"])
        let reopened = try ReferenceLibraryDisk.load(from: root)
        XCTAssertEqual(reopened.books.first?.title, corrected.title)
        XCTAssertEqual(reopened.books.first?.author, corrected.author)
        XCTAssertEqual(reopened.books.first?.genres, corrected.genres)
    }

    @MainActor
    func testAnalysisAndDeepeningRequireASelectionWithoutStartingWork() throws {
        let suiteName = "ReferenceLibrarySelectionGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)
        let settings = AppSettings(defaults: defaults)

        store.analyzeStructure(choiceIDs: [])
        XCTAssertEqual(store.errorMessage, "Select at least one book, author, or genre to analyze.")
        XCTAssertFalse(store.isAnalyzingStructure)

        store.errorMessage = nil
        store.deepen(choiceIDs: [], settings: settings)
        XCTAssertEqual(store.errorMessage, "Select at least one book, author, or genre to deepen.")
        XCTAssertFalse(store.isDeepening)
    }

    @MainActor
    func testAnalyzeStructureSkipsBooksWithACachedProfileUnlessRefreshing() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var analyzed = book(title: "Already Analyzed", author: "Author", genres: ["Fiction"])
        analyzed.profile = profile(structuralProfile: .empty)
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [analyzed], insights: []), to: root)
        let suiteName = "ReferenceLibraryCachedProfileTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)
        let choiceID = try XCTUnwrap(store.choices(kind: .book).first?.id)

        store.analyzeStructure(choiceIDs: [choiceID])

        XCTAssertEqual(
            store.errorMessage,
            "Every selected reference already has a cached Benepar profile. Choose Refresh All Profiles if you want to rebuild them."
        )
        XCTAssertFalse(store.isAnalyzingStructure)

        // `refreshExisting: true` must not stop at the same message -- whatever happens next
        // (installing/using the language pack) is environment-dependent, so this only asserts
        // that the cache filter itself was bypassed.
        store.errorMessage = nil
        store.analyzeStructure(choiceIDs: [choiceID], refreshExisting: true)
        XCTAssertNotEqual(
            store.errorMessage,
            "Every selected reference already has a cached Benepar profile. Choose Refresh All Profiles if you want to rebuild them."
        )
    }

    @MainActor
    func testDeepenRequiresAReadyProviderBeforeStartingWork() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = book(title: "Some Title", author: "Some Author", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [source], insights: []), to: root)
        let suiteName = "ReferenceLibraryDeepenGuardTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)
        let choiceID = try XCTUnwrap(store.choices(kind: .book).first?.id)
        let settings = AppSettings(defaults: defaults)

        settings.provider = .openAI
        store.deepen(choiceIDs: [choiceID], settings: settings)
        XCTAssertEqual(
            store.errorMessage,
            "Add your OpenAI API key and choose a model in Settings before using Deepen with AI."
        )
        XCTAssertFalse(store.isDeepening)

        store.errorMessage = nil
        settings.provider = .ollama
        settings.ollamaModel = ""
        store.deepen(choiceIDs: [choiceID], settings: settings)
        XCTAssertEqual(
            store.errorMessage,
            "Detect and choose an installed Ollama model in Settings before using Deepen with AI."
        )
        XCTAssertFalse(store.isDeepening)
    }

    // MARK: - analyzeStructure / deepen with the async pipeline injected

    @MainActor
    func testAnalyzeStructureFailsWhenTheLanguagePackIsNotAvailable() throws {
        let (store, choiceID, parent) = try openedStoreWithOneBook(languagePackAvailable: { false })
        defer { try? FileManager.default.removeItem(at: parent) }

        store.analyzeStructure(choiceIDs: [choiceID])

        XCTAssertEqual(store.errorMessage, "Install the English structural-analysis pack in Settings first.")
        XCTAssertFalse(store.isAnalyzingStructure)
    }

    @MainActor
    func testAnalyzeStructureSurfacesAnErrorWhenLocatingTheLanguagePackThrows() throws {
        let (store, choiceID, parent) = try openedStoreWithOneBook(languagePackAvailable: {
            throw SimulatedFailure(message: "Simulated locate failure.")
        })
        defer { try? FileManager.default.removeItem(at: parent) }

        store.analyzeStructure(choiceIDs: [choiceID])

        XCTAssertEqual(store.errorMessage, "Simulated locate failure.")
        XCTAssertFalse(store.isAnalyzingStructure)
    }

    @MainActor
    func testAnalyzeStructureSucceedsAndPersistsTheUpdatedProfile() async throws {
        let expectedProfile = StructuralProfile(
            sentencesAnalyzed: 10, sentencesAvailable: 10, averageTreeDepth: 4, maximumTreeDepth: 6,
            averageClausesPerSentence: 1.5, subordinateSentenceRatio: 0.2, averageLongestNounPhraseWords: 3,
            longNounPhraseRatio: 0.1, coordinationRatio: 0.1, passiveCandidateRatio: 0.05, fragmentRatio: 0
        )
        let (store, choiceID, parent) = try openedStoreWithOneBook(
            languagePackAvailable: { true },
            structuralAnalyzer: { _, _, _, _ in BeneparAnalysis(metrics: expectedProfile, issues: []) }
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let bookID = try XCTUnwrap(store.books.first?.id)

        store.analyzeStructure(choiceIDs: [choiceID])
        await waitUntil { !store.isAnalyzingStructure }

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.structuralAnalysisCompleted, 1)
        XCTAssertEqual(store.book(id: bookID)?.profile.structuralProfile, expectedProfile)
        let rootURL = try XCTUnwrap(store.rootURL)
        XCTAssertEqual(try ReferenceLibraryDisk.load(from: rootURL).books.first?.profile.structuralProfile, expectedProfile)
    }

    @MainActor
    func testAnalyzeStructureStopsTheBatchAndReportsAnErrorWhenTheAnalyzerFails() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let books = [
            book(title: "First", author: "Author", genres: ["Fiction"]),
            book(title: "Second", author: "Author", genres: ["Fiction"])
        ]
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books, insights: []), to: root)
        let suiteName = "ReferenceLibraryAnalyzeFailureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let callCount = LockedTestValue<Int>(0)
        let store = ReferenceLibraryStore(
            defaults: defaults,
            languagePackAvailable: { true },
            structuralAnalyzer: { _, _, _, _ in
                callCount.value += 1
                return nil
            }
        )
        let choiceIDs = Set(store.choices(kind: .book).map(\.id))

        store.analyzeStructure(choiceIDs: choiceIDs)
        await waitUntil { !store.isAnalyzingStructure }

        XCTAssertTrue(store.errorMessage?.contains("Benepar could not finish") ?? false)
        XCTAssertEqual(callCount.value, 1, "a book the analyzer could not finish must stop the batch instead of moving on to the next one")
    }

    @MainActor
    func testDeepenSucceedsAndAppendsAPersistedInsight() async throws {
        let (store, choiceID, parent, settings) = try openedStoreWithOneBookForDeepening()
        defer { try? FileManager.default.removeItem(at: parent) }
        MockDeepeningURLProtocol.handler = { request in
            let payload = """
            {"summary":"Clear summary","style":"Direct","voice":"Third person","tone":"Measured","vocabulary":"Concrete","characterContinuity":"Consistent","tempo":"Steady","techniques":["Varied sentences"],"suggestedGenres":["Fantasy"]}
            """
            let body: [String: Any] = ["message": ["role": "assistant", "content": payload]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        defer { MockDeepeningURLProtocol.handler = nil }

        store.deepen(choiceIDs: [choiceID], settings: settings)
        await waitUntil { !store.isDeepening }

        XCTAssertNil(store.errorMessage)
        let insight = try XCTUnwrap(store.insights.first)
        XCTAssertEqual(insight.markdown.contains("Clear summary"), true)
        XCTAssertEqual(insight.provider, AIProvider.ollama.title)
        let rootURL = try XCTUnwrap(store.rootURL)
        XCTAssertEqual(try ReferenceLibraryDisk.load(from: rootURL).insights.first?.id, insight.id)
    }

    @MainActor
    func testDeepenReportsAnErrorAndDoesNotAppendAnInsightWhenTheProviderCallFails() async throws {
        let (store, choiceID, parent, settings) = try openedStoreWithOneBookForDeepening()
        defer { try? FileManager.default.removeItem(at: parent) }
        MockDeepeningURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { MockDeepeningURLProtocol.handler = nil }

        store.deepen(choiceIDs: [choiceID], settings: settings)
        await waitUntil { !store.isDeepening }

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.insights.isEmpty)
    }

    @MainActor
    func testLibraryNameAuthorsCountAndGenresCountReflectTheLoadedLibrary() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let books = [
            book(title: "First", author: "Ada Lovelace", genres: ["Fiction"]),
            book(title: "Second", author: "ADA LOVELACE", genres: ["fiction"]),
            book(title: "Third", author: "Grace Hopper", genres: ["Nonfiction"])
        ]
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books, insights: []), to: root)
        let suiteName = "ReferenceLibraryCountsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let unopened = ReferenceLibraryStore(defaults: defaults)
        XCTAssertEqual(unopened.libraryName, "No library selected")
        XCTAssertEqual(unopened.authorsCount, 0)
        XCTAssertEqual(unopened.genresCount, 0)

        unopened.setLocation(root)

        XCTAssertEqual(unopened.libraryName, root.lastPathComponent)
        XCTAssertEqual(unopened.authorsCount, 2, "author names differing only by case must count as one author")
        XCTAssertEqual(unopened.genresCount, 2, "genre names differing only by case must count as one genre")
    }

    @MainActor
    func testInitReportsAnErrorWhenTheRememberedLocationCannotBeReopened() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // A directory where the index file is expected makes `ReferenceLibraryDisk.load` throw.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".kistulentz", isDirectory: true).appendingPathComponent("library.json"),
            withIntermediateDirectories: true
        )
        let suiteName = "ReferenceLibraryInitFailureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")

        let store = ReferenceLibraryStore(defaults: defaults)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage?.contains("could not reopen the reference library") ?? false)
        XCTAssertNil(store.rootURL)
        XCTAssertTrue(store.books.isEmpty)
    }

    @MainActor
    func testSetLocationReportsAnErrorWhenTheFolderCannotBeUsed() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        // A regular file where a directory is expected makes `ReferenceLibraryDisk.load` throw
        // when it tries to create the library's metadata subdirectories there.
        let blockedPath = parent.appendingPathComponent("blocked")
        try Data().write(to: blockedPath)
        let suiteName = "ReferenceLibrarySetLocationFailureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferenceLibraryStore(defaults: defaults)

        store.setLocation(blockedPath)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage?.contains("could not use that folder") ?? false)
        XCTAssertNil(store.rootURL, "a folder that could not be opened must not become the active location")
    }

    @MainActor
    func testUpdateBookOnAnUnknownIDIsANoOp() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = book(title: "Existing", author: "Author", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [existing], insights: []), to: root)
        let suiteName = "ReferenceLibraryUnknownUpdateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)

        await store.updateBook(id: UUID(), title: "New Title", author: "New Author", genres: ["New"])

        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books.first?.id, existing.id)
        XCTAssertEqual(store.books.first?.title, existing.title)
        XCTAssertEqual(store.books.first?.author, existing.author)
        XCTAssertEqual(store.books.first?.genres, existing.genres)
    }

    @MainActor
    func testReferenceForMultipleBooksCombinesTitlesAuthorsAndOnlyMatchingInsights() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sameAuthorFirst = book(title: "Voice One", author: "Shared Author", genres: ["Fiction"])
        let sameAuthorSecond = book(title: "Voice Two", author: "Shared Author", genres: ["Fiction"])
        let differentAuthor = book(title: "Voice Three", author: "Other Author", genres: ["Fiction"])
        let matchingInsight = LibraryAIInsight(
            id: UUID(), title: "Combined take", bookIDs: [sameAuthorFirst.id, sameAuthorSecond.id],
            provider: "Ollama", model: "writer:latest", markdown: "Matches.", createdAt: Date()
        )
        let nonMatchingInsight = LibraryAIInsight(
            id: UUID(), title: "Unrelated", bookIDs: [differentAuthor.id],
            provider: "Ollama", model: "writer:latest", markdown: "Does not match.", createdAt: Date()
        )
        try ReferenceLibraryDisk.saveIndex(
            ReferenceLibraryIndex(books: [sameAuthorFirst, sameAuthorSecond, differentAuthor], insights: [matchingInsight, nonMatchingInsight]),
            to: root
        )
        let suiteName = "ReferenceLibraryCombinedReferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)
        let choices = store.choices(kind: .book)
        let sameAuthorChoiceIDs = Set(choices.filter { $0.bookIDs.contains(sameAuthorFirst.id) || $0.bookIDs.contains(sameAuthorSecond.id) }.map(\.id))
        let allChoiceIDs = Set(choices.map(\.id))

        let sameAuthorReference = try XCTUnwrap(store.reference(for: sameAuthorChoiceIDs))
        XCTAssertEqual(sameAuthorReference.sourceCount, 2)
        XCTAssertEqual(sameAuthorReference.title, "2 combined references")
        XCTAssertEqual(sameAuthorReference.author, "Shared Author", "a single shared author across every selected book must be preserved")
        XCTAssertEqual(sameAuthorReference.learnedInsights, "# Combined take\nMatches.")

        let allReference = try XCTUnwrap(store.reference(for: allChoiceIDs))
        XCTAssertNil(allReference.author, "differing authors across the selection must not invent a single author")
        XCTAssertNil(store.reference(for: []), "an empty selection must not produce a reference")
    }

    @MainActor
    func testCleanedGenresFallsBackToUnclassifiedWhenEveryValueIsBlank() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = book(title: "Existing", author: "Author", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [existing], insights: []), to: root)
        let suiteName = "ReferenceLibraryBlankGenresTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)

        await store.updateBook(id: existing.id, title: existing.title, author: existing.author, genres: ["  ", ""])

        XCTAssertEqual(store.book(id: existing.id)?.genres, ["Unclassified"])
    }

    @MainActor
    func testGroupedChoicesUseSingularAndPluralBookCounts() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let books = [
            book(title: "Solo", author: "Solo Author", genres: ["Solo Genre"]),
            book(title: "First", author: "Shared Author", genres: ["Shared Genre"]),
            book(title: "Second", author: "Shared Author", genres: ["Shared Genre"])
        ]
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books, insights: []), to: root)
        let suiteName = "ReferenceLibraryGroupedChoicesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)

        let authorChoices = store.choices(kind: .author)
        XCTAssertEqual(authorChoices.first { $0.title == "Solo Author" }?.subtitle, "1 book")
        XCTAssertEqual(authorChoices.first { $0.title == "Shared Author" }?.subtitle, "2 books")

        let genreChoices = store.choices(kind: .genre)
        XCTAssertEqual(genreChoices.first { $0.title == "Solo Genre" }?.subtitle, "1 book")
        XCTAssertEqual(genreChoices.first { $0.title == "Shared Genre" }?.subtitle, "2 books")
    }

    @MainActor
    func testPersistReportsAnErrorWhenTheIndexCannotBeSaved() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = book(title: "Existing", author: "Author", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [existing], insights: []), to: root)
        let suiteName = "ReferenceLibraryPersistFailureTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)
        let indexURL = root.appendingPathComponent(".kistulentz").appendingPathComponent("library.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: indexURL.path) }

        await store.updateBook(id: existing.id, title: "New Title", author: existing.author, genres: existing.genres)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage?.contains("could not be saved") ?? false)
        XCTAssertEqual(
            store.book(id: existing.id)?.title, "New Title",
            "the in-memory edit is not rolled back just because the write failed"
        )
    }

    func testLibraryBookBuildsAReferenceWithoutInventingAnEmptyAuthor() {
        let id = UUID()
        let source = LibraryBook(
            id: id,
            sourcePath: "/Books/Harbor.epub",
            sourceFileSize: 42,
            sourceModifiedAt: nil,
            title: "Harbor",
            author: "   ",
            genres: ["Literary Fiction"],
            profile: profile(),
            excerpts: [
                LibraryExcerpt(section: "Chapter 2", purpose: "Dialogue", text: "A representative exchange."),
                LibraryExcerpt(section: "Chapter 7", purpose: "Tempo", text: "A faster representative passage.")
            ],
            importedAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let reference = source.reference

        XCTAssertEqual(reference.id, id)
        XCTAssertEqual(reference.fileName, "Harbor.epub")
        XCTAssertNil(reference.author)
        XCTAssertEqual(reference.subjects, ["Literary Fiction"])
        XCTAssertEqual(reference.chapters.map(\.id), [0, 1])
        XCTAssertEqual(reference.chapters.map(\.title), ["Chapter 2 — Dialogue", "Chapter 7 — Tempo"])
        XCTAssertEqual(reference.chapters.map(\.text), source.excerpts.map(\.text))
        XCTAssertEqual(reference.profile.wordCount, source.profile.wordCount)
        XCTAssertEqual(reference.profile.averageSentenceWords, source.profile.averageSentenceWords)
        XCTAssertEqual(reference.profile.voice, source.profile.voice)
    }

    func testReferenceLibraryKindsExposeStableLabelsAndSymbols() {
        XCTAssertEqual(LibraryReferenceKind.allCases.map(\.id), ["book", "author", "genre"])
        XCTAssertEqual(LibraryReferenceKind.allCases.map(\.title), ["Books", "Authors", "Genres"])
        XCTAssertEqual(
            LibraryReferenceKind.allCases.map(\.systemImage),
            ["book.closed", "person.2", "tag"]
        )
    }

    func testReferenceDeepeningMarkdownRendersEverySectionAndOptionalList() {
        let deepening = ReferenceDeepening(
            summary: "The collection favors direct openings.",
            style: "Concrete and economical.",
            voice: "Close third person.",
            tone: "Reflective.",
            vocabulary: "Plain words with nautical precision.",
            characterContinuity: "Names and motivations remain stable.",
            tempo: "Measured with short action bursts.",
            techniques: ["Open scenes late", "End chapters on decisions"],
            suggestedGenres: ["Literary Fiction", "Historical Fiction"]
        )

        let markdown = deepening.markdown

        for heading in [
            "## Editorial synthesis", "### Style", "### Voice", "### Tone",
            "### Vocabulary", "### Characters and continuity", "### Tempo",
            "### Techniques", "### Suggested genres"
        ] {
            XCTAssertTrue(markdown.contains(heading), "Missing \(heading)")
        }
        XCTAssertTrue(markdown.contains("- Open scenes late"))
        XCTAssertTrue(markdown.contains("- Historical Fiction"))
        XCTAssertFalse(markdown.hasSuffix("\n"))
    }

    func testReferenceDeepeningMarkdownOmitsEmptyOptionalSections() {
        let markdown = ReferenceDeepening(
            summary: "Summary",
            style: "Style",
            voice: "Voice",
            tone: "Tone",
            vocabulary: "Vocabulary",
            characterContinuity: "Continuity",
            tempo: "Tempo",
            techniques: [],
            suggestedGenres: []
        ).markdown

        XCTAssertFalse(markdown.contains("### Techniques"))
        XCTAssertFalse(markdown.contains("### Suggested genres"))
    }

    func testReferenceLibraryIndexRoundTripPreservesBooksInsightsAndExcerpts() throws {
        let source = book(title: "First Light", author: "Beau Henry", genres: ["Fantasy"])
        let insight = LibraryAIInsight(
            id: UUID(),
            title: "Combined voice",
            bookIDs: [source.id],
            provider: "Ollama",
            model: "writer:latest",
            markdown: "## Voice\n\nMeasured.",
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let index = ReferenceLibraryIndex(schemaVersion: 1, books: [source], insights: [insight])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let reopened = try decoder.decode(ReferenceLibraryIndex.self, from: encoder.encode(index))

        XCTAssertEqual(reopened.schemaVersion, 1)
        XCTAssertEqual(reopened.books.first?.id, source.id)
        XCTAssertEqual(reopened.books.first?.excerpts, source.excerpts)
        XCTAssertEqual(reopened.insights.first?.id, insight.id)
        XCTAssertEqual(reopened.insights.first?.bookIDs, [source.id])
        XCTAssertEqual(reopened.insights.first?.markdown, insight.markdown)
    }

    private func profile(
        wordCount: Int = 500,
        sentenceWords: Double = 14,
        firstPerson: Double = 0.2,
        thirdPerson: Double = 0.8,
        structuralProfile: StructuralProfile? = nil
    ) -> ReferenceProfile {
        ReferenceProfile(
            wordCount: wordCount,
            chapterCount: 4,
            gradeLevel: 7.5,
            averageSentenceWords: sentenceWords,
            sentenceVariation: 6,
            averageParagraphWords: 55,
            dialogueRatio: 0.22,
            firstPersonRatio: firstPerson,
            thirdPersonRatio: thirdPerson,
            tempo: "steady",
            voice: firstPerson > thirdPerson ? "intimate first-person" : "observational third-person",
            tone: ["balanced"],
            vocabulary: ["lantern", "courtyard"],
            characters: ["Elara", "Tomas"],
            structuralProfile: structuralProfile
        )
    }

    private func book(title: String, author: String, genres: [String]) -> LibraryBook {
        LibraryBook(
            id: UUID(),
            sourcePath: "/Books/\(title).epub",
            sourceFileSize: 1_000,
            sourceModifiedAt: Date(timeIntervalSince1970: 100),
            title: title,
            author: author,
            genres: genres,
            profile: profile(),
            excerpts: [LibraryExcerpt(section: "Chapter 1", purpose: "Opening voice", text: "A short representative passage from \(title).")],
            importedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Library-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFixtureEPUB(in outputDirectory: URL) throws -> URL {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("EPUBSource", isDirectory: true)
        let outputURL = outputDirectory.appendingPathComponent("fixture.epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = fixtureDirectory
        process.arguments = ["-X", "-q", "-r", outputURL.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return outputURL
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 200,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for the reference-library operation to finish")
    }

    /// A store with one saved book, ready to call `analyzeStructure` against, with the Benepar
    /// seam(s) under test injected and the rest defaulted.
    @MainActor
    private func openedStoreWithOneBook(
        languagePackAvailable: (() throws -> Bool)? = nil,
        structuralAnalyzer: ((String, Int, Bool, Bool) async -> BeneparAnalysis?)? = nil
    ) throws -> (store: ReferenceLibraryStore, choiceID: String, parent: URL) {
        let root = temporaryDirectory()
        let source = book(title: "Some Title", author: "Some Author", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [source], insights: []), to: root)
        let suiteName = "ReferenceLibraryAnalyzeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(
            defaults: defaults,
            languagePackAvailable: languagePackAvailable,
            structuralAnalyzer: structuralAnalyzer
        )
        let choiceID = try XCTUnwrap(store.choices(kind: .book).first?.id)
        return (store, choiceID, root)
    }

    /// A store with one saved book and an Ollama-ready `AppSettings` (no API key needed), wired to
    /// a `ReferenceDeepeningService` whose session routes through `MockDeepeningURLProtocol`.
    @MainActor
    private func openedStoreWithOneBookForDeepening() throws -> (
        store: ReferenceLibraryStore, choiceID: String, parent: URL, settings: AppSettings
    ) {
        let root = temporaryDirectory()
        let source = book(title: "Some Title", author: "Some Author", genres: ["Fiction"])
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: [source], insights: []), to: root)
        let suiteName = "ReferenceLibraryDeepenTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepeningURLProtocol.self]
        let store = ReferenceLibraryStore(
            defaults: defaults,
            deepeningService: ReferenceDeepeningService(session: URLSession(configuration: configuration))
        )
        let choiceID = try XCTUnwrap(store.choices(kind: .book).first?.id)
        let settings = AppSettings(defaults: defaults)
        settings.provider = .ollama
        settings.ollamaModel = "test-model"
        return (store, choiceID, root, settings)
    }
}

private struct SimulatedFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class MockDeepeningURLProtocol: URLProtocol {
    private static let handlerStorage = LockedTestValue<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { handlerStorage.value }
        set { handlerStorage.value = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
