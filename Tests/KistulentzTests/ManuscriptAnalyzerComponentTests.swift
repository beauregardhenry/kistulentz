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
