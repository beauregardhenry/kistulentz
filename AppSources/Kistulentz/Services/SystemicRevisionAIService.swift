import Foundation

struct SystemicRevisionAIService {
    private let client: StructuredAIClient

    init(session: URLSession = .shared) {
        client = StructuredAIClient(session: session)
    }

    func deepen(
        request: AIRequestPreview,
        documents: [ManuscriptDocument],
        apiKey: String?
    ) async throws -> (summary: String, findings: [SystemicRevisionFinding]) {
        guard case .systemicRevision = request.purpose else { throw WritingAIError.invalidResponse }
        let raw = try await client.generate(
            provider: request.provider,
            model: request.model,
            apiKey: apiKey,
            instructions: request.instructions,
            input: request.input,
            schemaName: "systemic_revision_findings",
            schema: Self.schema,
            maxTokens: 8_000
        )
        let cleaned = raw.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let response = try? JSONDecoder().decode(AISystemicRevisionResponse.self, from: data) else {
            throw WritingAIError.invalidResponse
        }
        let byPath = Dictionary(uniqueKeysWithValues: documents.map { ($0.relativePath, $0.text) })
        let now = Date()
        let findings = response.findings.compactMap { item -> SystemicRevisionFinding? in
            guard let pass = RevisionPass(rawValue: item.revisionPass),
                  let classification = RevisionFindingClassification(rawValue: item.classification),
                  let text = byPath[item.chapterPath] else { return nil }
            let excerpt = item.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !excerpt.isEmpty {
                let source = text as NSString
                let first = source.range(of: excerpt)
                guard first.location != NSNotFound else { return nil }
                let nextLocation = NSMaxRange(first)
                if nextLocation < source.length,
                   source.range(of: excerpt, range: NSRange(location: nextLocation, length: source.length - nextLocation)).location != NSNotFound {
                    return nil
                }
            }
            let signature = Self.signature([pass.rawValue, classification.rawValue, item.title, item.chapterPath, excerpt.lowercased(), request.provider.rawValue, request.model])
            return SystemicRevisionFinding(
                signature: signature,
                revisionPass: pass,
                classification: classification,
                title: item.title,
                detail: item.detail,
                chapterPath: item.chapterPath,
                excerpt: excerpt,
                replacement: item.replacement.isEmpty ? nil : item.replacement,
                origin: .ai,
                provider: request.provider.title,
                model: request.model,
                createdAt: now,
                lastSeenAt: now
            )
        }
        return (response.summary, findings)
    }

    private static func signature(_ parts: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in parts.joined(separator: "\u{1F}").utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string"],
            "findings": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "revisionPass": ["type": "string", "enum": RevisionPass.allCases.map(\.rawValue)],
                        "classification": ["type": "string", "enum": RevisionFindingClassification.allCases.map(\.rawValue)],
                        "title": ["type": "string"],
                        "detail": ["type": "string"],
                        "chapterPath": ["type": "string"],
                        "excerpt": ["type": "string"],
                        "replacement": ["type": "string"]
                    ],
                    "required": ["revisionPass", "classification", "title", "detail", "chapterPath", "excerpt", "replacement"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["summary", "findings"],
        "additionalProperties": false
    ]
}
