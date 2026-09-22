import Foundation
import XCTest
@testable import Kistulentz

final class CraftExampleServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testCandidatesFlattensBooksAndCapsByCharacterBudget() {
        let bookA = book(title: "Harbor", excerptTexts: [String(repeating: "a", count: 900), String(repeating: "b", count: 900)])
        let bookB = book(title: "Lighthouse", excerptTexts: [String(repeating: "c", count: 900)])

        let all = CraftExampleService.candidates(from: [bookA, bookB], maximumCount: 20, maximumCharacters: 100_000)
        XCTAssertEqual(all.count, 3)

        let capped = CraftExampleService.candidates(from: [bookA, bookB], maximumCount: 20, maximumCharacters: 1_000)
        XCTAssertEqual(capped.count, 1, "budget under one excerpt's size should still keep the first one, not zero")
    }

    func testCandidatesReturnsEmptyForNoBooksOrNoExcerpts() {
        XCTAssertEqual(CraftExampleService.candidates(from: []), [])
        let empty = book(title: "Empty", excerptTexts: [])
        XCTAssertEqual(CraftExampleService.candidates(from: [empty]), [])
    }

    func testReferenceContextIncludesEveryCandidateIDAndText() {
        let source = book(title: "Harbor", author: "A. Writer", excerptTexts: ["A quiet, exact sentence."])
        let candidates = CraftExampleService.candidates(from: [source])

        let context = CraftExampleService.referenceContext(for: candidates)

        XCTAssertTrue(context.contains(candidates[0].excerpt.id.uuidString))
        XCTAssertTrue(context.contains("A quiet, exact sentence."))
        XCTAssertTrue(context.contains("A. Writer"))
        XCTAssertTrue(context.contains("Harbor"))
    }

    func testReferenceContextIsEmptyForNoCandidates() {
        XCTAssertEqual(CraftExampleService.referenceContext(for: []), "")
    }

    func testPrimaryTextIncludesTheFlaggedExcerptAndCategory() {
        let issue = WritingIssue(
            category: .adverb,
            range: NSRange(location: 0, length: 10),
            excerpt: "walked quickly",
            message: "Consider a stronger verb."
        )

        let text = CraftExampleService.primaryText(for: issue)

        XCTAssertTrue(text.contains("walked quickly"))
        XCTAssertTrue(text.contains(IssueCategory.adverb.title))
    }

    func testFindThrowsForAMismatchedPurposeWithoutTouchingTheNetwork() async {
        let service = mockedService()
        MockURLProtocol.handler = { _ in
            XCTFail("find(request:) must not reach the network for a non-craftExample purpose")
            throw URLError(.badServerResponse)
        }
        let request = AIRequestPreview(
            purpose: .referenceDeepening,
            provider: .openAI,
            model: "gpt-test",
            primaryLabel: "Flagged passage",
            primaryText: "irrelevant",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false
        )

        do {
            _ = try await service.find(request: request, candidates: [], apiKey: nil)
            XCTFail("expected an error for a non-craftExample purpose")
        } catch {
            // Any thrown error is acceptable; the assertion is in the handler never firing.
        }
    }

    func testFindReturnsNotFoundImmediatelyWhenThereAreNoCandidatesWithoutTouchingTheNetwork() async throws {
        let service = mockedService()
        MockURLProtocol.handler = { _ in
            XCTFail("find(request:) must not reach the network when there are no candidates")
            throw URLError(.badServerResponse)
        }

        let lookup = try await service.find(request: craftExampleRequest(), candidates: [], apiKey: nil)

        XCTAssertEqual(lookup, .notFound)
    }

    // MARK: - Grounding: the AI selects by id; Kistulentz decides what that resolves to

    func testFindResolvesAKnownExcerptIDToAFoundResult() async throws {
        let source = book(title: "Harbor", author: "A. Writer", excerptTexts: ["A quiet, exact sentence."])
        let candidates = CraftExampleService.candidates(from: [source])
        let realID = candidates[0].excerpt.id.uuidString

        let service = mockedService()
        respond(withJSON: #"{"excerptId":"\#(realID)","whyItWorks":"It names the actor and cuts the filler."}"#)

        let lookup = try await service.find(request: craftExampleRequest(), candidates: candidates, apiKey: "test-key")

        guard case .found(_, let bookTitle, let bookAuthor, let excerpt, let whyItWorks) = lookup else {
            return XCTFail("expected .found, got \(lookup)")
        }
        XCTAssertEqual(bookTitle, "Harbor")
        XCTAssertEqual(bookAuthor, "A. Writer")
        XCTAssertEqual(excerpt.text, "A quiet, exact sentence.")
        XCTAssertEqual(whyItWorks, "It names the actor and cuts the filler.")
    }

    func testFindTreatsAnIDNotInTheCandidateListAsNotFound() async throws {
        let source = book(title: "Harbor", excerptTexts: ["A quiet, exact sentence."])
        let candidates = CraftExampleService.candidates(from: [source])

        let service = mockedService()
        // A syntactically valid UUID that simply isn't one of the candidates sent -- the
        // grounding check must reject this exactly as it would a hallucinated id, since a
        // matching real UUID's *value* is what's verified, not just its shape.
        respond(withJSON: #"{"excerptId":"\#(UUID().uuidString)","whyItWorks":"Sounds plausible."}"#)

        let lookup = try await service.find(request: craftExampleRequest(), candidates: candidates, apiKey: "test-key")

        XCTAssertEqual(lookup, .notFound)
    }

    func testFindTreatsNullExcerptIDAsNotFound() async throws {
        let source = book(title: "Harbor", excerptTexts: ["A quiet, exact sentence."])
        let candidates = CraftExampleService.candidates(from: [source])

        let service = mockedService()
        respond(withJSON: #"{"excerptId":null,"whyItWorks":null}"#)

        let lookup = try await service.find(request: craftExampleRequest(), candidates: candidates, apiKey: "test-key")

        XCTAssertEqual(lookup, .notFound)
    }

    func testFindTreatsAnEmptyWhyItWorksAsNotFoundEvenWithAValidID() async throws {
        let source = book(title: "Harbor", excerptTexts: ["A quiet, exact sentence."])
        let candidates = CraftExampleService.candidates(from: [source])
        let realID = candidates[0].excerpt.id.uuidString

        let service = mockedService()
        respond(withJSON: #"{"excerptId":"\#(realID)","whyItWorks":"   "}"#)

        let lookup = try await service.find(request: craftExampleRequest(), candidates: candidates, apiKey: "test-key")

        XCTAssertEqual(lookup, .notFound)
    }

    // MARK: - Mock networking

    private func mockedService() -> CraftExampleService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return CraftExampleService(session: URLSession(configuration: configuration))
    }

    private func craftExampleRequest(category: IssueCategory = .adverb) -> AIRequestPreview {
        AIRequestPreview(
            purpose: .craftExample(category: category),
            provider: .openAI,
            model: "gpt-test",
            primaryLabel: "Flagged passage",
            primaryText: "walked quickly",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: "irrelevant for this test",
            includesReferenceContext: true
        )
    }

    private func respond(withJSON schemaJSON: String) {
        MockURLProtocol.handler = { request in
            let response: [String: Any] = [
                "output": [[
                    "content": [["type": "output_text", "text": schemaJSON]]
                ]]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }
    }

    // MARK: - Fixtures

    private func book(
        title: String,
        author: String = "Author",
        excerptTexts: [String]
    ) -> LibraryBook {
        LibraryBook(
            id: UUID(),
            sourcePath: "/Books/\(title).epub",
            sourceFileSize: 1,
            sourceModifiedAt: nil,
            title: title,
            author: author,
            genres: [],
            profile: ReferenceProfile(
                wordCount: 1_000,
                chapterCount: 1,
                gradeLevel: 8,
                averageSentenceWords: 12,
                sentenceVariation: 3,
                averageParagraphWords: 60,
                dialogueRatio: 0.2,
                firstPersonRatio: 0,
                thirdPersonRatio: 1,
                tempo: "measured",
                voice: "third-person",
                tone: [],
                vocabulary: [],
                characters: []
            ),
            excerpts: excerptTexts.enumerated().map { index, text in
                LibraryExcerpt(section: "Chapter \(index + 1)", purpose: "Test purpose", text: text)
            },
            importedAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let handlerStorage = LockedTestValue<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { handlerStorage.value }
        set { handlerStorage.value = newValue }
    }

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
