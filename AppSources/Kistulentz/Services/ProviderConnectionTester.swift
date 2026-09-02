import Foundation

struct ProviderConnectionResult: Equatable {
    let provider: AIProvider
    let model: String
    let message: String
}

enum ProviderConnectionError: LocalizedError, Equatable {
    case missingAPIKey(String)
    case missingModel
    case rejected(provider: String, status: Int)
    case invalidResponse(String)
    case modelUnavailable(String)
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "Save a \(provider) API key before testing the connection."
        case .missingModel:
            "Choose a model before testing the connection."
        case .rejected(let provider, let status):
            "\(provider) rejected the connection test (HTTP \(status)). Check the key, account access, and selected model."
        case .invalidResponse(let provider):
            "\(provider) responded, but Kistulentz could not verify the selected model."
        case .modelUnavailable(let model):
            "The selected model “\(model)” is not available from this provider."
        case .unreachable(let provider):
            "Kistulentz could not reach \(provider). Check the connection or make sure the local service is running."
        }
    }
}

/// Verifies credentials and selected-model availability without including any
/// manuscript, reference, project, or prompt text in the request.
struct ProviderConnectionTester {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func test(
        provider: AIProvider,
        model rawModel: String,
        apiKey rawAPIKey: String?
    ) async throws -> ProviderConnectionResult {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw ProviderConnectionError.missingModel }

        switch provider {
        case .openAI:
            let apiKey = try requiredKey(rawAPIKey, provider: provider)
            var request = URLRequest(
                url: URL(string: "https://api.openai.com/v1/models")!
                    .appendingPathComponent(model)
            )
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            try await verifyModelResponse(request, provider: provider, expectedModel: model)
        case .anthropic:
            let apiKey = try requiredKey(rawAPIKey, provider: provider)
            var request = URLRequest(
                url: URL(string: "https://api.anthropic.com/v1/models")!
                    .appendingPathComponent(model)
            )
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            try await verifyModelResponse(request, provider: provider, expectedModel: model)
        case .ollama:
            let models: [String]
            do {
                models = try await OllamaService(session: session).installedModels()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ProviderConnectionError.unreachable(provider.title)
            }
            guard models.contains(model) else {
                throw ProviderConnectionError.modelUnavailable(model)
            }
        }

        return ProviderConnectionResult(
            provider: provider,
            model: model,
            message: provider == .ollama
                ? "Ollama is running and \(model) is installed on this Mac."
                : "\(provider.title) accepted the key and reports \(model) as available."
        )
    }

    private func requiredKey(_ rawKey: String?, provider: AIProvider) throws -> String {
        let key = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw ProviderConnectionError.missingAPIKey(provider.title) }
        return key
    }

    private func verifyModelResponse(
        _ request: URLRequest,
        provider: AIProvider,
        expectedModel: String
    ) async throws {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderConnectionError.invalidResponse(provider.title)
            }
            guard (200...299).contains(http.statusCode) else {
                throw ProviderConnectionError.rejected(
                    provider: provider.title,
                    status: http.statusCode
                )
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String else {
                throw ProviderConnectionError.invalidResponse(provider.title)
            }
            guard id == expectedModel else {
                throw ProviderConnectionError.modelUnavailable(expectedModel)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProviderConnectionError {
            throw error
        } catch {
            throw ProviderConnectionError.unreachable(provider.title)
        }
    }
}
