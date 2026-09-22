import Foundation
import XCTest
@testable import Kistulentz

/// Covers `WritingAIService.referenceContext`, the one piece of this namespace still in use --
/// several other AI-backed request types (Selection Rewrite, Beta Reader, Outline Synopsis) build
/// their reference material through it.
final class WritingAIServiceTests: XCTestCase {
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
        XCTAssertTrue(WritingAIError.ollamaTimedOut.errorDescription?.contains("Ollama") ?? false)
        XCTAssertTrue(WritingAIError.invalidResponse.errorDescription?.contains("could not read") ?? false)
        XCTAssertEqual(WritingAIError.network("timed out").errorDescription, "The review could not connect: timed out")
        XCTAssertTrue(WritingAIError.requestTimedOut.errorDescription?.contains("timed out") ?? false)
        XCTAssertEqual(WritingAIError.api(status: 429, message: "rate limited").errorDescription, "The provider returned error 429: rate limited")
    }

    /// `looksLikeProviderRelatedMessage` is what the shared error alert (`EditorWorkspace`) uses to
    /// decide whether to offer an "Open Settings" button, working only from an already-flattened
    /// `String` -- every catch site across the app stores `error.localizedDescription`, not the
    /// original `WritingAIError`, by the time an error reaches that alert.
    func testLooksLikeProviderRelatedMessageRecognizesEveryActionableCaseAndRejectsTheRest() {
        let actionable: [WritingAIError] = [
            .missingModel,
            .missingAPIKey("Anthropic"),
            .ollamaUnavailable,
            .ollamaTimedOut,
            .invalidResponse,
            .network("timed out"),
            .requestTimedOut,
            .api(status: 429, message: "You have no credits remaining.")
        ]
        for error in actionable {
            let message = error.errorDescription ?? ""
            XCTAssertTrue(
                WritingAIError.looksLikeProviderRelatedMessage(message),
                "Expected \(error) to be recognized as provider-related: \(message)"
            )
        }

        let notActionable: [WritingAIError] = [.emptyDocument, .emptySelection, .documentTooLarge, .selectionTooLarge]
        for error in notActionable {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(
                WritingAIError.looksLikeProviderRelatedMessage(message),
                "Did not expect \(error) to be recognized as provider-related: \(message)"
            )
        }

        XCTAssertFalse(WritingAIError.looksLikeProviderRelatedMessage("That passage has changed, so the suggestion can no longer be declined."))
    }
}
