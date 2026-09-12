import Foundation
import XCTest
@testable import Kistulentz

/// Covers `WritingAIService`'s own guard clauses and pure helpers -- the parts that never reach
/// the network, so no mock session is needed. `AIRequestTests` already covers the request/response
/// round trip against a mocked `URLSession`.
final class WritingAIServiceTests: XCTestCase {
    func testReviewRejectsARequestThatIsNotAPolishRequest() async {
        let service = WritingAIService()
        let request = makeRequest(purpose: .referenceDeepening, primaryText: "Some manuscript text.")

        await assertThrows(.invalidResponse) {
            try await service.review(request: request, apiKey: nil)
        }
    }

    func testReviewRejectsABlankDocument() async {
        let service = WritingAIService()
        let request = makeRequest(purpose: .polish(targetGrade: 8), primaryText: "   \n  ")

        await assertThrows(.emptyDocument) {
            try await service.review(request: request, apiKey: nil)
        }
    }

    func testReviewRejectsADocumentOverTheSizeLimit() async {
        let service = WritingAIService()
        let oversized = String(repeating: "a", count: 160_001)
        let request = makeRequest(purpose: .polish(targetGrade: 8), primaryText: oversized)

        await assertThrows(.documentTooLarge) {
            try await service.review(request: request, apiKey: nil)
        }
    }

    func testReferenceContextIncludesProfileSubjectsExcerptsAndLearnedInsights() {
        let chapter = ReferenceChapter(
            id: 0,
            title: "Chapter One",
            text: "Elara raised the lantern beside the quiet river and waited for dawn."
        )
        let reference = EPUBReference(
            fileName: "lantern.epub",
            title: "The Lantern Road",
            author: "Beau Henry",
            subjects: ["Fantasy"],
            chapters: [chapter],
            profile: ReferenceProfileBuilder.build(chapters: [chapter]),
            learnedInsights: "Favors short, declarative sentences.",
            sourceCount: 3
        )

        let context = WritingAIService.referenceContext(reference, relevantTo: "Elara waited by the river.")

        XCTAssertTrue(context.contains("<reference_profile title=\"The Lantern Road\">"))
        XCTAssertTrue(context.contains("Books represented: 3"))
        XCTAssertTrue(context.contains("Genres: Fantasy"))
        XCTAssertTrue(context.contains("<reference_excerpts>"))
        XCTAssertTrue(context.contains("Elara"))
        XCTAssertTrue(context.contains("<learned_insights>"))
        XCTAssertTrue(context.contains("Favors short, declarative sentences."))
    }

    func testReferenceContextOmitsLearnedInsightsBlockWhenThereAreNone() {
        let chapter = ReferenceChapter(id: 0, title: "Chapter One", text: "Plain descriptive prose about a quiet harbor.")
        let reference = EPUBReference(
            fileName: "harbor.epub",
            title: "Harbor Notes",
            author: nil,
            chapters: [chapter],
            profile: ReferenceProfileBuilder.build(chapters: [chapter])
        )

        let context = WritingAIService.referenceContext(reference, relevantTo: "harbor")

        XCTAssertFalse(context.contains("<learned_insights>"))
    }

    func testErrorDescriptionsAreDistinctAndActionableForEveryCase() {
        XCTAssertEqual(WritingAIError.emptyDocument.errorDescription, "Write or paste something before running an AI review.")
        XCTAssertEqual(WritingAIError.emptySelection.errorDescription, "Select a passage before choosing a rewrite.")
        XCTAssertTrue(WritingAIError.documentTooLarge.errorDescription?.contains("too large for a single review") ?? false)
        XCTAssertTrue(WritingAIError.selectionTooLarge.errorDescription?.contains("too large for one rewrite") ?? false)
        XCTAssertEqual(WritingAIError.missingModel.errorDescription, "Choose a model in Settings.")
        XCTAssertTrue(WritingAIError.missingAPIKey("Anthropic").errorDescription?.contains("Anthropic") ?? false)
        XCTAssertTrue(WritingAIError.ollamaUnavailable.errorDescription?.contains("Ollama") ?? false)
        XCTAssertTrue(WritingAIError.invalidResponse.errorDescription?.contains("could not read") ?? false)
        XCTAssertEqual(WritingAIError.network("timed out").errorDescription, "The review could not connect: timed out")
        XCTAssertEqual(WritingAIError.api(status: 429, message: "rate limited").errorDescription, "The provider returned error 429: rate limited")
    }

    // MARK: - Helpers

    private func makeRequest(purpose: AIRequestPurpose, primaryText: String) -> AIRequestPreview {
        AIRequestPreview(
            purpose: purpose,
            provider: .ollama,
            model: "local-model",
            primaryLabel: "Markdown draft",
            primaryText: primaryText,
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: nil,
            sourceText: primaryText
        )
    }

    private func assertThrows(
        _ expected: WritingAIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> AIReview
    ) async {
        do {
            _ = try await operation()
            XCTFail("expected \(expected) to be thrown", file: file, line: line)
        } catch let error as WritingAIError {
            XCTAssertEqual(error.errorDescription, expected.errorDescription, file: file, line: line)
        } catch {
            XCTFail("expected a WritingAIError, got \(error)", file: file, line: line)
        }
    }
}
