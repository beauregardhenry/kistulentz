import Foundation
import XCTest
@testable import Kistulentz

/// Covers the pure model logic in `AIRequestModels.swift`: `SelectionRewriteKind`,
/// `SelectionRewriteGoal`, `AIRequestPurpose`'s display strings, and the `hasStyleGuide`/
/// `hasReference` branches of `AIRequestBuilder` that the higher-level service tests never
/// happen to exercise directly.
final class AIRequestModelsTests: XCTestCase {
    func testEverySelectionRewriteKindHasAUniqueIDMatchingItsRawValueAndNonEmptyDisplayStrings() {
        var seenTitles = Set<String>()
        for kind in SelectionRewriteKind.allCases {
            XCTAssertEqual(kind.id, kind.rawValue)
            XCTAssertFalse(kind.title.isEmpty, "Missing title for \(kind)")
            XCTAssertFalse(kind.systemImage.isEmpty, "Missing systemImage for \(kind)")
            XCTAssertTrue(seenTitles.insert(kind.title).inserted, "Duplicate title for \(kind): \(kind.title)")
        }
    }

    func testSelectionRewriteGoalTitleStripsTheEllipsisFromTheKindTitleByDefault() {
        let goal = SelectionRewriteGoal(kind: .adjustTone)
        XCTAssertEqual(goal.title, "Adjust Tone")
        XCTAssertFalse(goal.title.contains("…"))
    }

    func testSelectionRewriteGoalTitleIncludesTheRequestedToneWhenAdjustingTone() {
        let goal = SelectionRewriteGoal(kind: .adjustTone, requestedTone: "warmer")
        XCTAssertEqual(goal.title, "Adjust Tone: warmer")
    }

    func testSelectionRewriteGoalTitleFallsBackWhenTheRequestedToneIsEmpty() {
        let goal = SelectionRewriteGoal(kind: .adjustTone, requestedTone: "")
        XCTAssertEqual(goal.title, "Adjust Tone")
    }

    func testSelectionRewriteGoalTitleIgnoresARequestedToneOnANonToneKind() {
        let goal = SelectionRewriteGoal(kind: .shorten, requestedTone: "warmer")
        XCTAssertEqual(goal.title, "Shorten")
    }

    func testEverySelectionRewriteGoalInstructionDescribesItsOperationDistinctly() {
        let expectedSubstrings: [SelectionRewriteKind: String] = [
            .correct: "Correct grammar",
            .simplify: "Reduce reading difficulty",
            .shorten: "meaningfully shorter",
            .expand: "sensory, explanatory, or connective detail",
            .strengthenVerbs: "precise, active verbs",
            .adjustTone: "Adjust the selection toward this user-requested tone",
            .matchReferences: "high-level voice, vocabulary, tone, and tempo"
        ]
        for kind in SelectionRewriteKind.allCases {
            let goal = SelectionRewriteGoal(kind: kind)
            let expected = try! XCTUnwrap(expectedSubstrings[kind])
            XCTAssertTrue(goal.instruction.contains(expected), "Unexpected instruction for \(kind): \(goal.instruction)")
            XCTAssertFalse(goal.instruction.contains("Address this editor concern"))
        }
    }

    func testAdjustToneInstructionFallsBackWhenNoToneWasRequested() {
        let goal = SelectionRewriteGoal(kind: .adjustTone, requestedTone: nil)
        XCTAssertTrue(goal.instruction.contains("the tone stated by the user"))
    }

    func testAdjustToneInstructionNamesTheRequestedTone() {
        let goal = SelectionRewriteGoal(kind: .adjustTone, requestedTone: "more playful")
        XCTAssertTrue(goal.instruction.contains("more playful"))
    }

    func testInstructionAppendsATrimmedEditorConcernWhenPresent() {
        let goal = SelectionRewriteGoal(kind: .shorten, issueInstruction: "  Watch the pacing here.  ")
        XCTAssertTrue(goal.instruction.hasSuffix("Address this editor concern: Watch the pacing here."))
    }

    func testInstructionIgnoresAWhitespaceOnlyEditorConcern() {
        let goal = SelectionRewriteGoal(kind: .shorten, issueInstruction: "   \n  ")
        XCTAssertFalse(goal.instruction.contains("Address this editor concern"))
    }

