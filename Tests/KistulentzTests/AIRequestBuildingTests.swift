import Foundation
import XCTest
@testable import Kistulentz

/// Direct unit tests for the AI request-building layer: `StructuredAIClient` (builds and parses the raw
/// HTTP request/response for each provider) and the two services built on top of it, `ManuscriptAIService`
/// and `SystemicRevisionAIService`. `AIRequestTests.swift` already covers `SelectionRewriteService` and
/// `OllamaService` this way; these three were the remaining gap -- none of them had a direct test before.
///
/// Two things matter most here, matching how the rest of this codebase tests the AI layer: that the
/// request actually sent over the wire is exactly what each provider's API expects (URL, headers, and
/// body shape, not just "some request went out"), and that a response coming back from the AI is treated
/// as untrusted content -- decoded defensively, and in `SystemicRevisionAIService`'s case, checked against
/// the manuscript's real chapter paths and verbatim text before a single finding is accepted.
final class AIRequestBuildingTests: XCTestCase {
    override func tearDown() {
        AIRequestBuildingMockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - StructuredAIClient

    func testGenerateThrowsMissingModelForABlankModel() async {
        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .openAI,
                model: "   ",
                apiKey: "sk-test-key",
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A blank model must be rejected before any network call.")
        } catch let error as WritingAIError {
            guard case .missingModel = error else {
                return XCTFail("Expected missingModel, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testGenerateThrowsMissingAPIKeyForOpenAIWithoutAKey() async {
        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .openAI,
                model: "gpt-test",
                apiKey: nil,
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A missing OpenAI API key must be rejected before any network call.")
        } catch let error as WritingAIError {
            guard case .missingAPIKey(let provider) = error else {
                return XCTFail("Expected missingAPIKey, got \(error).")
            }
            XCTAssertEqual(provider, "OpenAI")
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testGenerateThrowsMissingAPIKeyForAnthropicWithAnEmptyKey() async {
        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .anthropic,
                model: "claude-test",
                apiKey: "",
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("An empty-string Anthropic API key must be rejected before any network call.")
        } catch let error as WritingAIError {
            guard case .missingAPIKey(let provider) = error else {
                return XCTFail("Expected missingAPIKey, got \(error).")
            }
            XCTAssertEqual(provider, "Anthropic")
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testGenerateBuildsTheExpectedOpenAIRequest() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(request.jsonBody)
            XCTAssertEqual(body["model"] as? String, "gpt-test")
            XCTAssertEqual(body["store"] as? Bool, false)
            XCTAssertEqual(body["instructions"] as? String, "System instructions.")
            XCTAssertEqual(body["input"] as? String, "The user input.")
            let text = try XCTUnwrap(body["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            XCTAssertEqual(format["name"] as? String, "schema_name")
            XCTAssertEqual(format["strict"] as? Bool, true)
            return (self.okResponse(for: request), self.openAIEnvelope(text: "ok"))
        }

        _ = try await StructuredAIClient(session: mockSession()).generate(
            provider: .openAI,
            model: "gpt-test",
            apiKey: "sk-test-key",
            instructions: "System instructions.",
            input: "The user input.",
            schemaName: "schema_name",
            schema: ["type": "object"],
            maxTokens: 100
        )
    }

    func testGenerateParsesTheOpenAIResponseTextAndThrowsWhenOutputIsMissing() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            (self.okResponse(for: request), self.openAIEnvelope(text: "Extracted text."))
        }

        let result = try await StructuredAIClient(session: mockSession()).generate(
            provider: .openAI,
            model: "gpt-test",
            apiKey: "sk-test-key",
            instructions: "Instructions.",
            input: "Input.",
            schemaName: "schema",
            schema: ["type": "object"],
            maxTokens: 100
        )
        XCTAssertEqual(result, "Extracted text.")

        AIRequestBuildingMockURLProtocol.handler = { request in
            (self.okResponse(for: request), try JSONSerialization.data(withJSONObject: [String: Any]()))
        }
        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .openAI,
                model: "gpt-test",
                apiKey: "sk-test-key",
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A response with no output array must be rejected.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error).")
            }
        }
    }

