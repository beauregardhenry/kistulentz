import Foundation

struct SelectionRewriteService {
    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    func rewrite(request: AIRequestPreview, apiKey: String?) async throws -> SelectionRewriteResult {
        guard case .selectionRewrite = request.purpose else {
            throw WritingAIError.invalidResponse
        }
        guard !request.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WritingAIError.emptySelection
        }
        guard request.primaryText.utf8.count <= 80_000 else {
            throw WritingAIError.selectionTooLarge
        }

        let raw = try await client.generate(
            provider: request.provider,
            model: request.model,
            apiKey: apiKey,
            instructions: request.instructions,
            input: request.input,
            schemaName: "selection_rewrite",
            schema: Self.schema,
            maxTokens: 6_000
        )
        return try Self.decode(raw)
    }

    private static func decode(_ rawText: String) throws -> SelectionRewriteResult {
        let cleaned = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(SelectionRewriteResult.self, from: data),
              result.alternatives.count == 3 else {
            throw WritingAIError.invalidResponse
        }
        return result
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "alternatives": [
                "type": "array",
                "minItems": 3,
                "maxItems": 3,
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "explanation": ["type": "string"],
                        "gradeEstimate": ["type": "number"]
                    ],
                    "required": ["text", "explanation", "gradeEstimate"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["alternatives"],
        "additionalProperties": false
    ]
}
