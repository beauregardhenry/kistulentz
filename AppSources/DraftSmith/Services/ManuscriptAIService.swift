import Foundation

struct ManuscriptAIService {
    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    func deepenMarkdown(request: AIRequestPreview, apiKey: String?) async throws -> AIManuscriptMarkdownResponse {
        guard request.purpose.isManuscriptMarkdownPurpose else { throw WritingAIError.invalidResponse }
        let raw = try await generate(
            request: request,
            apiKey: apiKey,
            schemaName: "manuscript_editorial_notes",
            schema: Self.markdownSchema,
            maxTokens: 8_000
        )
        return try decode(AIManuscriptMarkdownResponse.self, from: raw)
    }

    func betaRead(
        request: AIRequestPreview,
        profile: BetaReaderProfile,
        scope: BetaReaderScope,
        apiKey: String?
    ) async throws -> BetaReaderFeedback {
        guard case .betaReader = request.purpose else { throw WritingAIError.invalidResponse }
        let raw = try await generate(
            request: request,
            apiKey: apiKey,
            schemaName: "beta_reader_feedback",
            schema: Self.betaSchema,
            maxTokens: 5_000
        )
        let response = try decode(AIBetaReaderResponse.self, from: raw)
        return BetaReaderFeedback(
            reader: profile,
            scope: scope,
            source: .ai(provider: request.provider.title, model: request.model),
            summary: response.summary,
            reaction: response.reaction,
            strengths: response.strengths,
            concerns: response.concerns,
            questions: response.questions
        )
    }

    private func generate(
        request: AIRequestPreview,
        apiKey: String?,
        schemaName: String,
        schema: [String: Any],
        maxTokens: Int
    ) async throws -> String {
        try await client.generate(
            provider: request.provider,
            model: request.model,
            apiKey: apiKey,
            instructions: request.instructions,
            input: request.input,
            schemaName: schemaName,
            schema: schema,
            maxTokens: maxTokens
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let value = try? JSONDecoder().decode(type, from: data) else {
            throw WritingAIError.invalidResponse
        }
        return value
    }

    private static let markdownSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "markdown": ["type": "string"]
        ],
        "required": ["summary", "markdown"],
        "additionalProperties": false
    ]

    private static let betaSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "reaction": ["type": "string"],
            "strengths": ["type": "array", "items": ["type": "string"]],
            "concerns": ["type": "array", "items": ["type": "string"]],
            "questions": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["summary", "reaction", "strengths", "concerns", "questions"],
        "additionalProperties": false
    ]
}

private extension AIRequestPurpose {
    var isManuscriptMarkdownPurpose: Bool {
        switch self {
        case .manuscriptReport, .manuscriptBible: true
        default: false
        }
    }
}
