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
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)
        let reopened = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)

        XCTAssertEqual(chapters.count, KistulentzScaleTargets.projectDocuments)
        XCTAssertEqual(reopened.reduce(0) { $0 + $1.wordCount }, KistulentzScaleTargets.manuscriptWords)
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

        let discovery = try ProjectImportSourceDiscovery.discover(from: [root])
        let converted = try discovery.sources.map(ProjectImportConversionService.load)

        XCTAssertEqual(discovery.sources.count, KistulentzScaleTargets.projectImportFiles)
        XCTAssertEqual(converted.count, KistulentzScaleTargets.projectImportFiles)
    }

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

        try ReferenceLibraryDisk.saveIndex(ReferenceLibraryIndex(books: books), to: root)
        let reopened = try ReferenceLibraryDisk.load(from: root)

        XCTAssertEqual(reopened.books.count, KistulentzScaleTargets.referenceBooks)
        XCTAssertEqual(Set(reopened.books.map(\.author)).count, 500)
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Scale-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
