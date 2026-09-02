import XCTest
@testable import Kistulentz

final class PolishedDraftPlannerTests: XCTestCase {
    func testCreatesIndividualChangedPassagesAndAppliesOnlySelectedChanges() {
        let original = "# Chapter\n\nThe first passage stays.\n\nWe moved quickly.\n\nThis is the ending."
        let polished = "# Chapter\n\nThe first passage stays.\n\nWe hurried.\n\nThis is a stronger ending."

        let plan = PolishedDraftPlanner.plan(original: original, polished: polished, targetGrade: 8)

        XCTAssertEqual(plan.changes.count, 2)
        XCTAssertEqual(plan.changes[0].originalText, "We moved quickly.\n")
        XCTAssertEqual(plan.changes[0].replacementText, "We hurried.\n")

        let result = plan.applying(changeIDs: [plan.changes[0].id])
        XCTAssertEqual(
            result,
            "# Chapter\n\nThe first passage stays.\n\nWe hurried.\n\nThis is the ending."
        )
    }

    func testPreservesInsertionsAndDeletionsExactly() {
        let original = "One.\nTwo.\nThree."
        let polished = "One.\nInserted.\nThree."

        let plan = PolishedDraftPlanner.plan(original: original, polished: polished, targetGrade: 8)

        XCTAssertEqual(plan.changes.count, 1)
        XCTAssertEqual(plan.applying(changeIDs: Set(plan.changes.map(\.id))), polished)
    }

    func testMarksReplacementUnsafeWhenItIntroducesANewLocalRule() {
        let original = "We ran."
        let polished = "We moved quickly."

        let plan = PolishedDraftPlanner.plan(original: original, polished: polished, targetGrade: 8)

        XCTAssertEqual(plan.changes.count, 1)
        XCTAssertFalse(plan.changes[0].isSafe)
        XCTAssertTrue(plan.changes[0].introducedRuleCategories.contains(.adverb))
        XCTAssertNil(plan.applying(changeIDs: [plan.changes[0].id]))
    }

    func testEmptyAndIdenticalDraftsHaveNoChanges() {
        XCTAssertTrue(
            PolishedDraftPlanner.plan(original: "", polished: "", targetGrade: 8).changes.isEmpty
        )
        XCTAssertTrue(
            PolishedDraftPlanner.plan(original: "Same", polished: "Same", targetGrade: 8).changes.isEmpty
        )
    }

    func testContextualValidationCatchesAProblemCreatedByTheSurroundingSentence() {
        let text = "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen."
        let range = (text as NSString).range(of: "One")

        let conflicts = SuggestionRuleValidator.introducedCategories(
            replacing: range,
            in: text,
            with: "One alpha beta gamma delta epsilon",
            targetGrade: 8
        )

        XCTAssertTrue(conflicts.contains(.hardSentence))
    }
}
