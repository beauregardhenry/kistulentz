import XCTest
@testable import Kistulentz

final class ManuscriptAnalyzerComponentTests: XCTestCase {
    func testFacadeAssemblesMetricAndContinuityComponentsWithoutChangingTheirResults() {
        let documents = sampleDocuments()
        let metrics = ManuscriptMetricsAnalyzer.analyze(documents: documents)
        let continuity = ManuscriptContinuityAnalyzer.analyze(
            documents: documents,
            chapters: metrics.chapters
        )
        let analysis = ManuscriptAnalyzer.analyze(
            projectName: "Refactor Fixture",
            kind: .nonfiction,
            documents: documents
        )

        XCTAssertEqual(analysis.chapters, metrics.chapters)
        XCTAssertEqual(analysis.totalWords, metrics.totalWords)
        XCTAssertEqual(analysis.totalSentences, metrics.totalSentences)
        XCTAssertEqual(analysis.overallGrade, metrics.overallGrade)
        XCTAssertEqual(analysis.averageSentenceWords, metrics.averageSentenceWords)
        XCTAssertEqual(analysis.averageParagraphWords, metrics.averageParagraphWords)
        XCTAssertEqual(analysis.dialogueRatio, metrics.dialogueRatio)
        XCTAssertEqual(analysis.citationCount, metrics.citationCount)
        XCTAssertEqual(analysis.adverbCount, metrics.adverbCount)
        XCTAssertEqual(analysis.passiveVoiceCount, metrics.passiveVoiceCount)
        XCTAssertEqual(analysis.entities, continuity.entities)
        XCTAssertEqual(analysis.keyTerms, continuity.keyTerms)
        XCTAssertEqual(analysis.repeatedPhrases, continuity.repeatedPhrases)
        XCTAssertEqual(analysis.timelineMarkers, continuity.timelineMarkers)
        XCTAssertEqual(findingValues(analysis.claimChecks), findingValues(continuity.claimChecks))
        XCTAssertEqual(findingValues(analysis.continuityChecks), findingValues(continuity.continuityChecks))
    }

    func testFacadeUsesTheDedicatedReportRenderer() {
        let analysis = ManuscriptAnalyzer.analyze(
            projectName: "Renderer Fixture",
            kind: .fiction,
            documents: sampleDocuments()
        )

        XCTAssertEqual(analysis.reportMarkdown, ManuscriptReportRenderer.renderReport(analysis))
        XCTAssertEqual(analysis.generatedBibleBlock, ManuscriptReportRenderer.renderBibleBlock(analysis))
    }

    func testContextComposesReportBibleAndDocumentSectionsInOrder() {
        let documents = [
            ManuscriptDocument(relativePath: "ch1.md", title: "Chapter One", text: "Once upon a time."),
            ManuscriptDocument(relativePath: "ch2.md", title: "Chapter Two", text: "The end.")
        ]

        let result = ManuscriptAnalyzer.context(documents: documents, report: "Report body.", bible: "Bible body.")

        XCTAssertTrue(result.contains("<local_manuscript_report>\nReport body.\n</local_manuscript_report>"))
        XCTAssertTrue(result.contains("<project_bible>\nBible body.\n</project_bible>"))
        XCTAssertTrue(result.contains("<manuscript_section path=\"ch1.md\" title=\"Chapter One\">\nOnce upon a time.\n</manuscript_section>"))
        XCTAssertTrue(result.contains("<manuscript_section path=\"ch2.md\" title=\"Chapter Two\">\nThe end.\n</manuscript_section>"))
        // Sections should appear in the order they were assembled: report, then bible, then documents.
        let reportRange = result.range(of: "<local_manuscript_report>")
        let bibleRange = result.range(of: "<project_bible>")
        let firstDocumentRange = result.range(of: "<manuscript_section path=\"ch1.md\"")
        XCTAssertNotNil(reportRange)
        XCTAssertNotNil(bibleRange)
        XCTAssertNotNil(firstDocumentRange)
        XCTAssertLessThan(reportRange!.lowerBound, bibleRange!.lowerBound)
        XCTAssertLessThan(bibleRange!.lowerBound, firstDocumentRange!.lowerBound)
    }

