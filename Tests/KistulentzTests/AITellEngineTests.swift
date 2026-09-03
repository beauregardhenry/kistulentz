import XCTest
@testable import Kistulentz

final class AITellEngineTests: XCTestCase {
    func testFlagsCorrelativeConstruction() {
        let issues = AITellEngine.analyze(
            "The garden isn't just a hobby, it's a way of slowing down after work."
        )

        let match = issues.first { $0.category == .aiTell }
        XCTAssertNotNil(match)
        XCTAssertNil(match?.replacement, "AI-tell issues should always be advisory, never auto-applied.")
    }

    func testFlagsNotAboutConstruction() {
        let issues = AITellEngine.analyze(
            "It's not about winning the argument, it's about being understood."
        )

        XCTAssertTrue(issues.contains { $0.category == .aiTell })
    }

    func testDoesNotConfusePossessiveItsWithCorrelativeConstruction() {
        // The second clause requires "it's" (a genuine contraction), not the bare possessive
        // "its" — otherwise this check would misfire on any ordinary sentence shaped like
        // "wasn't just X, its Y ...". This is a different, unrelated sentence, not the AI tell.
        let issues = AITellEngine.analyze(
            "The old house wasn't just falling apart, its foundation had cracked in three places."
        )

        XCTAssertFalse(issues.contains { $0.category == .aiTell })
    }

    func testDoesNotFlagOrdinaryPossessiveIts() {
        let issues = AITellEngine.analyze(
            "The cabin sat near the lake, its windows dark against the tree line."
        )

        XCTAssertTrue(issues.isEmpty, "A plain possessive \"its\" with no negation should never trigger a correlative match.")
    }

    func testFlagsStockWindUpPhrases() {
        let issues = AITellEngine.analyze(
            "Here's the thing: nobody actually reads the manual before assembling the shelf."
        )

        XCTAssertTrue(issues.contains { $0.category == .aiTell && $0.excerpt.lowercased() == "here's the thing" })
    }

    func testFlagsStockOpenerAtStartOfLine() {
        let issues = AITellEngine.analyze(
            "In today's fast-paced world, nobody has time to read the instructions."
        )

        XCTAssertTrue(issues.contains { $0.category == .aiTell })
    }

    func testDoesNotFlagStockOpenerPhraseMidSentence() {
        // The opener check is anchored to the start of a line; the same words appearing
        // mid-sentence describe an actual claim rather than a formulaic AI lead-in.
        let issues = AITellEngine.analyze(
            "She grew up believing, as her grandmother put it, in an era where kindness mattered more than cleverness."
        )

        XCTAssertFalse(issues.contains { $0.category == .aiTell })
    }

    func testFlagsStaccatoMarketingTriad() {
        let issues = AITellEngine.analyze("No fluff. No filler. Just results.")

        XCTAssertTrue(issues.contains { $0.category == .aiTell })
    }

    func testDoesNotFlagShortFictionDialogueAsStaccato() {
        // Short fragments are ordinary in dialogue and action beats. Only the specific
        // "No X. No Y. Just/Only Z." marketing rhythm should trigger, not fragments generally.
        let issues = AITellEngine.analyze("\"Stop.\" \"Wait.\" \"Listen to me.\"")

        XCTAssertTrue(issues.isEmpty)
    }

    func testFlagsStackedHedgeWordsInOneSentence() {
        let issues = AITellEngine.analyze(
            "This might perhaps possibly be the reason attendance dropped last spring."
        )

        XCTAssertTrue(issues.contains { $0.category == .aiTell })
    }

    func testDoesNotFlagASingleHedgeWord() {
        let issues = AITellEngine.analyze(
            "This might be the reason attendance dropped last spring."
        )

        XCTAssertTrue(issues.isEmpty, "One hedge word is an honest expression of uncertainty, not a stacked-hedge tell.")
    }

    func testFlagsRepeatedFillerJustWithinAParagraph() {
        let text = "We just need to focus on the work. It just takes patience and a clear head."
        let issues = AITellEngine.analyze(text)

        let justIssues = issues.filter { $0.category == .aiTell && $0.excerpt.lowercased() == "just" }
        XCTAssertEqual(justIssues.count, 1, "Only the second and later 'just' in a paragraph should be flagged, not the first.")
    }

    func testDoesNotFlagExemptedUsesOfJust() {
        let text = "I just started this project. Just in case, I kept the old draft too."
        let issues = AITellEngine.analyze(text)

        XCTAssertTrue(issues.isEmpty, "Idiomatic uses of 'just' (just started, just in case) should never count toward the filler tally.")
    }

    func testFlagsActuallyWhenOverusedForPassageLength() {
        let text = Array(repeating: "This is a short sentence about the weather today.", count: 20)
            .joined(separator: " ")
            + " It's actually going to rain. It's actually quite cold too."

        let issues = AITellEngine.analyze(text)

        XCTAssertTrue(issues.contains { $0.category == .aiTell && $0.excerpt.lowercased() == "actually" })
    }

    func testDoesNotFlagASingleActuallyInAShortPassage() {
        let issues = AITellEngine.analyze(
            "I thought the meeting was cancelled, but it's actually still happening at three."
        )

        XCTAssertTrue(issues.isEmpty)
    }

    func testEveryAITellIssueIsAdvisoryOnly() {
        let text = """
        Here's the thing: this feature isn't just useful, it's essential. \
        At the end of the day, it might perhaps possibly change how the team works.
        """
        let issues = AITellEngine.analyze(text)

        XCTAssertFalse(issues.isEmpty)
        XCTAssertTrue(issues.allSatisfy { $0.replacement == nil && $0.category == .aiTell })
    }

    func testReadabilityEngineSurfacesAITellIssues() {
        // AITellEngine is wired into ReadabilityEngine.analyze, which is what the live editor,
        // whole-project polish, and the AI-rewrite safety check all actually call.
        let result = ReadabilityEngine.analyze(
            "Here's the thing: our approach isn't just different, it's better.",
            targetGrade: 8
        )

        XCTAssertTrue(result.issues.contains { $0.category == .aiTell })
    }

    func testOrdinaryProseProducesNoAITellIssues() {
        let issues = AITellEngine.analyze(
            "Maria closed the shop early and walked home along the river, watching the last light fade over the water."
        )

        XCTAssertTrue(issues.isEmpty)
    }
}
