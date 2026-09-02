import Foundation

struct ReferenceDeepeningService {
    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    func deepen(
        reference: EPUBReference,
        provider: AIProvider,
        model: String,
        apiKey: String?
    ) async throws -> ReferenceDeepening {
        try await deepen(
            input: Self.input(for: reference),
            provider: provider,
            model: model,
            apiKey: apiKey
        )
    }

    func deepen(
        input: String,
        provider: AIProvider,
        model: String,
        apiKey: String?
    ) async throws -> ReferenceDeepening {
        let raw = try await client.generate(
            provider: provider,
            model: model,
            apiKey: apiKey,
            instructions: Self.instructions,
            input: input,
            schemaName: "reference_deepening",
            schema: Self.schema,
            maxTokens: 4_000
        )
        return try Self.decode(raw)
    }

    static let instructions = AIRequestBuilder.instructions(
        for: .referenceDeepening,
        hasStyleGuide: false,
        hasReference: true
    )

    static func input(for reference: EPUBReference) -> String {
        let excerpts = reference.selectedExcerpts(relevantTo: "", maxCharacters: 16_000)
        let prior = reference.learnedInsights.map { "\n<prior_insights>\n\($0)\n</prior_insights>" } ?? ""
        return """
        Analyze this local reference selection containing \(reference.sourceCount) book(s).

        <profile>
        Title: \(reference.title)
        Genres: \(reference.subjects.joined(separator: ", "))
        \(reference.profile.aiSummary)
        </profile>

        <selected_excerpts>
        \(excerpts)
        </selected_excerpts>
        \(prior)
        """
    }

    private static func decode(_ rawText: String) throws -> ReferenceDeepening {
        let cleaned = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let result = try? JSONDecoder().decode(ReferenceDeepening.self, from: data) else {
            throw WritingAIError.invalidResponse
        }
        return result
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "style": ["type": "string"],
            "voice": ["type": "string"],
            "tone": ["type": "string"],
            "vocabulary": ["type": "string"],
            "characterContinuity": ["type": "string"],
            "tempo": ["type": "string"],
            "techniques": ["type": "array", "items": ["type": "string"]],
            "suggestedGenres": ["type": "array", "items": ["type": "string"]]
        ],
        "required": [
            "summary", "style", "voice", "tone", "vocabulary",
            "characterContinuity", "tempo", "techniques", "suggestedGenres"
        ],
        "additionalProperties": false
    ]
}
