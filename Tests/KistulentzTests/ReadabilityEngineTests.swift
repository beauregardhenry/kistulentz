import XCTest
@testable import Kistulentz

final class ReadabilityEngineTests: XCTestCase {
    func testBasicStatistics() {
        let result = ReadabilityEngine.analyze(
            "Clear writing helps readers. Short sentences work.",
            targetGrade: 8
        )

        XCTAssertEqual(result.stats.words, 7)
        XCTAssertEqual(result.stats.sentences, 2)
        XCTAssertGreaterThanOrEqual(result.stats.gradeLevel, 0)
        XCTAssertLessThanOrEqual(result.stats.readabilityScore, 100)
    }

    func testFlagsLongSentences() {
        let text = "This deliberately long sentence contains far too many separate words and clauses for a reader who wants to understand the central point without stopping to reconstruct the author's argument from the beginning."
        let result = ReadabilityEngine.analyze(text, targetGrade: 8)

        XCTAssertTrue(result.issues.contains { $0.category == .veryHardSentence })
    }

    func testFindsSimplerPhrasesAndAdverbs() {
        let result = ReadabilityEngine.analyze(
            "In order to finish, we moved quickly and requested additional assistance.",
            targetGrade: 8
        )

        XCTAssertTrue(result.issues.contains { $0.category == .adverb && $0.excerpt == "quickly" })
        XCTAssertTrue(result.issues.contains { $0.category == .complexPhrase && $0.replacement == "to" })
        XCTAssertTrue(result.issues.contains { $0.category == .complexPhrase && $0.replacement == "more" })
        XCTAssertTrue(result.issues.contains { $0.category == .complexPhrase && $0.replacement == "help" })
    }

    func testDetectsPassiveVoice() {
        let result = ReadabilityEngine.analyze(
            "The final report was completed by the team.",
            targetGrade: 8
        )

        XCTAssertTrue(result.issues.contains { $0.category == .passiveVoice })
    }

    func testMarkdownSyntaxDoesNotInflateWordCount() {
        let result = ReadabilityEngine.analyze(
            "# Heading\n\nRead [the guide](https://example.com) today.",
            targetGrade: 8
        )

        XCTAssertEqual(result.stats.words, 5)
    }
}
