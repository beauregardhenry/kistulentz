import Foundation
import XCTest
@testable import Kistulentz

/// Covers the "words to avoid" feature end to end on the model/service layer:
/// `ProjectStyleManager.avoidedWords` parsing the project's own "### Words to avoid" bullet list
/// out of Kistulentz Style.md, and `ReadabilityEngine` flagging occurrences of those words
/// locally -- no AI, no network -- the same way it already flags adverbs or passive voice. Before
/// this, everything under the style guide's freeform sections (including its own "words to
/// avoid" mention) was read only by optional AI-backed editing; this is the one part of the file
/// that now genuinely feeds the local, offline checks.
final class AvoidedWordsTests: XCTestCase {
    // MARK: - ProjectStyleManager.avoidedWords

    func testParsesBulletedWordsUnderTheHeading() {
        let styleText = """
        ## Vocabulary and mechanics

        ### Words to avoid

        - utilize
        - very
        - moist
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), ["utilize", "very", "moist"])
    }

    func testAcceptsAsteriskAndBulletMarkersToo() {
        let styleText = """
        ### Words to avoid

        * utilize
        • moist
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), ["utilize", "moist"])
    }

    func testIgnoresTheTemplatesOwnInstructionalProseUnderTheHeading() {
        // The template puts a plain (non-bulleted) instructional sentence directly under this
        // heading -- it must never itself be parsed as a word to avoid.
        let styleText = """
        ### Words to avoid

        List each word or short phrase as its own bullet below. Kistulentz's local checks will flag any of them while you write, the same way it already flags adverbs or passive voice.

        - utilize
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), ["utilize"])
    }

    func testStopsAtTheNextHeading() {
        let styleText = """
        ### Words to avoid

        - utilize

        ## Project rules

        - Avoid the passive voice.
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), ["utilize"])
    }

    func testDeduplicatesCaseInsensitivelyKeepingTheFirstSpelling() {
        let styleText = """
        ### Words to avoid

        - Utilize
        - utilize
        - UTILIZE
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), ["Utilize"])
    }

    func testReturnsEmptyWhenTheHeadingIsAbsent() {
        let styleText = """
        ## Vocabulary and mechanics

        Record preferred spellings, capitalization, punctuation, terminology, and words to avoid.
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), [])
    }

    func testReturnsEmptyWhenTheHeadingHasNoBullets() {
        let styleText = """
        ### Words to avoid

        Nothing added yet.
        """

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), [])
    }

    func testFreshlyPreparedProjectsStyleGuideParsesToNoAvoidedWordsYet() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ProjectStyleManager.prepare(at: root, projectName: "Test Project", kind: .fiction)
        let styleText = try ProjectStyleManager.loadStyle(at: root)

        XCTAssertEqual(ProjectStyleManager.avoidedWords(from: styleText), [])
    }

    // MARK: - ReadabilityEngine local detection

    func testAnalyzeFlagsAnAvoidedWordCaseInsensitively() {
        let result = ReadabilityEngine.analyze(
            "She would Utilize the tool tomorrow.",
            targetGrade: 8,
            avoidedWords: ["utilize"]
        )

        let issue = result.issues.first { $0.category == .avoidedWord }
        XCTAssertEqual(issue?.excerpt, "Utilize")
        XCTAssertNil(issue?.replacement)
        XCTAssertEqual(issue?.source, .local)
    }

    func testAnalyzeOnlyMatchesWholeWordsNotSubstrings() {
        let result = ReadabilityEngine.analyze(
            "The utilization report is ready.",
            targetGrade: 8,
            avoidedWords: ["utilize"]
        )

        XCTAssertFalse(result.issues.contains { $0.category == .avoidedWord })
    }

    func testAnalyzeFlagsEveryOccurrenceOfEveryAvoidedWord() {
        let result = ReadabilityEngine.analyze(
            "She would utilize the tool. He would also utilize a second tool, which felt moist.",
            targetGrade: 8,
            avoidedWords: ["utilize", "moist"]
        )

        let avoided = result.issues.filter { $0.category == .avoidedWord }
        XCTAssertEqual(avoided.count, 3)
    }

    func testAnalyzeProducesNoAvoidedWordIssuesWhenTheListIsEmpty() {
        let result = ReadabilityEngine.analyze("She would utilize the tool.", targetGrade: 8)

        XCTAssertFalse(result.issues.contains { $0.category == .avoidedWord })
    }

    // MARK: - EditorViewModel wiring

    @MainActor
    func testUpdateAvoidedWordsTakesEffectOnTheNextAnalysisPass() async {
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in nil })
        viewModel.updateAvoidedWords(["utilize"])

        viewModel.scheduleAnalysis(text: "Please utilize the form.", targetGrade: 8, immediately: true)
        await waitUntil { viewModel.analysis.issues.contains { $0.category == .avoidedWord } }

        XCTAssertTrue(viewModel.visibleLocalIssues.contains { $0.category == .avoidedWord })
    }

    @MainActor
    func testAvoidedWordSurvivesTheBeneparMergeWhenStructuralAnalysisSucceeds() async {
        let profile = StructuralProfile(
            sentencesAnalyzed: 4, sentencesAvailable: 4, averageTreeDepth: 5, maximumTreeDepth: 7,
            averageClausesPerSentence: 1.8, subordinateSentenceRatio: 0.25, averageLongestNounPhraseWords: 3.2,
            longNounPhraseRatio: 0.12, coordinationRatio: 0.08, passiveCandidateRatio: 0.04, fragmentRatio: 0
        )
        let viewModel = EditorViewModel(structuralAnalyzer: { _, _, _, _ in
            BeneparAnalysis(metrics: profile, issues: [])
        })
        viewModel.updateAvoidedWords(["utilize"])

        viewModel.scheduleAnalysis(text: "Please utilize the form.", targetGrade: 8, immediately: true)
        await waitUntil { viewModel.isUsingBenepar }

        XCTAssertTrue(
            viewModel.analysis.issues.contains { $0.category == .avoidedWord },
            "avoidedWord issue did not survive BeneparAnalysisMerger.merge; issues: \(viewModel.analysis.issues.map(\.category))"
        )
    }

    @MainActor
    private func waitUntil(
        timeoutIterations: Int = 200,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for avoided-word analysis to complete")
    }
}
