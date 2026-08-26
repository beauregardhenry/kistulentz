import XCTest
@testable import DraftSmith

final class SuggestionApplicationPlannerTests: XCTestCase {
    func testAppliesNonOverlappingChangesFromEndToBeginning() {
        let text = "In order to move quickly, we requested additional help."
        let issues = [
            issue("In order to", replacement: "To", in: text),
            issue("quickly", replacement: "fast", in: text),
            issue("additional", replacement: "more", in: text)
        ]

        let plan = SuggestionApplicationPlanner.plan(issues: issues, in: text)

        XCTAssertEqual(plan.resultText, "To move fast, we requested more help.")
        XCTAssertEqual(plan.appliedCount, 3)
        XCTAssertEqual(plan.conflictCount, 0)
    }

    func testSkipsEveryMemberOfAnOverlappingConflict() {
        let text = "In order to finish."
        let issues = [
            issue("In order to", replacement: "To", in: text),
            issue("order", replacement: "sequence", in: text)
        ]

        let plan = SuggestionApplicationPlanner.plan(issues: issues, in: text)

        XCTAssertEqual(plan.resultText, text)
        XCTAssertEqual(plan.appliedCount, 0)
        XCTAssertEqual(plan.conflictCount, 2)
    }

    func testDeduplicatesIdenticalChangesAndSkipsStaleOrAdvisoryItems() {
        let text = "We moved quickly."
        let replacement = issue("quickly", replacement: "fast", in: text)
        let stale = WritingIssue(
            category: .grammar,
            range: NSRange(location: 0, length: 3),
            excerpt: "They",
            message: "Stale",
            replacement: "We"
        )
        let advisory = issue("moved", replacement: nil, in: text)

        let plan = SuggestionApplicationPlanner.plan(
            issues: [replacement, replacement, stale, advisory],
            in: text
        )

        XCTAssertEqual(plan.resultText, "We moved fast.")
        XCTAssertEqual(plan.appliedCount, 1)
        XCTAssertEqual(plan.duplicateCount, 1)
        XCTAssertEqual(plan.staleCount, 1)
        XCTAssertEqual(plan.advisoryCount, 1)
    }

    func testSingleSuggestionRelocatesOnlyWhenExcerptIsUnique() {
        let original = "We moved quickly."
        let shifted = "Yesterday, we moved quickly."
        let staleIssue = issue("quickly", replacement: "fast", in: original)

        let plan = SuggestionApplicationPlanner.planSingle(issue: staleIssue, in: shifted)

        XCTAssertEqual(plan.resultText, "Yesterday, we moved fast.")
        XCTAssertEqual(plan.appliedCount, 1)

        let ambiguous = "quickly, then quickly."
        let ambiguousIssue = WritingIssue(
            category: .adverb,
            range: NSRange(location: 99, length: 7),
            excerpt: "quickly",
            message: "Consider a stronger verb.",
            replacement: "fast"
        )
        XCTAssertFalse(SuggestionApplicationPlanner.planSingle(issue: ambiguousIssue, in: ambiguous).hasChanges)
    }

    private func issue(
        _ excerpt: String,
        replacement: String?,
        in text: String
    ) -> WritingIssue {
        WritingIssue(
            category: .complexPhrase,
            range: (text as NSString).range(of: excerpt),
            excerpt: excerpt,
            message: "Suggestion",
            replacement: replacement
        )
    }
}
