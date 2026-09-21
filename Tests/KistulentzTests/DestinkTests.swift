import Foundation
import XCTest
@testable import Kistulentz

final class DestinkTests: XCTestCase {
    func testLexicalFindingsAreLocatedInOriginalText() throws {
        let text = "The robust platform offers actionable insights. In conclusion, it will define the next era."

        let findings = DestinkEngine.analyze(text)

        XCTAssertTrue(findings.contains { $0.ruleID == "lex-delve-family" && $0.excerpt == "robust" })
        XCTAssertTrue(findings.contains { $0.ruleID == "corporate-jargon" && $0.excerpt == "actionable insights" })
        XCTAssertTrue(findings.contains { $0.ruleID == "lex-signposts" && $0.excerpt == "In conclusion" })
        for finding in findings {
            XCTAssertEqual(
                (text as NSString).substring(with: finding.range).trimmingCharacters(in: .whitespacesAndNewlines),
                finding.excerpt
            )
        }
    }

    func testPhraseListAdditionsPortedFromUpstreamFire() {
        let text = """
        This is production-ready. TLDR: it's fine. Worth sitting with for a moment.
        This matters because of the migration, and honestly it matters because of billing too.
        Most people won't read this far, but paper cuts add up, modulo the edge cases.
        She kept comprehending and emulating the design, exceptionally so, necessitating a pronounced shift.
        """

        let findings = DestinkEngine.analyze(text)
        let idsByExcerpt = Dictionary(grouping: findings, by: { $0.excerpt.lowercased() }).mapValues { $0.map(\.ruleID) }

        XCTAssertTrue(idsByExcerpt["production-ready"]?.contains("claude-assistant-voice") == true)
        XCTAssertTrue(idsByExcerpt["tldr"]?.contains("claude-discourse-markers") == true)
        XCTAssertTrue(idsByExcerpt["worth sitting with"]?.contains("claude-discourse-markers") == true)
        XCTAssertTrue(idsByExcerpt["matters because"]?.contains("claude-stock-frames") == true)
        XCTAssertTrue(idsByExcerpt["most people won't read this far"]?.contains("claude-stock-frames") == true)
        XCTAssertTrue(idsByExcerpt["paper cuts"]?.contains("claude-technical-vocabulary") == true)
        XCTAssertTrue(idsByExcerpt["modulo"]?.contains("claude-technical-vocabulary") == true)
        XCTAssertTrue(idsByExcerpt["comprehending"]?.contains("excess-vocabulary") == true)
        XCTAssertTrue(idsByExcerpt["emulating"]?.contains("excess-vocabulary") == true)
        XCTAssertTrue(idsByExcerpt["exceptionally"]?.contains("excess-vocabulary") == true)
        XCTAssertTrue(idsByExcerpt["necessitating"]?.contains("excess-vocabulary") == true)
        XCTAssertTrue(idsByExcerpt["pronounced"]?.contains("excess-vocabulary") == true)
    }

    func testFictionFrameCompletionPhrasesFire() {
        let text = "She let out a breath she didn't know she was holding, then straightened."

        let findings = DestinkEngine.analyze(text).filter { $0.ruleID == "claude-fiction-frames" }

        XCTAssertTrue(findings.contains { $0.excerpt.lowercased() == "didn't know she was holding" })
    }

    func testFictionGestureClusterStaysCandidateBelowDensityAndEscalatesAtDensity() {
        let single = "He blinked once, then looked away."
        let dense = "He blinked. She glanced away. He murmured something. She tilted her head. His hands trembled. The room fell into stillness."

        let singleFindings = DestinkEngine.analyze(single).filter { $0.ruleID == "claude-fiction-gestures" }
        XCTAssertEqual(singleFindings.map(\.severity), [.candidate])

        let denseFindings = DestinkEngine.analyze(dense).filter { $0.ruleID == "claude-fiction-gestures" }
        XCTAssertGreaterThanOrEqual(denseFindings.count, 5)
        XCTAssertTrue(denseFindings.allSatisfy { $0.severity == .low })
    }

