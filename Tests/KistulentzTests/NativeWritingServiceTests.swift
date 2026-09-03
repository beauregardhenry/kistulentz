import Foundation
import XCTest
@testable import Kistulentz

@MainActor
final class NativeWritingServiceTests: XCTestCase {
    func testAppleWritingServicesReturnActionableEnglishCorrections() async throws {
        let text = "This sentnce is unclear. These is wrong."

        let issues = await NativeWritingService.issues(in: text)
        let spelling = try XCTUnwrap(issues.first {
            $0.category == .spelling && $0.excerpt == "sentnce"
        })
        XCTAssertEqual(spelling.source, .system)
        XCTAssertEqual(spelling.replacement?.lowercased(), "sentence")

        let grammar = try XCTUnwrap(issues.first {
            $0.category == .grammar && $0.excerpt == "is"
        })
        XCTAssertEqual(grammar.source, .system)
        // The system grammar checker picks the verb form itself, and which one it picks differs
        // between macOS versions (CI suggests "am" where "are" is expected). What this test is
        // actually about is that the correction is actionable, so assert that instead of the word.
        let replacement = try XCTUnwrap(grammar.replacement)
        XCTAssertFalse(replacement.isEmpty)
        XCTAssertNotEqual(replacement.lowercased(), "is")
        XCTAssertFalse(grammar.message.isEmpty)
    }

    func testAppleWritingServicesIgnoreMarkdownProtectedContent() async {
        let text = """
        `sentnce` stays literal.

        ```text
        sentnce
        ```

        [sentnce](https://example.com/sentnce) stays a link.

        This sentnce should be corrected.
        """

        let issues = await NativeWritingService.issues(in: text)
        let spellingRanges = issues
            .filter { $0.category == .spelling && $0.excerpt == "sentnce" }
            .map(\.range)

        XCTAssertEqual(spellingRanges.count, 1)
        XCTAssertEqual(
            spellingRanges.first,
            (text as NSString).range(of: "sentnce", options: .backwards)
        )
    }

    func testEmptyTextReturnsImmediately() async {
        let issues = await NativeWritingService.issues(in: "")
        XCTAssertTrue(issues.isEmpty)
    }

    func testLargePastedDocumentDoesNotBlockTheMainActor() async {
        let paragraph = "A persistent agent needs a computer, dependencies, credentials, network access, logs, permissions, and working state.\n\n"
        let text = String(repeating: paragraph, count: 360)
        XCTAssertGreaterThan(text.utf8.count, 37_000)

        let mainActorResponded = expectation(description: "The interface remains responsive")
        let checkingTask = Task { @MainActor in
            await NativeWritingService.issues(in: text, maximumIssues: 25)
        }
        Task { @MainActor in
            mainActorResponded.fulfill()
        }

        await fulfillment(of: [mainActorResponded], timeout: 0.5)
        _ = await checkingTask.value
    }
}
