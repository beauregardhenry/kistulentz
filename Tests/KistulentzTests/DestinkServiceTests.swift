import Foundation
import XCTest
@testable import Kistulentz

/// Direct tests for `DestinkService.analyze` -- the async orchestration layer around
/// `DestinkEngine`/`BeneparService` that fans a de-stink pass out across every document in a
/// manuscript. `DestinkTests.swift` covers `DestinkEngine`'s pure rule logic in isolation and never
/// calls `DestinkService.analyze` itself, so none of the orchestration decisions this file checks
/// (one report per document in input order, per-document `wordCount`/`usedBenepar` wiring, graceful
/// fallback when the Benepar language pack is unavailable, empty/blank-document edge cases) had any
/// direct coverage before this.
///
/// `BeneparService` is a concrete actor, not a protocol, and `BeneparLanguagePackLocator.locate`
/// only succeeds against a real installed language pack (a real Python runtime and model directory
/// on disk) -- there is no seam to inject a fake. `unavailableBenepar()` below points a fresh
/// `BeneparService` at a directory with no `manifest.json`, which deterministically makes
/// `destinkIfAvailable` return nil (see `BeneparLanguagePackLocator.locate` and
/// `BeneparService.destinkIfAvailable`'s catch block) regardless of whether the machine running the
/// tests happens to have a real pack installed. That gives solid, deterministic coverage of the
/// "asked for Benepar, but it wasn't available" fallback path -- the path every CI run and most
/// contributors' machines will actually take. Two things are consequently NOT covered here, and
/// can't be without either a real installed language pack or an injectable seam added to
/// `DestinkService`/`BeneparService`: the `parsedSentencesPerDocument` budget math (`max(1, 400 /
/// max(documents.count, 1))`) is a local variable never surfaced to a caller, and the `usedBenepar
/// == true` success path requires Benepar to actually answer. A mid-run `Task.isCancelled` early
/// break is also left untested: with `useBenepar: false` the loop body has no `await` suspension
/// point, so whether a freshly created `Task { ... }` begins running eagerly or gets enqueued before
/// `cancel()` runs is a real Swift-concurrency-runtime detail this file can't verify by hand without
/// a compiler, and guessing at it risks shipping exactly the kind of flaky test this pass is meant
/// to avoid.
final class DestinkServiceTests: XCTestCase {
    // MARK: - Fixtures

    private func makeDocument(
        relativePath: String = "chapter.md",
        title: String = "Chapter",
        text: String
    ) -> ManuscriptDocument {
        ManuscriptDocument(relativePath: relativePath, title: title, text: text)
    }

    /// A `BeneparService` rooted at a directory with no `manifest.json`, so `destinkIfAvailable`
    /// always resolves to nil -- deterministically, regardless of the host machine's own state. The
    /// directory need not exist: `BeneparLanguagePackLocator.locate` only checks
    /// `FileManager.fileExists` for `manifest.json` under it, which is false either way.
    private func unavailableBenepar() -> BeneparService {
        BeneparService(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("kistulentz-test-no-benepar-\(UUID().uuidString)", isDirectory: true))
    }

    private func ruleIDs(_ findings: [DestinkFinding]) -> [String] {
        findings.map(\.ruleID)
    }

    // MARK: - Tests

    func testAnalyzeReturnsOneReportPerDocumentInInputOrderWithoutCrossDocumentLeakage() async throws {
        let documents = [
            makeDocument(relativePath: "a.md", title: "A", text: "The robust platform offers actionable insights."),
            makeDocument(relativePath: "b.md", title: "B", text: "Plain, unremarkable prose with nothing to flag."),
            makeDocument(relativePath: "c.md", title: "C", text: "In conclusion, it will define the next era.")
        ]

        let report = await DestinkService.analyze(documents: documents, useBenepar: false)

        XCTAssertEqual(report.documents.map(\.relativePath), ["a.md", "b.md", "c.md"])
        XCTAssertEqual(report.documents.map(\.title), ["A", "B", "C"])

        let first = try XCTUnwrap(report.documents.first { $0.relativePath == "a.md" })
        XCTAssertTrue(ruleIDs(first.findings).contains("lex-delve-family"))
        XCTAssertTrue(ruleIDs(first.findings).contains("corporate-jargon"))

        let second = try XCTUnwrap(report.documents.first { $0.relativePath == "b.md" })
        XCTAssertEqual(second.findings, [])

        let third = try XCTUnwrap(report.documents.first { $0.relativePath == "c.md" })
        XCTAssertTrue(ruleIDs(third.findings).contains("lex-signposts"))
        XCTAssertFalse(ruleIDs(third.findings).contains("lex-delve-family"))
        XCTAssertFalse(ruleIDs(third.findings).contains("corporate-jargon"))
    }

    func testAnalyzeWordCountMatchesDestinkEngineWordCountPerDocument() async throws {
        let document = makeDocument(text: "Seven words go into this one sentence.")

        let report = await DestinkService.analyze(documents: [document], useBenepar: false)

        let result = try XCTUnwrap(report.documents.first)
        XCTAssertEqual(result.wordCount, DestinkEngine.wordCount(document.text))
        XCTAssertEqual(result.wordCount, 7)
    }

    func testAnalyzeWithUseBeneparFalseNeverMarksUsedBenepar() async throws {
        let document = makeDocument(text: "The robust platform offers actionable insights.")

        let report = await DestinkService.analyze(
            documents: [document], useBenepar: false, benepar: unavailableBenepar()
        )

        let result = try XCTUnwrap(report.documents.first)
        XCTAssertFalse(result.usedBenepar)
        XCTAssertFalse(report.usedBenepar)
    }

    func testAnalyzeWithUnavailableBeneparPackGracefullyFallsBackToLocalFindings() async throws {
        let document = makeDocument(text: "The robust platform offers actionable insights.")

        let report = await DestinkService.analyze(
            documents: [document], useBenepar: true, benepar: unavailableBenepar()
        )

        let result = try XCTUnwrap(report.documents.first)
        XCTAssertFalse(result.usedBenepar)
        XCTAssertTrue(ruleIDs(result.findings).contains("lex-delve-family"))
        XCTAssertTrue(ruleIDs(result.findings).contains("corporate-jargon"))
    }

    func testAnalyzeWithEmptyDocumentsListProducesAnEmptyReportWithoutCrashing() async {
        let report = await DestinkService.analyze(
            documents: [], useBenepar: true, benepar: unavailableBenepar()
        )

        XCTAssertTrue(report.documents.isEmpty)
        XCTAssertEqual(report.wordCount, 0)
        XCTAssertEqual(report.findingCount, 0)
    }

    func testAnalyzeHandlesBlankDocumentTextWithoutFindingsOrCrashing() async throws {
        let document = makeDocument(text: "   \n\n  ")

        let report = await DestinkService.analyze(
            documents: [document], useBenepar: true, benepar: unavailableBenepar()
        )

        let result = try XCTUnwrap(report.documents.first)
        XCTAssertEqual(result.wordCount, 0)
        XCTAssertEqual(result.findings, [])
        XCTAssertFalse(result.usedBenepar)
    }
}
