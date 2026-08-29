import Foundation
import XCTest
@testable import Kistulentz

final class AIRequestTests: XCTestCase {
    override func tearDown() {
        AIRequestMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testPreviewIncludesOnlyEnabledOptionalMaterial() {
        var preview = AIRequestPreview(
            purpose: .polish(targetGrade: 8),
            provider: .openAI,
            model: "test-model",
            primaryLabel: "Draft",
            primaryText: "# Chapter\n\nThe draft.",
            styleGuide: "Prefer concrete language.",
            includesStyleGuide: true,
            referenceContext: "<reference_excerpts>Sample</reference_excerpts>",
            includesReferenceContext: false,
            sourceRange: nil,
            sourceText: nil
        )

        XCTAssertTrue(preview.input.contains("Prefer concrete language."))
        XCTAssertFalse(preview.input.contains("Sample"))

        preview.includesStyleGuide = false
        preview.includesReferenceContext = true
        XCTAssertFalse(preview.input.contains("Prefer concrete language."))
        XCTAssertTrue(preview.input.contains("Sample"))
    }

    func testSelectionReplacementRequiresTheOriginalPassageToBeUnchanged() {
        let text = "Before 🌊 passage after."
        let range = (text as NSString).range(of: "🌊 passage")

        XCTAssertEqual(
            SelectionReplacementPlanner.replace(
                in: text,
                range: range,
                expected: "🌊 passage",
                with: "clear passage"
            ),
            "Before clear passage after."
        )
        XCTAssertNil(SelectionReplacementPlanner.replace(
            in: "Before changed passage after.",
            range: range,
            expected: "🌊 passage",
            with: "clear passage"
        ))
    }

    @MainActor
    func testOllamaIsReadyWithAChosenModelAndNoAPIKey() throws {
        let suite = "AIRequestSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        settings.ollamaModel = "local-model:latest"

        XCTAssertTrue(settings.isProviderReady(.ollama))
        XCTAssertNil(settings.apiKey(for: .ollama))
        XCTAssertTrue(AIProvider.ollama.isLocal)
    }

    @MainActor
    func testProviderModelCatalogDefaultsAndPreservesCustomModels() throws {
        let suite = "AIModelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.openAIModel, AIModelCatalog.recommendedModel(for: .openAI))
        XCTAssertEqual(settings.anthropicModel, AIModelCatalog.recommendedModel(for: .anthropic))
        XCTAssertTrue(AIModelCatalog.openAI.contains { $0.id == settings.openAIModel })
        XCTAssertTrue(AIModelCatalog.anthropic.contains { $0.id == settings.anthropicModel })

        settings.openAIModel = "future-openai-model"
        settings.anthropicModel = "future-anthropic-model"

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.openAIModel, "future-openai-model")
        XCTAssertEqual(reopened.anthropicModel, "future-anthropic-model")
    }

    func testProviderModelCatalogIdentifiersAreUnique() {
        for provider in [AIProvider.openAI, .anthropic] {
            let choices = AIModelCatalog.choices(for: provider)
            XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
            XCTAssertEqual(choices.filter(\.isRecommended).count, 1)
        }
    }

    func testDetectsModelsFromTheLocalOllamaTagsEndpoint() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/tags")
            let body: [String: Any] = [
                "models": [
                    ["name": "gemma3:latest", "model": "gemma3:latest"],
                    ["name": "llama3.2:latest", "model": "llama3.2:latest"]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }

        let models = try await OllamaService(session: session).installedModels()

        XCTAssertEqual(models, ["gemma3:latest", "llama3.2:latest"])
    }

    func testOllamaRewriteUsesStructuredNonStreamingLocalRequest() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
            let data = try XCTUnwrap(request.bodyData)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "local-model")
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertNotNil(body["format"] as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])

            let result = """
            {"alternatives":[
              {"text":"First.","explanation":"Direct.","gradeEstimate":5},
              {"text":"Second.","explanation":"Compact.","gradeEstimate":5.5},
              {"text":"Third.","explanation":"Rhythmic.","gradeEstimate":6}
            ]}
            """
            let response: [String: Any] = [
                "message": ["role": "assistant", "content": result]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let goal = SelectionRewriteGoal(kind: .shorten, requestedTone: nil)
        let preview = AIRequestPreview(
            purpose: .selectionRewrite(goal: goal, targetGrade: 8),
            provider: .ollama,
            model: "local-model",
            primaryLabel: "Selection",
            primaryText: "This is a longer selection.",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: NSRange(location: 0, length: 27),
            sourceText: "This is a longer selection."
        )

        let result = try await SelectionRewriteService(session: session).rewrite(
            request: preview,
            apiKey: nil
        )

        XCTAssertEqual(result.alternatives.count, 3)
        XCTAssertEqual(result.alternatives.first?.text, "First.")
    }

    func testRewriteRejectsAProviderResponseWithoutThreeAlternatives() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let result = """
            {"alternatives":[
              {"text":"First.","explanation":"Direct.","gradeEstimate":5},
              {"text":"Second.","explanation":"Compact.","gradeEstimate":5.5}
            ]}
            """
            let response: [String: Any] = [
                "message": ["role": "assistant", "content": result]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }
        let preview = AIRequestPreview(
            purpose: .selectionRewrite(
                goal: SelectionRewriteGoal(kind: .shorten, requestedTone: nil),
                targetGrade: 8
            ),
            provider: .ollama,
            model: "local-model",
            primaryLabel: "Selection",
            primaryText: "A passage to shorten.",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: NSRange(location: 0, length: 21),
            sourceText: "A passage to shorten."
        )

        do {
            _ = try await SelectionRewriteService(session: session).rewrite(
                request: preview,
                apiKey: nil
            )
            XCTFail("An incomplete alternative set should be rejected.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, received \(error).")
            }
        }
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIRequestMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AIRequestMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
