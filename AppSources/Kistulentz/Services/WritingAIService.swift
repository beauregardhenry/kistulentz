import Foundation

/// Just `referenceContext` now -- the request-preview/response round trip this used to own for
/// AI-backed Polish requests was removed once Polish started always running locally (nothing
/// constructs an `AIRequestPurpose.polish` request anymore). `referenceContext` itself is still
/// live: several other AI-backed request types (Selection Rewrite, Beta Reader, Outline Synopsis)
/// build their reference material through it.
enum WritingAIService {
    static func referenceContext(
        _ reference: EPUBReference,
        relevantTo text: String,
        maxCharacters: Int = 24_000
    ) -> String {
        let excerpts = reference.selectedExcerpts(relevantTo: text, maxCharacters: maxCharacters)
        let learnedInsights = reference.learnedInsights.map {
            "\n<learned_insights>\n\($0)\n</learned_insights>"
        } ?? ""
        return """
        <reference_profile title="\(reference.title)">
        Books represented: \(reference.sourceCount)
        Genres: \(reference.subjects.joined(separator: ", "))
        \(reference.profile.aiSummary)
        </reference_profile>

        <reference_excerpts>
        \(excerpts)
        </reference_excerpts>
        \(learnedInsights)
        """
    }
}

enum WritingAIError: LocalizedError {
    case emptyDocument
    case emptySelection
    case documentTooLarge
    case selectionTooLarge
    case missingModel
    case missingAPIKey(String)
    case ollamaUnavailable
    case invalidResponse
    case network(String)
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "Write or paste something before running an AI review."
        case .emptySelection:
            "Select a passage before choosing a rewrite."
        case .documentTooLarge:
            "This document is too large for a single review. Split it into sections and try again."
        case .selectionTooLarge:
            "That selection is too large for one rewrite. Select a shorter passage and try again."
        case .missingModel:
            "Choose a model in Settings."
        case .missingAPIKey(let provider):
            "Add your \(provider) API key in Settings before using this command."
        case .ollamaUnavailable:
            "Kistulentz could not reach Ollama on this Mac. Open Ollama, make sure at least one model is installed, then try Detect Models in Settings."
        case .invalidResponse:
            "The provider returned a response Kistulentz could not read. Try again or choose another model."
        case .network(let message):
            "The review could not connect: \(message)"
        case .api(let status, let message):
            "The provider returned error \(status): \(message)"
        }
    }
}