    func testGenerateBuildsTheExpectedAnthropicRequest() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try XCTUnwrap(request.jsonBody)
            XCTAssertEqual(body["model"] as? String, "claude-test")
            XCTAssertEqual(body["max_tokens"] as? Int, 321)
            XCTAssertEqual(body["system"] as? String, "System instructions.")
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?["role"] as? String, "user")
            XCTAssertEqual(messages.first?["content"] as? String, "The user input.")
            let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
            let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            return (self.okResponse(for: request), self.anthropicEnvelope(text: "ok"))
        }

        _ = try await StructuredAIClient(session: mockSession()).generate(
            provider: .anthropic,
            model: "claude-test",
            apiKey: "sk-ant-test-key",
            instructions: "System instructions.",
            input: "The user input.",
            schemaName: "schema",
            schema: ["type": "object"],
            maxTokens: 321
        )
    }

    func testGenerateParsesTheAnthropicResponseTextAndSkipsNonTextBlocks() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body: [String: Any] = [
                "content": [
                    ["type": "tool_use", "id": "toolu_1", "name": "lookup", "input": [String: Any]()],
                    ["type": "text", "text": "The real answer."]
                ]
            ]
            return (self.okResponse(for: request), try JSONSerialization.data(withJSONObject: body))
        }

        let result = try await StructuredAIClient(session: mockSession()).generate(
            provider: .anthropic,
            model: "claude-test",
            apiKey: "sk-ant-test-key",
            instructions: "Instructions.",
            input: "Input.",
            schemaName: "schema",
            schema: ["type": "object"],
            maxTokens: 100
        )
        XCTAssertEqual(result, "The real answer.")

        AIRequestBuildingMockURLProtocol.handler = { request in
            let body: [String: Any] = ["content": [["type": "tool_use", "id": "toolu_1", "name": "lookup", "input": [String: Any]()]]]
            return (self.okResponse(for: request), try JSONSerialization.data(withJSONObject: body))
        }
        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .anthropic,
                model: "claude-test",
                apiKey: "sk-ant-test-key",
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A response with no text content block must be rejected.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error).")
            }
        }
    }

    func testGenerateBuildsTheExpectedOllamaRequestWithoutRequiringAnAPIKey() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.jsonBody)
            XCTAssertEqual(body["model"] as? String, "local-model")
            XCTAssertEqual(body["stream"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
            XCTAssertEqual(messages.first?["content"] as? String, "System instructions.")
            XCTAssertEqual(messages.last?["content"] as? String, "The user input.")
            XCTAssertNotNil(body["format"] as? [String: Any])
            let options = try XCTUnwrap(body["options"] as? [String: Any])
            XCTAssertEqual(options["temperature"] as? Int, 0)
            return (self.okResponse(for: request), self.ollamaEnvelope(content: "ok"))
        }

        // No apiKey at all: Ollama is the only provider that never requires one.
        _ = try await StructuredAIClient(session: mockSession()).generate(
            provider: .ollama,
            model: "local-model",
            apiKey: nil,
            instructions: "System instructions.",
            input: "The user input.",
            schemaName: "schema",
            schema: ["type": "object"],
            maxTokens: 100
        )
    }

    func testGenerateParsesTheOllamaResponseMessageContent() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            (self.okResponse(for: request), self.ollamaEnvelope(content: "Ollama's answer."))
        }

        let result = try await StructuredAIClient(session: mockSession()).generate(
            provider: .ollama,
            model: "local-model",
            apiKey: nil,
            instructions: "Instructions.",
            input: "Input.",
            schemaName: "schema",
            schema: ["type": "object"],
            maxTokens: 100
        )
        XCTAssertEqual(result, "Ollama's answer.")
    }

    func testGenerateWrapsOllamaNetworkFailureAsOllamaUnavailable() async {
        AIRequestBuildingMockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .ollama,
                model: "local-model",
                apiKey: nil,
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A transport failure while talking to Ollama must be surfaced.")
        } catch let error as WritingAIError {
            // Ollama specifically remaps any transport-level failure to a friendlier "go start Ollama"
            // error, rather than the generic .network(...) every other provider would surface.
            guard case .ollamaUnavailable = error else {
                return XCTFail("Expected ollamaUnavailable, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testGenerateWrapsAGenericTransportFailureAsNetworkErrorForNonOllamaProviders() async {
        AIRequestBuildingMockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .openAI,
                model: "gpt-test",
                apiKey: "sk-test-key",
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A transport failure must be surfaced.")
        } catch let error as WritingAIError {
            // Unlike Ollama, OpenAI/Anthropic have no local-daemon fallback message, so a transport
            // failure stays a plain .network(...) rather than being remapped.
            guard case .network = error else {
                return XCTFail("Expected network, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testAPIErrorMessageFallsBackThroughEveryShapeOfProviderErrorBody() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body: [String: Any] = ["error": ["message": "Rate limited."]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        await assertAPIError(status: 429, message: "Rate limited.")

        AIRequestBuildingMockURLProtocol.handler = { request in
            let body: [String: Any] = ["error": "literal string error"]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        await assertAPIError(status: 400, message: "literal string error")

        AIRequestBuildingMockURLProtocol.handler = { request in
            let body: [String: Any] = ["message": "top-level message"]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        await assertAPIError(status: 500, message: "top-level message")

        AIRequestBuildingMockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!,
                Data("not json".utf8)
            )
        }
        await assertAPIError(status: 502, message: "The provider returned an error.")
    }

    private func assertAPIError(status: Int, message: String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await StructuredAIClient(session: mockSession()).generate(
                provider: .openAI,
                model: "gpt-test",
                apiKey: "sk-test-key",
                instructions: "Instructions.",
                input: "Input.",
                schemaName: "schema",
                schema: ["type": "object"],
                maxTokens: 100
            )
            XCTFail("A non-2xx response must be rejected.", file: file, line: line)
        } catch let error as WritingAIError {
            guard case let .api(receivedStatus, receivedMessage) = error else {
                return XCTFail("Expected api, got \(error).", file: file, line: line)
            }
            XCTAssertEqual(receivedStatus, status, file: file, line: line)
            XCTAssertEqual(receivedMessage, message, file: file, line: line)
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).", file: file, line: line)
        }
    }

    // MARK: - ManuscriptAIService

    func testDeepenMarkdownRejectsANonManuscriptPurpose() async {
        let request = makeRequest(purpose: .polish(targetGrade: 8))
        do {
            _ = try await ManuscriptAIService(session: mockSession()).deepenMarkdown(request: request, apiKey: "sk-test-key")
            XCTFail("A non-manuscript purpose must be rejected before any network call.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testDeepenMarkdownSendsTheManuscriptEditorialNotesSchemaName() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.jsonBody)
            let text = try XCTUnwrap(body["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["name"] as? String, "manuscript_editorial_notes")
            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            let required = try XCTUnwrap(schema["required"] as? [String])
            XCTAssertEqual(Set(required), Set(["summary", "markdown"]))
            return (self.okResponse(for: request), self.openAIEnvelope(text: self.manuscriptMarkdownResponseText(summary: "S", markdown: "M")))
        }

        let request = makeRequest(purpose: .manuscriptReport(kind: .fiction))
        _ = try await ManuscriptAIService(session: mockSession()).deepenMarkdown(request: request, apiKey: "sk-test-key")
    }

    func testDeepenMarkdownForwardsAnEightThousandTokenBudget() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.jsonBody)
            XCTAssertEqual(body["max_tokens"] as? Int, 8_000)
            return (self.okResponse(for: request), self.anthropicEnvelope(text: self.manuscriptMarkdownResponseText(summary: "S", markdown: "M")))
        }

        let request = makeRequest(purpose: .manuscriptBible(kind: .nonfiction), provider: .anthropic)
        _ = try await ManuscriptAIService(session: mockSession()).deepenMarkdown(request: request, apiKey: "sk-ant-test-key")
    }

    func testDeepenMarkdownDecodesAResponseWrappedInMarkdownCodeFences() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let fenced = "```json\n\(self.manuscriptMarkdownResponseText(summary: "Clean summary.", markdown: "# Notes"))\n```"
            return (self.okResponse(for: request), self.openAIEnvelope(text: fenced))
        }

        let request = makeRequest(purpose: .manuscriptReport(kind: .fiction))
        let result = try await ManuscriptAIService(session: mockSession()).deepenMarkdown(request: request, apiKey: "sk-test-key")

        XCTAssertEqual(result.summary, "Clean summary.")
        XCTAssertEqual(result.markdown, "# Notes")
    }

    func testDeepenMarkdownThrowsInvalidResponseForUnparsableJSON() async {
        AIRequestBuildingMockURLProtocol.handler = { request in
            (self.okResponse(for: request), self.openAIEnvelope(text: "Sorry, I can't help with that."))
        }

        let request = makeRequest(purpose: .manuscriptReport(kind: .fiction))
        do {
            _ = try await ManuscriptAIService(session: mockSession()).deepenMarkdown(request: request, apiKey: "sk-test-key")
            XCTFail("Unparsable model output must be rejected.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testBetaReadRejectsANonBetaReaderPurpose() async {
        let request = makeRequest(purpose: .polish(targetGrade: 8))
        do {
            _ = try await ManuscriptAIService(session: mockSession()).betaRead(
                request: request,
                profile: BetaReaderProfile.builtIns[0],
                scope: .manuscript,
                apiKey: "sk-test-key"
            )
            XCTFail("A non-beta-reader purpose must be rejected before any network call.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testBetaReadSendsTheBetaReaderFeedbackSchemaName() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.jsonBody)
            let text = try XCTUnwrap(body["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["name"] as? String, "beta_reader_feedback")
            return (
                self.okResponse(for: request),
                self.openAIEnvelope(text: self.betaReaderResponseText(summary: "S", reaction: "R", strengths: [], concerns: [], questions: []))
            )
        }

        let request = makeRequest(purpose: .betaReader(readerName: "General Reader", focus: "Pacing.", scope: .manuscript, kind: .fiction))
        _ = try await ManuscriptAIService(session: mockSession()).betaRead(
            request: request,
            profile: BetaReaderProfile.builtIns[0],
            scope: .manuscript,
            apiKey: "sk-test-key"
        )
    }

    func testBetaReadForwardsAFiveThousandTokenBudget() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.jsonBody)
            XCTAssertEqual(body["max_tokens"] as? Int, 5_000)
            return (
                self.okResponse(for: request),
                self.anthropicEnvelope(text: self.betaReaderResponseText(summary: "S", reaction: "R", strengths: [], concerns: [], questions: []))
            )
        }

        let request = makeRequest(
            purpose: .betaReader(readerName: "General Reader", focus: "Pacing.", scope: .manuscript, kind: .fiction),
            provider: .anthropic
        )
        _ = try await ManuscriptAIService(session: mockSession()).betaRead(
            request: request,
            profile: BetaReaderProfile.builtIns[0],
            scope: .manuscript,
            apiKey: "sk-ant-test-key"
        )
    }

    func testBetaReadBuildsFeedbackFromTheDecodedResponseAndSuppliedProfileAndScope() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.betaReaderResponseText(
                summary: "A brisk, confident opening.",
                reaction: "I wanted to keep reading.",
                strengths: ["Clear voice."],
                concerns: ["The midpoint drags."],
                questions: ["Why does she leave the letter unopened?"]
            )
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let reader = BetaReaderProfile.builtIns[2]
        let request = makeRequest(
            purpose: .betaReader(readerName: reader.name, focus: reader.focus, scope: .chapter, kind: .fiction),
            model: "gpt-test"
        )

        let feedback = try await ManuscriptAIService(session: mockSession()).betaRead(
            request: request,
            profile: reader,
            scope: .chapter,
            apiKey: "sk-test-key"
        )

        XCTAssertEqual(feedback.reader, reader)
        XCTAssertEqual(feedback.scope, .chapter)
        XCTAssertEqual(feedback.source, .ai(provider: "OpenAI", model: "gpt-test"))
        XCTAssertEqual(feedback.summary, "A brisk, confident opening.")
        XCTAssertEqual(feedback.reaction, "I wanted to keep reading.")
        XCTAssertEqual(feedback.strengths, ["Clear voice."])
        XCTAssertEqual(feedback.concerns, ["The midpoint drags."])
        XCTAssertEqual(feedback.questions, ["Why does she leave the letter unopened?"])
    }

    // MARK: - SystemicRevisionAIService

    func testDeepenRejectsANonSystemicRevisionPurpose() async {
        let request = makeRequest(purpose: .polish(targetGrade: 8))
        do {
            _ = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: [], apiKey: "sk-test-key")
            XCTFail("A non-systemic-revision purpose must be rejected before any network call.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error).")
            }
        } catch {
            XCTFail("Expected a WritingAIError, got \(error).")
        }
    }

    func testDeepenSendsTheSystemicRevisionFindingsSchemaName() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.jsonBody)
            let text = try XCTUnwrap(body["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["name"] as? String, "systemic_revision_findings")
            return (self.okResponse(for: request), self.openAIEnvelope(text: self.systemicRevisionResponseText(summary: "S", findings: [])))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
        _ = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: [], apiKey: "sk-test-key")
    }

    func testDeepenForwardsAnEightThousandTokenBudget() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            let body = try XCTUnwrap(request.jsonBody)
            XCTAssertEqual(body["max_tokens"] as? Int, 8_000)
            return (self.okResponse(for: request), self.anthropicEnvelope(text: self.systemicRevisionResponseText(summary: "S", findings: [])))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]), provider: .anthropic)
        _ = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: [], apiKey: "sk-ant-test-key")
    }

    func testDeepenDropsAFindingWhoseChapterPathIsNotAKnownDocument() async throws {
        let documents = [ManuscriptDocument(relativePath: "Chapter1.md", title: "Chapter One", text: "The door creaked.")]
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.systemicRevisionResponseText(summary: "S", findings: [
                self.findingJSON(pass: "lineEditing", classification: "confirmedProblem", title: "T", detail: "D", chapterPath: "Unknown.md", excerpt: "", replacement: "")
            ])
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")

        // A finding about a chapter that isn't part of this manuscript can't be an AI hallucination we
        // silently trust -- it's dropped rather than shown to the user as if it were grounded.
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testDeepenDropsAFindingWithAnUnrecognizedRevisionPass() async throws {
        let documents = [ManuscriptDocument(relativePath: "Chapter1.md", title: "Chapter One", text: "The door creaked.")]
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.systemicRevisionResponseText(summary: "S", findings: [
                self.findingJSON(pass: "not-a-real-pass", classification: "confirmedProblem", title: "T", detail: "D", chapterPath: "Chapter1.md", excerpt: "", replacement: "")
            ])
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")

        XCTAssertTrue(result.findings.isEmpty)
    }

    func testDeepenDropsAFindingWhoseExcerptDoesNotAppearInTheChapterText() async throws {
        let documents = [ManuscriptDocument(relativePath: "Chapter1.md", title: "Chapter One", text: "The door creaked. She stepped inside slowly.")]
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.systemicRevisionResponseText(summary: "S", findings: [
                self.findingJSON(pass: "lineEditing", classification: "confirmedProblem", title: "T", detail: "D", chapterPath: "Chapter1.md", excerpt: "a phrase that never appears", replacement: "")
            ])
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")

        // A quoted excerpt that isn't actually in the manuscript is exactly the kind of AI hallucination
        // this guard exists to catch: it must not become a finding pointing at nonexistent text.
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testDeepenDropsAFindingWhoseExcerptAppearsMoreThanOnceInTheChapterText() async throws {
        let documents = [ManuscriptDocument(
            relativePath: "Chapter1.md",
            title: "Chapter One",
            text: "The door creaked. She stepped inside slowly. The door creaked again as it closed."
        )]
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.systemicRevisionResponseText(summary: "S", findings: [
                self.findingJSON(pass: "lineEditing", classification: "confirmedProblem", title: "T", detail: "D", chapterPath: "Chapter1.md", excerpt: "The door creaked", replacement: "")
            ])
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")

        // An ambiguous excerpt can't be replaced safely later, so it's dropped rather than kept and
        // pointed at the wrong occurrence.
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testDeepenKeepsAFindingWithAnEmptyExcerptAndMapsAnEmptyReplacementToNil() async throws {
        let documents = [ManuscriptDocument(relativePath: "Chapter1.md", title: "Chapter One", text: "The door creaked.")]
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.systemicRevisionResponseText(summary: "S", findings: [
                self.findingJSON(pass: "pacing", classification: "authorQuestion", title: "Slow opening", detail: "Consider trimming.", chapterPath: "Chapter1.md", excerpt: "", replacement: "")
            ])
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.pacing]))
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")

        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(finding.excerpt, "")
        XCTAssertNil(finding.replacement)
    }

    func testDeepenKeepsAFindingWhoseExcerptAppearsExactlyOnce() async throws {
        let documents = [ManuscriptDocument(
            relativePath: "Chapter1.md",
            title: "Chapter One",
            text: "The door creaked. She stepped inside slowly, listening for any sound."
        )]
        AIRequestBuildingMockURLProtocol.handler = { request in
            let text = self.systemicRevisionResponseText(summary: "Overall solid.", findings: [
                self.findingJSON(
                    pass: "structure",
                    classification: "opportunity",
                    title: "Good structural beat",
                    detail: "Consider more sensory grounding here.",
                    chapterPath: "Chapter1.md",
                    excerpt: "stepped inside slowly",
                    replacement: "stepped inside, listening carefully"
                )
            ])
            return (self.okResponse(for: request), self.openAIEnvelope(text: text))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.structure]), provider: .openAI, model: "gpt-test")
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")

        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(finding.revisionPass, .structure)
        XCTAssertEqual(finding.classification, .opportunity)
        XCTAssertEqual(finding.title, "Good structural beat")
        XCTAssertEqual(finding.detail, "Consider more sensory grounding here.")
        XCTAssertEqual(finding.chapterPath, "Chapter1.md")
        XCTAssertEqual(finding.excerpt, "stepped inside slowly")
        XCTAssertEqual(finding.replacement, "stepped inside, listening carefully")
        XCTAssertEqual(finding.origin, .ai)
        XCTAssertEqual(finding.provider, "OpenAI")
        XCTAssertEqual(finding.model, "gpt-test")
    }

    func testDeepenComputesADeterministicSignatureThatChangesWithTheFindingTitle() async throws {
        let documents = [ManuscriptDocument(relativePath: "Chapter1.md", title: "Chapter One", text: "The door creaked.")]

        func signature(forTitle title: String) async throws -> String {
            AIRequestBuildingMockURLProtocol.handler = { request in
                let text = self.systemicRevisionResponseText(summary: "S", findings: [
                    self.findingJSON(pass: "lineEditing", classification: "confirmedProblem", title: title, detail: "D", chapterPath: "Chapter1.md", excerpt: "", replacement: "")
                ])
                return (self.okResponse(for: request), self.openAIEnvelope(text: text))
            }
            let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
            let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: documents, apiKey: "sk-test-key")
            return try XCTUnwrap(result.findings.first).signature
        }

        let firstRun = try await signature(forTitle: "Repeated word")
        let secondRun = try await signature(forTitle: "Repeated word")
        let differentTitle = try await signature(forTitle: "A different issue")

        XCTAssertEqual(firstRun, secondRun)
        XCTAssertNotEqual(firstRun, differentTitle)
    }

    func testDeepenReturnsTheSummaryFromTheDecodedResponse() async throws {
        AIRequestBuildingMockURLProtocol.handler = { request in
            (self.okResponse(for: request), self.openAIEnvelope(text: self.systemicRevisionResponseText(summary: "Overall solid draft.", findings: [])))
        }

        let request = makeRequest(purpose: .systemicRevision(kind: .fiction, passes: [.lineEditing]))
        let result = try await SystemicRevisionAIService(session: mockSession()).deepen(request: request, documents: [], apiKey: "sk-test-key")

        XCTAssertEqual(result.summary, "Overall solid draft.")
        XCTAssertTrue(result.findings.isEmpty)
    }

    // MARK: - Fixture helpers

    private func makeRequest(
        purpose: AIRequestPurpose,
        provider: AIProvider = .openAI,
        model: String = "test-model"
    ) -> AIRequestPreview {
        AIRequestPreview(
            purpose: purpose,
            provider: provider,
            model: model,
            primaryLabel: "Manuscript",
            primaryText: "The full manuscript text.",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: nil,
            sourceText: nil
        )
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIRequestBuildingMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func okResponse(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private func openAIEnvelope(text: String) -> Data {
        let body: [String: Any] = ["output": [["content": [["text": text]]]]]
        return try! JSONSerialization.data(withJSONObject: body) // swiftlint:disable:this force_try
    }

    private func anthropicEnvelope(text: String) -> Data {
        let body: [String: Any] = ["content": [["type": "text", "text": text]]]
        return try! JSONSerialization.data(withJSONObject: body) // swiftlint:disable:this force_try
    }

    private func ollamaEnvelope(content: String) -> Data {
        let body: [String: Any] = ["message": ["role": "assistant", "content": content]]
        return try! JSONSerialization.data(withJSONObject: body) // swiftlint:disable:this force_try
    }

    private func manuscriptMarkdownResponseText(summary: String, markdown: String) -> String {
        let body: [String: Any] = ["summary": summary, "markdown": markdown]
        return String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)! // swiftlint:disable:this force_try force_unwrapping
    }

    private func betaReaderResponseText(summary: String, reaction: String, strengths: [String], concerns: [String], questions: [String]) -> String {
        let body: [String: Any] = ["summary": summary, "reaction": reaction, "strengths": strengths, "concerns": concerns, "questions": questions]
        return String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)! // swiftlint:disable:this force_try force_unwrapping
    }

    private func findingJSON(
        pass: String,
        classification: String,
        title: String,
        detail: String,
        chapterPath: String,
        excerpt: String,
        replacement: String
    ) -> [String: String] {
        [
            "revisionPass": pass,
            "classification": classification,
            "title": title,
            "detail": detail,
            "chapterPath": chapterPath,
            "excerpt": excerpt,
            "replacement": replacement
        ]
    }

    private func systemicRevisionResponseText(summary: String, findings: [[String: String]]) -> String {
        let body: [String: Any] = ["summary": summary, "findings": findings]
        return String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)! // swiftlint:disable:this force_try force_unwrapping
    }
}

private final class AIRequestBuildingMockURLProtocol: URLProtocol {
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

    var jsonBody: [String: Any]? {
        guard let data = bodyData else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