    func testAIRequestPurposeTitlesAndActionTitlesForEveryCase() {
        let cases: [(AIRequestPurpose, title: String, actionTitle: String)] = [
            (
                .selectionRewrite(goal: SelectionRewriteGoal(kind: .shorten), targetGrade: 8),
                "Preview Shorten",
                "Create Alternatives"
            ),
            (.referenceDeepening, "Preview Reference Analysis", "Deepen Reference"),
            (.manuscriptReport(kind: .fiction), "Preview Manuscript Report Request", "Deepen Report"),
            (.manuscriptBible(kind: .fiction), "Preview Bible Request", "Deepen Bible"),
            (
                .betaReader(readerName: "The Skeptic", focus: "plot holes", scope: .manuscript, kind: .fiction),
                "Preview The Skeptic",
                "Run AI Beta Reader"
            ),
            (
                .outlineSynopsis(projectKind: .fiction, nodeKind: .chapter, title: "The Long Way Home"),
                "Preview Synopsis for The Long Way Home",
                "Suggest Synopsis"
            ),
            (
                .systemicRevision(kind: .fiction, passes: [.structure, .pacing]),
                "Preview Systemic Revision Request",
                "Deepen Revision Findings"
            )
        ]
        for (purpose, expectedTitle, expectedActionTitle) in cases {
            XCTAssertEqual(purpose.title, expectedTitle)
            XCTAssertEqual(purpose.actionTitle, expectedActionTitle)
        }
    }

    func testSelectionRewriteInstructionsAppendTheStyleGuideAndReferenceSentencesOnlyWhenRequested() {
        let goal = SelectionRewriteGoal(kind: .shorten)
        let purpose = AIRequestPurpose.selectionRewrite(goal: goal, targetGrade: 8)

        let bare = AIRequestBuilder.instructions(for: purpose, hasStyleGuide: false, hasReference: false)
        XCTAssertFalse(bare.contains("Use the project style guide as an editorial constraint."))
        XCTAssertFalse(bare.contains("Use references only for high-level craft patterns."))

        let withStyleGuide = AIRequestBuilder.instructions(for: purpose, hasStyleGuide: true, hasReference: false)
        XCTAssertTrue(withStyleGuide.contains("Use the project style guide as an editorial constraint."))

        let withReference = AIRequestBuilder.instructions(for: purpose, hasStyleGuide: false, hasReference: true)
        XCTAssertTrue(withReference.contains("Use references only for high-level craft patterns."))
    }

    func testSelectionRewriteInputIncludesTheStyleGuideAndReferenceSectionsOnlyWhenSupplied() {
        let purpose = AIRequestPurpose.selectionRewrite(goal: SelectionRewriteGoal(kind: .shorten), targetGrade: 8)

        let bare = AIRequestBuilder.input(for: purpose, primaryText: "The selection.", styleGuide: nil, referenceContext: nil)
        XCTAssertEqual(bare, "<selection>\nThe selection.\n</selection>")

        let withBoth = AIRequestBuilder.input(
            for: purpose,
            primaryText: "The selection.",
            styleGuide: "Prefer short sentences.",
            referenceContext: "<reference_profile>voice notes</reference_profile>"
        )
        XCTAssertEqual(
            withBoth,
            """
            <project_style>
            Prefer short sentences.
            </project_style>

            <reference_profile>voice notes</reference_profile>

            <selection>
            The selection.
            </selection>
            """
        )
    }

    func testReferenceDeepeningInputIsThePrimaryTextVerbatim() {
        let input = AIRequestBuilder.input(
            for: .referenceDeepening,
            primaryText: "Raw reference excerpt.",
            styleGuide: "ignored",
            referenceContext: "ignored"
        )
        XCTAssertEqual(input, "Raw reference excerpt.")
    }

    func testRewriteAlternativeIDCombinesTextAndExplanation() {
        let alternative = RewriteAlternative(text: "New text.", explanation: "Tighter phrasing.", gradeEstimate: 7.5)
        XCTAssertEqual(alternative.id, "New text.|Tighter phrasing.")
    }

    func testSelectionRewritePresentationCarriesTheGoalRangeTextAndAlternatives() {
        let goal = SelectionRewriteGoal(kind: .shorten)
        let alternatives = [RewriteAlternative(text: "Shorter.", explanation: "Cut filler.", gradeEstimate: 6)]
        let presentation = SelectionRewritePresentation(
            goal: goal,
            sourceRange: NSRange(location: 4, length: 10),
            sourceText: "Original passage.",
            alternatives: alternatives
        )
        XCTAssertEqual(presentation.goal, goal)
        XCTAssertEqual(presentation.sourceRange, NSRange(location: 4, length: 10))
        XCTAssertEqual(presentation.sourceText, "Original passage.")
        XCTAssertEqual(presentation.alternatives.map(\.id), alternatives.map(\.id))
    }
}
