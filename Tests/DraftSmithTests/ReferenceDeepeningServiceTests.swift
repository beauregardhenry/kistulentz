import Foundation
import XCTest
@testable import DraftSmith

final class ReferenceDeepeningServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testOpenAIDeepeningUsesStructuredStatelessRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = ReferenceDeepeningService(session: session)
        let chapter = ReferenceChapter(id: 0, title: "Opening", text: "Elara carried the lantern across the silent courtyard.")
        let reference = EPUBReference(
            fileName: "sample.epub",
            title: "Sample",
            author: "Writer",
            subjects: ["Fantasy"],
            chapters: [chapter],
            profile: ReferenceProfileBuilder.build(chapters: [chapter])
        )

        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let data = try XCTUnwrap(request.bodyData)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["store"] as? Bool, false)
            let text = try XCTUnwrap(body["text"] as? [String: Any])
            let format = try XCTUnwrap(text["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")

            let result = """
            {"summary":"Clear summary","style":"Direct","voice":"Third person","tone":"Measured","vocabulary":"Concrete","characterContinuity":"Consistent","tempo":"Steady","techniques":["Varied sentences"],"suggestedGenres":["Fantasy"]}
            """
            let response: [String: Any] = [
                "output": [[
                    "content": [["type": "output_text", "text": result]]
                ]]
            ]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, try JSONSerialization.data(withJSONObject: response))
        }

        let result = try await service.deepen(
            reference: reference,
            provider: .openAI,
            model: "test-model",
            apiKey: "test-key"
        )

        XCTAssertEqual(result.summary, "Clear summary")
        XCTAssertEqual(result.suggestedGenres, ["Fantasy"])
    }
}

private final class MockURLProtocol: URLProtocol {
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
