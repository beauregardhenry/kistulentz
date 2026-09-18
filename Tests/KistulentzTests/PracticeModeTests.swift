import XCTest
@testable import Kistulentz

/// Tests for `AppSettings.isPracticeModeEnabled` and `IssueCategory.practicePrompt` -- the two
/// pieces of pure logic behind Practice Mode. The UI-side gating in `EditorSidebars.swift`
/// (`IssueCard`/`ReviewSidebar` withholding Accept/Rewrite/Apply All) and the toolbar's disabled
/// `Polish` button aren't covered here, matching this suite's existing precedent of not driving
/// SwiftUI view bodies directly (see `EditorPreferencesTests.swift`'s header comment) -- both
/// read straight from `practicePrompt`, which is what's actually under test.
final class PracticeModeTests: XCTestCase {
    @MainActor
    func testPracticeModeDefaultsToOff() throws {
        let suite = "PracticeModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.isPracticeModeEnabled)
    }

    @MainActor
    func testPracticeModePersistsAcrossReopen() throws {
        let suite = "PracticeModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.isPracticeModeEnabled = true

        let reopened = AppSettings(defaults: defaults)
        XCTAssertTrue(reopened.isPracticeModeEnabled)
    }

    /// Every category with a craft judgment behind it -- something a writer's own revision skill
    /// applies, not a fact to check -- has a practice prompt. This is the exact set Practice Mode
    /// withholds a fix for.
    func testCraftJudgmentCategoriesHavePracticePrompts() {
        let craftJudgmentCategories: [IssueCategory] = [
            .hardSentence, .veryHardSentence, .adverb, .passiveVoice,
            .structuralComplexity, .complexPhrase, .aiTell, .referenceVoice, .avoidedWord
        ]

        for category in craftJudgmentCategories {
            XCTAssertNotNil(
                category.practicePrompt,
                "\(category) is a craft judgment and should have a practice prompt"
            )
            XCTAssertFalse(
                category.practicePrompt?.isEmpty ?? true,
                "\(category)'s practice prompt should not be blank"
            )
        }
    }

    /// Spelling, grammar, continuity, and an already-reviewed AI suggestion aren't craft
    /// judgments -- they're objective corrections or a fact-check, and withholding them would add
    /// friction without teaching anything. Practice Mode leaves these fixable either way.
    func testObjectiveCategoriesHaveNoPracticePrompt() {
        let objectiveCategories: [IssueCategory] = [.spelling, .grammar, .continuity, .aiSuggestion]

        for category in objectiveCategories {
            XCTAssertNil(
                category.practicePrompt,
                "\(category) is not a craft judgment and should have no practice prompt"
            )
        }
    }

    /// Every case is covered by exactly one of the two assertions above -- if a new
    /// `IssueCategory` case is ever added, one of these two tests should start failing rather than
    /// silently leaving it unclassified.
    func testEveryIssueCategoryIsClassified() {
        let craftJudgmentCategories: Set<IssueCategory> = [
            .hardSentence, .veryHardSentence, .adverb, .passiveVoice,
            .structuralComplexity, .complexPhrase, .aiTell, .referenceVoice, .avoidedWord
        ]
        let objectiveCategories: Set<IssueCategory> = [.spelling, .grammar, .continuity, .aiSuggestion]

        XCTAssertEqual(
            craftJudgmentCategories.union(objectiveCategories),
            Set(IssueCategory.allCases)
        )
        XCTAssertTrue(craftJudgmentCategories.isDisjoint(with: objectiveCategories))
    }
}
