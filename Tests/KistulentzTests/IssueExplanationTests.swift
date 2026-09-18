import XCTest
@testable import Kistulentz

/// Tests for `IssueCategory.whyThisMatters` (#93) -- the craft-principle explanation shown on
/// demand in `IssueCard`'s "Why this matters" disclosure. Every category gets one, including the
/// objective categories `practicePrompt` (#90) skips: understanding why a typo costs a reader's
/// trust is worth knowing even though there's no craft judgment to practice on the fix itself.
final class IssueExplanationTests: XCTestCase {
    /// A generic restatement would be short -- roughly the length of `title` or `message` with a
    /// few words changed. A real explanation of the underlying principle runs longer than that.
    /// This is a coarse proxy, not a content-quality check, but it does catch the failure mode
    /// this issue exists to fix: a case that got a one-line label instead of a reason.
    private static let minimumSubstantiveLength = 60

    func testEveryCategoryHasASubstantiveExplanation() {
        for category in IssueCategory.allCases {
            let explanation = category.whyThisMatters
            XCTAssertGreaterThanOrEqual(
                explanation.count,
                Self.minimumSubstantiveLength,
                "\(category)'s whyThisMatters reads like a restated label, not an explanation"
            )
        }
    }

    /// The explanation is a distinct piece of copy from the always-visible label -- if a case
    /// accidentally returned `title` (or something derived from it) instead of writing an actual
    /// explanation, this catches it.
    func testExplanationIsNotJustTheCategoryTitle() {
        for category in IssueCategory.allCases {
            XCTAssertNotEqual(category.whyThisMatters, category.title)
            XCTAssertFalse(
                category.whyThisMatters.localizedCaseInsensitiveContains("check whether"),
                "\(category)'s whyThisMatters should explain the principle, not just repeat a check-whether instruction"
            )
        }
    }

    /// Spot-checks a few categories for actual content, not just length -- catches a copy/paste
    /// mistake that happened to land two categories' explanations on each other.
    func testSpotCheckedCategoriesExplainTheirOwnPrinciple() {
        XCTAssertTrue(IssueCategory.adverb.whyThisMatters.localizedCaseInsensitiveContains("verb"))
        XCTAssertTrue(IssueCategory.passiveVoice.whyThisMatters.localizedCaseInsensitiveContains("actor"))
        XCTAssertTrue(IssueCategory.spelling.whyThisMatters.localizedCaseInsensitiveContains("interruption"))
        XCTAssertTrue(IssueCategory.continuity.whyThisMatters.localizedCaseInsensitiveContains("trust"))
        XCTAssertTrue(IssueCategory.avoidedWord.whyThisMatters.localizedCaseInsensitiveContains("already"))
    }
}
