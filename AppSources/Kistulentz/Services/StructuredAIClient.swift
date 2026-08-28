import Foundation

struct StructuredAIClient {
    static let ollamaBaseURL = URL(string: "http://localhost:11434")!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generate(
        provider: AIProvider,
        model: String,
        apiKey: String?,
        instructions: String,
        input: String,
        schemaName: String,
        schema: [String: Any],
        maxTokens: Int
    ) async throws -> String {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WritingAIError.missingModel
        }

        switch provider {
        case .openAI:
            guard let apiKey, !apiKey.isEmpty else { throw WritingAIError.missingAPIKey(provider.title) }
            return try await openAI(
                model: model,
                apiKey: apiKey,
                instructions: instructions,
                input: input,
                schemaName: schemaName,
                schema: schema
            )
        case .anthropic:
            guard let apiKey, !apiKey.isEmpty else { throw WritingAIError.missingAPIKey(provider.title) }
            return try await anthropic(
                model: model,
                apiKey: apiKey,
                instructions: instructions,
                input: input,
                schema: schema,
                maxTokens: maxTokens
            )
        case .ollama:
            return try await ollama(
                model: model,
                instructions: instructions,
                input: input,
                schema: schema
            )
        }
    }

    private func openAI(
        model: String,
        apiKey: String,
        instructions: String,
        input: String,
        schemaName: String,
        schema: [String: Any]
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "store": false,
            "instructions": instructions,
            "input": input,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "strict": true,
                    "schema": schema
                ]
            ]
        ])

        let data = try await perform(request)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let output = root?["output"] as? [[String: Any]] else {
            throw WritingAIError.invalidResponse
        }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if let text = block["text"] as? String { return text }
            }
        }
        throw WritingAIError.invalidResponse
    }

    private func anthropic(
        model: String,
        apiKey: String,
        instructions: String,
        input: String,
        schema: [String: Any],
        maxTokens: Int
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": maxTokens,
            "system": instructions,
            "messages": [["role": "user", "content": input]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]]
        ])

        let data = try await perform(request)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = root?["content"] as? [[String: Any]] else {
            throw WritingAIError.invalidResponse
        }
        for block in content where block["type"] as? String == "text" {
            if let text = block["text"] as? String { return text }
        }
        throw WritingAIError.invalidResponse
    }

    private func ollama(
        model: String,
        instructions: String,
        input: String,
        schema: [String: Any]
    ) async throws -> String {
        var request = URLRequest(url: Self.ollamaBaseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": input]
            ],
            "format": schema,
            "stream": false,
            "options": ["temperature": 0]
        ])

        let data: Data
        do {
            data = try await perform(request)
        } catch let error as WritingAIError {
            if case .network = error { throw WritingAIError.ollamaUnavailable }
            throw error
        }
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let message = root?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw WritingAIError.invalidResponse
        }
        return content
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WritingAIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw WritingAIError.api(status: http.statusCode, message: Self.apiErrorMessage(from: data))
            }
            return data
        } catch let error as WritingAIError {
            throw error
        } catch {
            throw WritingAIError.network(error.localizedDescription)
        }
    }

    private static func apiErrorMessage(from data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "The provider returned an error."
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = root["error"] as? String { return error }
        return root["message"] as? String ?? "The provider returned an error."
    }
}

struct OllamaService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func installedModels() async throws -> [String] {
        let url = StructuredAIClient.ollamaBaseURL.appendingPathComponent("api/tags")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw WritingAIError.ollamaUnavailable
            }
            let result = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
            return Array(Set(result.models.map { $0.model.nonEmpty ?? $0.name }))
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch let error as WritingAIError {
            throw error
        } catch {
            throw WritingAIError.ollamaUnavailable
        }
    }
}

private struct OllamaModelsResponse: Decodable {
    let models: [OllamaModelResponse]
}

private struct OllamaModelResponse: Decodable {
    let name: String
    let model: String
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
