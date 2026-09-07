import XCTest
@testable import Kistulentz

final class ScaleTargetTests: XCTestCase {
    private var scaleTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["KISTULENTZ_RUN_SCALE_TESTS"] == "1"
    }

    func testApprovedScaleTargetsAreDocumentedInCode() {
        XCTAssertEqual(KistulentzScaleTargets.manuscriptWords, 2_000_000)
        XCTAssertEqual(KistulentzScaleTargets.projectDocuments, 2_000)
        XCTAssertEqual(KistulentzScaleTargets.projectImportFiles, 1_000)
        XCTAssertEqual(KistulentzScaleTargets.referenceBooks, 5_000)
    }

    func testTwoMillionWordTwoThousandDocumentProject() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("Manuscript")
        defer { try? FileManager.default.removeItem(at: root) }
        let sentence = "Clear systems help every reader. "
        let body = String(repeating: sentence, count: 199) + "Clear systems help."
        XCTAssertEqual(WritingProjectDisk.wordCount(in: body), 998)

        for index in 0..<KistulentzScaleTargets.projectDocuments {
            let text = "# Chapter \(index + 1)\n\n" + body
            try text.write(
                to: root.appendingPathComponent(String(format: "Chapter-%04d.md", index + 1)),
                atomically: true,
                encoding: .utf8
            )
        }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Scale Manuscript", kind: .fiction)
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let loadStarted = ContinuousClock.now
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)
        Self.record("project-load-2m-words", since: loadStarted)
        let reopened = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        let searchStarted = ContinuousClock.now
        let searchResults = try WritingProjectDisk.search(
            "phrase-that-does-not-exist-in-the-scale-manuscript",
            chapters: chapters,
            at: root
        )
        Self.record("project-search-2m-words-no-match", since: searchStarted)

        XCTAssertEqual(chapters.count, KistulentzScaleTargets.projectDocuments)
        XCTAssertEqual(reopened.reduce(0) { $0 + $1.wordCount }, KistulentzScaleTargets.manuscriptWords)
        XCTAssertTrue(searchResults.isEmpty)
    }

    func testOneThousandFileProjectImportBatch() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("Import")
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<KistulentzScaleTargets.projectImportFiles {
            try "Document \(index)\n".write(
                to: root.appendingPathComponent(String(format: "Document-%04d.txt", index)),
                atomically: true,
                encoding: .utf8
            )
        }

        let importStarted = ContinuousClock.now
        let discovery = try ProjectImportSourceDiscovery.discover(from: [root])
        let converted = try discovery.sources.map(ProjectImportConversionService.load)
        Self.record("project-import-1000-txt", since: importStarted)

        XCTAssertEqual(discovery.sources.count, KistulentzScaleTargets.projectImportFiles)
        XCTAssertEqual(converted.count, KistulentzScaleTargets.projectImportFiles)
    }

    @MainActor
    func testFiveThousandBookReferenceLibraryRoundTrip() throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let root = temporaryDirectory("References")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = ReferenceProfile(
            wordCount: 80_000,
            chapterCount: 20,
            gradeLevel: 8,
            averageSentenceWords: 14,
            sentenceVariation: 4,
            averageParagraphWords: 70,
            dialogueRatio: 0.2,
            firstPersonRatio: 0,
            thirdPersonRatio: 1,
            tempo: "Measured",
            voice: "Third person",
            tone: ["clear"],
            vocabulary: ["signal"],
            characters: []
        )
        let now = Date()
        let books = (0..<KistulentzScaleTargets.referenceBooks).map { index in
            LibraryBook(
                id: UUID(),
                sourcePath: "/Reference/Book-\(index).epub",
                sourceFileSize: 1_000,
                sourceModifiedAt: now,
                title: "Book \(index)",
                author: "Author \(index % 500)",
                genres: ["Genre \(index % 20)"],
                profile: profile,
                excerpts: [],
                importedAt: now,
                updatedAt: now
            )
        }

        let roundTripStarted = ContinuousClock.now
        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books), to: root)
        let reopened = try ReferenceLibraryDisk.load(from: root)
        Self.record("reference-round-trip-5000-books", since: roundTripStarted)

        XCTAssertEqual(reopened.books.count, KistulentzScaleTargets.referenceBooks)
        XCTAssertEqual(Set(reopened.books.map(\.author)).count, 500)

        let suite = "ScaleTargetReferenceFilter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(root.path, forKey: "referenceLibraryFolder")
        let store = ReferenceLibraryStore(defaults: defaults)
        let filterStarted = ContinuousClock.now
        let matches = store.choices(kind: .book, search: "Book 4999")
        Self.record("reference-filter-5000-books", since: filterStarted)
        XCTAssertEqual(matches.map(\.title), ["Book 4999"])
    }

    @MainActor
    func testProjectPolishMeasurementAndLargeProjectCancellation() async throws {
        try XCTSkipUnless(scaleTestsEnabled, "Run with KISTULENTZ_RUN_SCALE_TESTS=1.")
        let sampleText = "# Chapter\n\n" + String(
            repeating: "The detailed system was really utilized by the team in order to improve the result. ",
            count: 12
        )
        let measuredDocuments = (0..<200).map {
            ManuscriptDocument(relativePath: "Measured-\($0).md", title: "Measured \($0)", text: sampleText)
        }
        let polishStarted = ContinuousClock.now
        let polishReport = await ProjectPolishService().scan(
            documents: measuredDocuments,
            targetGrade: 8,
            styleDecisions: []
        )
        Self.record("project-polish-200-documents", since: polishStarted)
        XCTAssertEqual(polishReport.completedDocumentCount, measuredDocuments.count)

        let cancellationDocuments = (0..<KistulentzScaleTargets.projectDocuments).map {
            ManuscriptDocument(relativePath: "Cancel-\($0).md", title: "Cancel \($0)", text: "Draft")
        }
        let slowService = ProjectPolishService(documentAnalyzer: { _, _, _ in
            try await Task.sleep(for: .milliseconds(20))
            return ProjectPolishDocumentAnalysis(changes: [], advisoryCount: 0, skippedCount: 0)
        })
        let task = Task {
            await slowService.scan(
                documents: cancellationDocuments,
                targetGrade: 8,
                styleDecisions: []
            )
        }
        try await Task.sleep(for: .milliseconds(45))
        let cancellationStarted = ContinuousClock.now
        task.cancel()
        let cancelledReport = await task.value
        Self.record("project-polish-cancel-2000-documents", since: cancellationStarted)
        XCTAssertTrue(cancelledReport.wasCancelled)
        XCTAssertLessThan(cancelledReport.completedDocumentCount, cancellationDocuments.count)
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Scale-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func record(_ name: String, since started: ContinuousClock.Instant) {
        let elapsed = started.duration(to: .now)
        print("KISTULENTZ_PERFORMANCE \(name)=\(elapsed)")
    }
}
