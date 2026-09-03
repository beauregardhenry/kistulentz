import Foundation
import XCTest
@testable import Kistulentz

/// Covers the project-local advisory learning added on top of `ProjectStyleManager`: declining the
/// same advisory rule (a fixed category + message, not one specific sentence) often enough in a
/// project should stop that rule from being flagged again in that project, everywhere the local
/// engine's issues reach the author — live highlighting and Local Polish alike.
final class ProjectStyleLearningTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDown() {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    // MARK: - suppressedAdvisoryPatterns

    func testPatternIsSuppressedOnceDeclineCountReachesTheThreshold() {
        let decisions = [
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "This might, perhaps work."),
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "This could, maybe help.")
        ]

        let suppressed = ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions)

        XCTAssertTrue(suppressed.contains(AdvisoryPattern(category: .aiTell, message: "Stacked hedges.")))
    }

    func testASingleDeclineDoesNotYetSuppressThePattern() {
        let decisions = [
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "This might, perhaps work.")
        ]

        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions).isEmpty)
    }

    func testDeclineCountsForTheSamePatternAccumulateAcrossDifferentExcerpts() {
        // Each decline of an advisory issue creates its own decision (different sentence text), so
        // suppression has to sum counts across entries that share a category+message, not rely on
        // a single entry's own count.
        let decisions = [
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "Sentence one."),
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "Sentence two.")
        ]

        XCTAssertEqual(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions).count, 1)
    }

    func testDifferentAdvisoryRulesAreLearnedIndependently() {
        // Two declines of "overused actually" must never silence an unrelated "stock opener" rule
        // the author never objected to, even though both live under the same .aiTell category.
        let decisions = [
            declinedAdvisory(category: .aiTell, message: "Overused actually.", excerpt: "actually"),
            declinedAdvisory(category: .aiTell, message: "Overused actually.", excerpt: "actually")
        ]

        let suppressed = ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions)

        XCTAssertTrue(suppressed.contains(AdvisoryPattern(category: .aiTell, message: "Overused actually.")))
        XCTAssertFalse(suppressed.contains(AdvisoryPattern(category: .aiTell, message: "Stock opener.")))
    }

    func testAcceptedDecisionsNeverContributeToSuppression() {
        let decisions = [
            ProjectStyleDecision(
                action: .accepted,
                category: .aiTell,
                excerpt: "Sentence one.",
                replacement: nil,
                count: 5,
                lastUsedAt: Date(),
                message: "Stacked hedges."
            )
        ]

        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions).isEmpty)
    }

    func testDeclinedReplacementIssuesNeverContributeToAdvisorySuppression() {
        // Replacement issues already have their own excerpt-exact learning; they must not also
        // feed the coarser advisory-pattern suppression, however many times they're declined.
        let decisions = [
            ProjectStyleDecision(
                action: .declined,
                category: .complexPhrase,
                excerpt: "utilize",
                replacement: "use",
                count: 10,
                lastUsedAt: Date(),
                message: "Use a simpler alternative."
            )
        ]

        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions).isEmpty)
    }

    func testDecisionsWithNoStoredMessagePredateLearningAndAreIgnored() {
        // Archives written before this feature shipped have no `message`. They must not crash or
        // silently count toward a made-up empty-string pattern.
        let decisions = [
            ProjectStyleDecision(
                action: .declined,
                category: .aiTell,
                excerpt: "Sentence one.",
                replacement: nil,
                count: 5,
                lastUsedAt: Date()
            )
        ]

        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions).isEmpty)
    }

    // MARK: - filteringLearnedSuppressions

    func testFilteringRemovesOnlyIssuesMatchingASuppressedPattern() {
        let decisions = [
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "a"),
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "b")
        ]
        let suppressedIssue = advisoryIssue(category: .aiTell, message: "Stacked hedges.")
        let unrelatedIssue = advisoryIssue(category: .aiTell, message: "Stock opener.")

        let filtered = ProjectStyleManager.filteringLearnedSuppressions(
            [suppressedIssue, unrelatedIssue],
            decisions: decisions
        )

        XCTAssertEqual(filtered, [unrelatedIssue])
    }

    func testFilteringLeavesConcreteReplacementIssuesAloneEvenIfDeclinedRepeatedly() {
        let decisions = [
            ProjectStyleDecision(
                action: .declined,
                category: .complexPhrase,
                excerpt: "utilize",
                replacement: "use",
                count: 10,
                lastUsedAt: Date(),
                message: "Use a simpler alternative."
            )
        ]
        let issue = WritingIssue(
            category: .complexPhrase,
            range: NSRange(location: 0, length: 7),
            excerpt: "utilize",
            message: "Use a simpler alternative.",
            replacement: "use"
        )

        let filtered = ProjectStyleManager.filteringLearnedSuppressions([issue], decisions: decisions)

        XCTAssertEqual(filtered, [issue])
    }

    func testFilteringLeavesSystemAndAISourcedIssuesAloneEvenOnACategoryMessageMatch() {
        let decisions = [
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "a"),
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "b")
        ]
        let systemIssue = advisoryIssue(category: .aiTell, message: "Stacked hedges.", source: .system)
        let aiIssue = advisoryIssue(category: .aiTell, message: "Stacked hedges.", source: .ai)

        let filtered = ProjectStyleManager.filteringLearnedSuppressions(
            [systemIssue, aiIssue],
            decisions: decisions
        )

        XCTAssertEqual(filtered, [systemIssue, aiIssue])
    }

    func testFilteringIsANoOpWithNoDecisions() {
        let issue = advisoryIssue(category: .aiTell, message: "Stacked hedges.")
        XCTAssertEqual(ProjectStyleManager.filteringLearnedSuppressions([issue], decisions: []), [issue])
    }

    // MARK: - End-to-end through the on-disk decision archive

    func testDecliningTheSameAdvisoryRuleTwiceSuppressesItProjectWide() throws {
        let root = try makeTemporaryProject()

        try ProjectStyleManager.record(
            action: .declined,
            issue: advisoryIssue(category: .aiTell, message: "Stacked hedges.", excerpt: "First flagged sentence."),
            at: root
        )
        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: try ProjectStyleManager.loadDecisions(at: root)).isEmpty)
        XCTAssertFalse(try ProjectStyleManager.loadStyle(at: root).contains("No longer flagged in this project"))

        try ProjectStyleManager.record(
            action: .declined,
            issue: advisoryIssue(category: .aiTell, message: "Stacked hedges.", excerpt: "Second flagged sentence."),
            at: root
        )
        let decisions = try ProjectStyleManager.loadDecisions(at: root)
        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions)
            .contains(AdvisoryPattern(category: .aiTell, message: "Stacked hedges.")))

        let style = try ProjectStyleManager.loadStyle(at: root)
        XCTAssertTrue(style.contains("No longer flagged in this project"))
        XCTAssertTrue(style.contains("Stacked hedges."))
    }

    func testClearingLearnedPreferencesLiftsSuppression() throws {
        let root = try makeTemporaryProject()
        try ProjectStyleManager.record(
            action: .declined,
            issue: advisoryIssue(category: .aiTell, message: "Stacked hedges.", excerpt: "First."),
            at: root
        )
        try ProjectStyleManager.record(
            action: .declined,
            issue: advisoryIssue(category: .aiTell, message: "Stacked hedges.", excerpt: "Second."),
            at: root
        )
        XCTAssertFalse(try ProjectStyleManager.loadDecisions(at: root).isEmpty)

        try ProjectStyleManager.clearLearnedPreferences(at: root)

        XCTAssertTrue(try ProjectStyleManager.loadDecisions(at: root).isEmpty)
        XCTAssertFalse(try ProjectStyleManager.loadStyle(at: root).contains("No longer flagged in this project"))
    }

    func testArchivesWrittenBeforeThisFeatureStillDecode() throws {
        let root = try makeTemporaryProject()
        // Simulates a style-decisions.json saved by an older build, with no "message" key at all.
        let legacyJSON = """
        {
          "decisions": [
            {
              "action": "declined",
              "category": "aiTell",
              "excerpt": "Some earlier sentence.",
              "count": 3,
              "lastUsedAt": "2026-01-01T00:00:00Z"
            }
          ]
        }
        """
        let metadataURL = WritingProjectDisk.metadataURL(at: root)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try legacyJSON.write(
            to: metadataURL.appendingPathComponent("style-decisions.json"),
            atomically: true,
            encoding: .utf8
        )

        let decisions = try ProjectStyleManager.loadDecisions(at: root)

        XCTAssertEqual(decisions.count, 1)
        XCTAssertNil(decisions[0].message)
        XCTAssertTrue(ProjectStyleManager.suppressedAdvisoryPatterns(in: decisions).isEmpty)
    }

    // MARK: - LocalPolishService integration

    func testLocalPolishAdvisoryCountDropsOnceAPatternIsLearnedSuppressed() {
        let text = "This might, perhaps, possibly work out fine."
        let issue = advisoryIssue(
            category: .aiTell,
            message: "Stacked hedges.",
            excerpt: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )

        let beforeLearning = LocalPolishService.polish(
            text: text,
            targetGrade: 8,
            issues: [issue],
            styleDecisions: []
        )
        XCTAssertEqual(beforeLearning.advisoryCount, 1)

        let learnedDeclines = [
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "Other sentence one."),
            declinedAdvisory(category: .aiTell, message: "Stacked hedges.", excerpt: "Other sentence two.")
        ]
        let afterLearning = LocalPolishService.polish(
            text: text,
            targetGrade: 8,
            issues: [issue],
            styleDecisions: learnedDeclines
        )
        XCTAssertEqual(afterLearning.advisoryCount, 0)
    }

    // MARK: - Helpers

    private func declinedAdvisory(category: IssueCategory, message: String, excerpt: String) -> ProjectStyleDecision {
        ProjectStyleDecision(
            action: .declined,
            category: category,
            excerpt: excerpt,
            replacement: nil,
            count: 1,
            lastUsedAt: Date(),
            message: message
        )
    }

    private func advisoryIssue(
        category: IssueCategory,
        message: String,
        excerpt: String = "flagged text",
        range: NSRange = NSRange(location: 0, length: 12),
        source: IssueSource = .local
    ) -> WritingIssue {
        WritingIssue(
            category: category,
            range: range,
            excerpt: excerpt,
            message: message,
            replacement: nil,
            source: source
        )
    }

    private func makeTemporaryProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ProjectStyleLearningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        try ProjectStyleManager.prepare(at: root, projectName: "Test Project", kind: .fiction)
        return root
    }
}
