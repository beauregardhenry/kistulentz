import Foundation
import XCTest
@testable import Kistulentz

final class LocalPolishTests: XCTestCase {
    func testLocalPolishCreatesReviewableSafeChangesWithoutAProvider() throws {
        let text = "In order to commence, we utilize additional assistance."

        let result = LocalPolishService.polish(text: text, targetGrade: 8)
        let plan = try XCTUnwrap(result.plan)

        XCTAssertEqual(plan.origin, .local)
        XCTAssertEqual(result.appliedCount, 5)
        XCTAssertTrue(plan.isFullReplacementSafe)
        XCTAssertEqual(plan.polishedText, "To start, we use more help.")
        XCTAssertEqual(
            plan.applying(changeIDs: Set(plan.safeChanges.map(\.id))),
            plan.polishedText
        )
        XCTAssertTrue(SuggestionRuleValidator.isSafe(
            original: text,
            replacement: plan.polishedText,
            targetGrade: 8
        ))
    }

    func testLocalPolishNeverChangesFencedCodeInlineCodeLinksOrURLs() throws {
        let text = """
        `in order to` stays code.

        [in order to](https://example.com/in-order-to) stays a link.

        ```swift
        let phrase = "in order to"
        ```

        We work in order to help.
        """

        let result = LocalPolishService.polish(text: text, targetGrade: 8)
        let polished = try XCTUnwrap(result.plan?.polishedText)

        XCTAssertTrue(polished.contains("`in order to`"))
        XCTAssertTrue(polished.contains("[in order to](https://example.com/in-order-to)"))
        XCTAssertTrue(polished.contains("let phrase = \"in order to\""))
        XCTAssertTrue(polished.contains("We work to help."))
        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(result.skippedCount, 3)
    }

    func testLocalPolishLeavesAdvisoryOnlyGuidanceForAuthorJudgment() {
        let result = LocalPolishService.polish(
            text: "We moved quickly.",
            targetGrade: 8
        )

        XCTAssertNil(result.plan)
        XCTAssertEqual(result.appliedCount, 0)
        XCTAssertEqual(result.advisoryCount, 1)
    }

    func testLocalPolishRejectsStaleOverlappingAndRuleViolatingChanges() {
        let text = "Short utilize text."
        let source = text as NSString
        let utilizeRange = source.range(of: "utilize")
        let issues = [
            WritingIssue(
                category: .complexPhrase,
                range: utilizeRange,
                excerpt: "utilize",
                message: "First",
                replacement: "use"
            ),
            WritingIssue(
                category: .complexPhrase,
                range: utilizeRange,
                excerpt: "utilize",
                message: "Overlap",
                replacement: "employ"
            ),
            WritingIssue(
                category: .complexPhrase,
                range: NSRange(location: 0, length: 5),
                excerpt: "Stale",
                message: "Stale",
                replacement: "Fresh"
            ),
            WritingIssue(
                category: .grammar,
                range: source.range(of: "Short"),
                excerpt: "Short",
                message: "Unsafe",
                replacement: Array(repeating: "word", count: 40).joined(separator: " ")
            )
        ]

        let result = LocalPolishService.polish(
            text: text,
            targetGrade: 8,
            issues: issues
        )

        XCTAssertNil(result.plan)
        XCTAssertEqual(result.appliedCount, 0)
        XCTAssertEqual(result.skippedCount, 4)
    }

    func testLocalPolishDoesNotReuseAIReplacementCards() {
        let text = "We utilize tools."
        let issue = WritingIssue(
            category: .aiSuggestion,
            range: (text as NSString).range(of: "utilize"),
            excerpt: "utilize",
            message: "AI",
            replacement: "use",
            source: .ai
        )

        let result = LocalPolishService.polish(
            text: text,
            targetGrade: 8,
            issues: [issue]
        )

        XCTAssertNil(result.plan)
        XCTAssertEqual(result.appliedCount, 0)
    }
}
