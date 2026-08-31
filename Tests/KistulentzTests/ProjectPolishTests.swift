import XCTest
@testable import Kistulentz

final class ProjectPolishTests: XCTestCase {
    @MainActor
    func testScanContinuesAfterOneDocumentFails() async {
        enum ExpectedFailure: Error { case unreadable }
        let service = ProjectPolishService(documentAnalyzer: { document, _, _ in
            if document.relativePath == "Broken.md" { throw ExpectedFailure.unreadable }
            return ProjectPolishDocumentAnalysis(
                changes: [Self.change(path: document.relativePath, title: document.title)],
                advisoryCount: 1,
                skippedCount: 2
            )
        })
        let documents = [
            ManuscriptDocument(relativePath: "One.md", title: "One", text: "utilize"),
            ManuscriptDocument(relativePath: "Broken.md", title: "Broken", text: "bad"),
            ManuscriptDocument(relativePath: "Three.md", title: "Three", text: "utilize")
        ]

        let report = await service.scan(
            documents: documents,
            targetGrade: 8,
            styleDecisions: []
        )

        XCTAssertEqual(report.completedDocumentCount, 3)
        XCTAssertEqual(report.changes.map(\.chapterPath), ["One.md", "Three.md"])
        XCTAssertEqual(report.failures.map(\.chapterPath), ["Broken.md"])
        XCTAssertFalse(report.wasCancelled)
    }

    @MainActor
    func testScanStopsCleanlyWhenCancellationIsRequested() async {
        var cancellationChecks = 0
        let service = ProjectPolishService(
            documentAnalyzer: { document, _, _ in
                ProjectPolishDocumentAnalysis(
                    changes: [Self.change(path: document.relativePath, title: document.title)],
                    advisoryCount: 0,
                    skippedCount: 0
                )
            },
            cancellationRequested: {
                cancellationChecks += 1
                return cancellationChecks > 1
            }
        )
        let documents = (1...5).map {
            ManuscriptDocument(relativePath: "\($0).md", title: "\($0)", text: "utilize")
        }

        let report = await service.scan(
            documents: documents,
            targetGrade: 8,
            styleDecisions: []
        )

        XCTAssertTrue(report.wasCancelled)
        XCTAssertEqual(report.completedDocumentCount, 1)
        XCTAssertEqual(report.changes.count, 1)
    }

    @MainActor
    func testStagesUseCorrectnessThenReadabilityThenStyle() {
        XCTAssertEqual(ProjectPolishService.stage(for: [.spelling, .adverb]), .correctness)
        XCTAssertEqual(ProjectPolishService.stage(for: [.veryHardSentence, .passiveVoice]), .readability)
        XCTAssertEqual(ProjectPolishService.stage(for: [.adverb, .passiveVoice]), .styleAndVoice)
    }

    func testChangeSetIncludesOnlyEnabledStagesAndSelectedChanges() {
        var excluded = Self.change(path: "Style.md", title: "Style", stage: .styleAndVoice)
        excluded.isIncluded = false
        let report = ProjectPolishReport(
            changes: [
                Self.change(path: "Correct.md", title: "Correct", stage: .correctness),
                Self.change(path: "Clear.md", title: "Clear", stage: .readability),
                excluded
            ],
            failures: [],
            completedDocumentCount: 3,
            totalDocumentCount: 3,
            advisoryCount: 0,
            skippedCount: 0,
            wasCancelled: false
        )

        let set = report.changeSet(including: [.correctness])
        XCTAssertEqual(set.includedChanges.map(\.chapterPath), ["Correct.md"])
    }

    @MainActor
    func testStaleProjectPolishDoesNotOverwriteTheFile() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(
            in: parent,
            name: "Safe Polish",
            kind: .nonfiction
        )
        let store = WritingProjectStore()
        try store.openProject(at: root)
        let original = "# Draft\n\nThe current passage.\n"
        store.updateText(original)
        store.saveNow()
        let stale = RevisionChangeSet(
            title: "Project Polish",
            summary: "",
            changes: [RevisionChange(
                chapterPath: "Draft.md",
                originalText: "an older passage",
                replacementText: "a replacement",
                explanation: ""
            )]
        )

        XCTAssertFalse(store.applyRevisionChangeSet(stale))
        XCTAssertEqual(try WritingProjectDisk.readChapter("Draft.md", at: root), original)
    }

    private static func change(
        path: String,
        title: String,
        stage: ProjectPolishStage = .correctness
    ) -> ProjectPolishChange {
        ProjectPolishChange(
            chapterPath: path,
            chapterTitle: title,
            stage: stage,
            categoryTitle: stage.shortTitle,
            originalText: "utilize",
            replacementText: "use",
            explanation: "Prefer the simpler word."
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Project-Polish-Test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