    func testContextSamplesALongReportIntoStartMiddleAndEndExcerpts() {
        let longReport = (1...5_000).map { "word\($0)" }.joined(separator: " ")

        let result = ManuscriptAnalyzer.context(documents: [], report: longReport, bible: "", maximumCharacters: 80_000)

        XCTAssertTrue(result.contains("…middle excerpt…"))
        XCTAssertTrue(result.contains("…ending excerpt…"))
        XCTAssertTrue(result.contains("word1 word2"))
        XCTAssertTrue(result.contains("word5000"))
        // The full 5,000-word report is far larger than the 18,000-character report allowance,
        // so it must have actually been trimmed down rather than included verbatim.
        XCTAssertLessThan(result.count, longReport.count)
    }

    func testContextEnforcesAnEightThousandCharacterFloorEvenWhenMaximumCharactersIsSmaller() {
        let longText = String(repeating: "a", count: 5_000)
        let documents = (1...5).map {
            ManuscriptDocument(relativePath: "doc\($0).md", title: "Doc \($0)", text: longText)
        }

        let result = ManuscriptAnalyzer.context(documents: documents, report: "", bible: "", maximumCharacters: 100)

        // If the 100-character request were honored literally there would be no room for any
        // document content; the 8,000-character floor should keep real content in the result.
        XCTAssertGreaterThan(result.count, 3_000)
        XCTAssertTrue(result.contains("path=\"doc1.md\""))
    }

    func testContextStopsAddingDocumentSectionsOnceTheCharacterBudgetIsExhausted() {
        let longText = String(repeating: "x", count: 20_000)
        let documents = (1...10).map {
            ManuscriptDocument(relativePath: "doc\($0).md", title: "Doc \($0)", text: longText)
        }

        let result = ManuscriptAnalyzer.context(documents: documents, report: "", bible: "", maximumCharacters: 8_000)

        let sectionCount = result.components(separatedBy: "<manuscript_section").count - 1
        XCTAssertGreaterThan(sectionCount, 0)
        XCTAssertLessThan(sectionCount, documents.count)
    }

    func testContextEvenlySamplesUpToSixtyDocumentsWhenMoreAreProvided() {
        let documents = (1...120).map {
            ManuscriptDocument(relativePath: "doc\($0).md", title: "Doc \($0)", text: "Short text \($0).")
        }

        let result = ManuscriptAnalyzer.context(documents: documents, report: "", bible: "", maximumCharacters: 1_000_000)

        let sectionCount = result.components(separatedBy: "<manuscript_section").count - 1
        XCTAssertEqual(sectionCount, 60)
        // Even sampling across 120 documents down to 60 picks every other document by index.
        XCTAssertTrue(result.contains("title=\"Doc 1\""))
        XCTAssertTrue(result.contains("title=\"Doc 119\""))
        XCTAssertFalse(result.contains("title=\"Doc 2\""))
        XCTAssertFalse(result.contains("title=\"Doc 120\""))
    }

    private func findingValues(_ findings: [ManuscriptFinding]) -> [String] {
        findings.map { "\($0.title)|\($0.detail)|\($0.chapterPath ?? "")" }
    }

    private func sampleDocuments() -> [ManuscriptDocument] {
        [
            ManuscriptDocument(
                relativePath: "Opening.md",
                title: "Opening",
                text: """
                # Opening

                Alice met Alicia in Chicago on Monday. Alice carefully reviewed the evidence.
                Research proves the change caused a 25% improvement in 2025.
                The repeated silver signal appeared. The repeated silver signal appeared.
                "We should verify it," Alice said.
                """
            ),
            ManuscriptDocument(
                relativePath: "Closing.md",
                title: "Closing",
                text: """
                # Closing

                Alicia returned to Chicago on Tuesday. The repeated silver signal appeared.
                According to the report, the result remained stable (Henry, 2025).
                "That is enough," Alicia said.
                """
            )
        ]
    }
}
