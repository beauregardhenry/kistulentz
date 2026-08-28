import Foundation

struct WritingAIService {
    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    func review(request: AIRequestPreview, apiKey: String?) async throws -> AIReview {
        guard case .polish = request.purpose else {
            throw WritingAIError.invalidResponse
        }
        guard !request.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WritingAIError.emptyDocument
        }
        guard request.primaryText.utf8.count <= 160_000 else {
            throw WritingAIError.documentTooLarge
        }

        let raw = try await client.generate(
            provider: request.provider,
            model: request.model,
            apiKey: apiKey,
            instructions: request.instructions,
            input: request.input,
            schemaName: "writing_review",
            schema: Self.reviewSchema,
            maxTokens: 8_000
        )
        return try Self.decodeReview(from: raw)
    }

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

    private static func decodeReview(from rawText: String) throws -> AIReview {
        let cleaned = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let review = try? JSONDecoder().decode(AIReview.self, from: data) else {
            throw WritingAIError.invalidResponse
        }
        return review
    }

    private static let reviewSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "gradeEstimate": ["type": "number"],
            "polishedText": ["type": "string"],
            "suggestions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "original": ["type": "string"],
                        "replacement": ["type": "string"],
                        "explanation": ["type": "string"],
                        "category": [
                            "type": "string",
                            "enum": ["spelling", "grammar", "clarity", "concision", "tone"]
                        ]
                    ],
                    "required": ["original", "replacement", "explanation", "category"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["summary", "gradeEstimate", "polishedText", "suggestions"],
        "additionalProperties": false
    ]
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