    func testMarkdownCodeAndLinkTargetsDoNotBecomeProseFindings() {
        let text = "Use `robust` as a fixture. [Ordinary link](https://example.com/robust).\n\nThe robust claim remains."

        let findings = DestinkEngine.analyze(text).filter { $0.ruleID == "lex-delve-family" }

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.excerpt, "robust")
        XCTAssertEqual(findings.first?.range.location, (text as NSString).range(of: "The robust").location + 4)
    }

    func testCodeFenceKeepsNewlinesAndUTF16OffsetsStable() {
        let text = "Before 😀.\n```swift\nlet robust = true\n```\nAfter robust."

        let prose = DestinkEngine.markdownProse(text)
        let findings = DestinkEngine.analyze(text).filter { $0.ruleID == "lex-delve-family" }

        XCTAssertEqual((prose as NSString).length, (text as NSString).length)
        XCTAssertEqual(prose.filter { $0 == "\n" }.count, text.filter { $0 == "\n" }.count)
        XCTAssertEqual(findings.map(\.excerpt), ["robust"])
        XCTAssertEqual(findings.first?.range, (text as NSString).range(of: "robust", options: .backwards))
    }

    func testStructuralSurfaceRulesFindReframeQuestionAndIngTackOn() {
        let text = "It is not a feature. It is a trap. The result? Devastating. The release landed, demonstrating its importance."

        let ids = Set(DestinkEngine.analyze(text).map(\.ruleID))

        XCTAssertTrue(ids.contains("reframe"))
        XCTAssertTrue(ids.contains("syntactic/self-posed-question"))
        XCTAssertTrue(ids.contains("ing-tackon"))
    }

    func testReviewReusesAlwaysOnAITellChecksWithoutDuplicateSpans() {
        let text = "Let's be honest: this garden isn't just a hobby, it's a way to slow down."

        let findings = DestinkEngine.analyze(text)

        XCTAssertTrue(findings.contains { $0.ruleID == "native/ai-tell" && $0.excerpt.lowercased() == "let's be honest" })
        let correlativeRange = (text as NSString).range(of: "isn't just")
        XCTAssertEqual(findings.filter { NSIntersectionRange($0.range, correlativeRange).length > 0 }.count, 1)
    }

    func testRepeatedShortFragmentsProduceOneDiscourseFinding() {
        let text = "She published the claim. No caveat. No source. No proof."

        let findings = DestinkEngine.analyze(text)

        XCTAssertEqual(findings.filter { $0.ruleID == "discourse/punchy-fragments" }.count, 1)
        XCTAssertEqual(findings.filter { $0.ruleID == "discourse/countdown" }.count, 1)
    }

    func testStaccatoRegisterRequiresDocumentLevelDensity() {
        let text = "This works.\n\nThat failed.\n\nWe moved.\n\nThey stayed.\n\nIt ended.\n\nNothing changed."

        XCTAssertTrue(DestinkEngine.analyze(text).contains { $0.ruleID == "discourse/staccato-register" })
        XCTAssertFalse(DestinkEngine.analyze("This works. That failed, because the input changed; we fixed it together.")
            .contains { $0.ruleID == "discourse/staccato-register" })
    }

    func testScoreUsesSeverityWeightsPerThousandWithShortTextFloor() {
        let text = "A short document."
        let source = text as NSString
        let findings = [
            DestinkFinding(
                ruleID: "low", tier: .lexical, severity: .low,
                range: source.range(of: "short"), excerpt: "short", message: "Low", explanation: ""
            ),
            DestinkFinding(
                ruleID: "high", tier: .syntactic, severity: .high,
                range: source.range(of: "document"), excerpt: "document", message: "High", explanation: ""
            )
        ]
        let document = DestinkDocumentReport(
            relativePath: "test.md", title: "Test", wordCount: 3, findings: findings, usedBenepar: false
        )
        let report = DestinkReport(documents: [document])

        XCTAssertEqual(report.score, 50, accuracy: 0.001)
        XCTAssertEqual(report.score(for: .lexical), 10, accuracy: 0.001)
        XCTAssertEqual(report.score(for: .syntactic), 40, accuracy: 0.001)
    }

    func testBeneparFindingDecodesUTF16RangeAndMergesWithoutDuplicateRuleSpan() throws {
        let text = "😀 The release serves as a warning."
        let range = (text as NSString).range(of: "serves as")
        let worker = BeneparWorkerDestinkFinding(
            ruleId: "serves-as-dodge",
            tier: "syntactic",
            severity: "medium",
            location: range.location,
            length: range.length,
            excerpt: "serves as",
            message: "Parsed",
            explanation: "Tree-backed"
        )
        let parsed = try XCTUnwrap(worker.finding(in: text))
        let local = DestinkEngine.analyze(text)

        XCTAssertEqual(parsed.range, range)
        XCTAssertTrue(parsed.usedBenepar)
        XCTAssertEqual(
            DestinkEngine.merge(local: local, benepar: [parsed]).filter { $0.ruleID == "serves-as-dodge" }.count,
            1
        )
    }

    func testWorkerFindingRejectsUnknownContractValuesAndInvalidRanges() {
        let text = "Text"
        XCTAssertNil(BeneparWorkerDestinkFinding(
            ruleId: "x", tier: "unknown", severity: "low", location: 0, length: 4,
            excerpt: "Text", message: "", explanation: ""
        ).finding(in: text))
        XCTAssertNil(BeneparWorkerDestinkFinding(
            ruleId: "x", tier: "lexical", severity: "high", location: 9, length: 2,
            excerpt: "", message: "", explanation: ""
        ).finding(in: text))
    }
}
