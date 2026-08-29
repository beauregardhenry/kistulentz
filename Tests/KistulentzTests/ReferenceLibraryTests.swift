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

    private func profile(
        wordCount: Int = 500,
        sentenceWords: Double = 14,
        firstPerson: Double = 0.2,
        thirdPerson: Double = 0.8
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
            characters: ["Elara", "Tomas"]
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
}
