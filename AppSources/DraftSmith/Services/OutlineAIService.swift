import Foundation

struct OutlineAIService {
    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    func suggestSynopsis(request: AIRequestPreview, apiKey: String?) async throws -> AIOutlineSynopsisResponse {
        guard case .outlineSynopsis = request.purpose else { throw WritingAIError.invalidResponse }
        let raw = try await client.generate(
            provider: request.provider,
            model: request.model,
            apiKey: apiKey,
            instructions: request.instructions,
            input: request.input,
            schemaName: "outline_synopsis",
            schema: Self.schema,
            maxTokens: 1_500
        )
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let response = try? JSONDecoder().decode(AIOutlineSynopsisResponse.self, from: data) else {
            throw WritingAIError.invalidResponse
        }
        return response
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "synopsis": ["type": "string"]
        ],
        "required": ["summary", "synopsis"],
        "additionalProperties": false
    ]
}
