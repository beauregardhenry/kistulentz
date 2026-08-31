import Foundation
import XCTest
@testable import Kistulentz

final class ProviderConnectionTesterTests: XCTestCase {
    override func tearDown() {
        ProviderTestURLProtocol.handler = nil
        super.tearDown()
    }

    func testOpenAITestUsesModelMetadataAndNeverSendsWriting() async throws {
        let tester = ProviderConnectionTester(session: makeSession())
        ProviderTestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models/gpt-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.httpBodyStream)
            return try Self.response(request, status: 200, json: ["id": "gpt-test"])
        }

        let result = try await tester.test(provider: .openAI, model: "gpt-test", apiKey: "secret")
        XCTAssertEqual(result.model, "gpt-test")
        XCTAssertEqual(result.provider, .openAI)
    }

    func testAnthropicTestUsesRequiredHeadersAndNoBody() async throws {
        let tester = ProviderConnectionTester(session: makeSession())
        ProviderTestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models/claude-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.httpBodyStream)
            return try Self.response(request, status: 200, json: ["id": "claude-test"])
        }

        let result = try await tester.test(provider: .anthropic, model: "claude-test", apiKey: "secret")
        XCTAssertEqual(result.provider, .anthropic)
    }

    func testRejectedKeyReturnsActionableError() async {
        let tester = ProviderConnectionTester(session: makeSession())
        ProviderTestURLProtocol.handler = { request in
            try Self.response(request, status: 401, json: ["error": ["message": "no"]])
        }

        do {
            _ = try await tester.test(provider: .openAI, model: "gpt-test", apiKey: "bad")
            XCTFail("Expected the key to be rejected")
        } catch let error as ProviderConnectionError {
            XCTAssertEqual(error, .rejected(provider: "OpenAI", status: 401))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOllamaRequiresSelectedModelToBeInstalled() async {
        let tester = ProviderConnectionTester(session: makeSession())
        ProviderTestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/tags")
            return try Self.response(request, status: 200, json: [
                "models": [["name": "other:latest", "model": "other:latest"]]
            ])
        }

        do {
            _ = try await tester.test(provider: .ollama, model: "wanted:latest", apiKey: nil)
            XCTFail("Expected unavailable model")
        } catch let error as ProviderConnectionError {
            XCTAssertEqual(error, .modelUnavailable("wanted:latest"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        json: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        ))
        return (response, try JSONSerialization.data(withJSONObject: json))
    }
}

private final class ProviderTestURLProtocol: URLProtocol {
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
