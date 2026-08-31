import Foundation
import XCTest
@testable import Kistulentz

@MainActor
final class NativeWritingServiceTests: XCTestCase {
    func testAppleWritingServicesReturnActionableEnglishCorrections() throws {
        let text = "This sentnce is unclear. These is wrong."

        let issues = NativeWritingService.issues(in: text)
        let spelling = try XCTUnwrap(issues.first {
            $0.category == .spelling && $0.excerpt == "sentnce"
        })
        XCTAssertEqual(spelling.source, .system)
        XCTAssertEqual(spelling.replacement?.lowercased(), "sentence")

        let grammar = try XCTUnwrap(issues.first {
            $0.category == .grammar && $0.excerpt == "is"
        })
        XCTAssertEqual(grammar.source, .system)
        XCTAssertEqual(grammar.replacement, "are")
        XCTAssertFalse(grammar.message.isEmpty)
    }

    func testAppleWritingServicesIgnoreMarkdownProtectedContent() {
        let text = """
        `sentnce` stays literal.

        ```text
        sentnce
        ```

        [sentnce](https://example.com/sentnce) stays a link.

        This sentnce should be corrected.
        """

        let issues = NativeWritingService.issues(in: text)
        let spellingRanges = issues
            .filter { $0.category == .spelling && $0.excerpt == "sentnce" }
            .map(\.range)

        XCTAssertEqual(spellingRanges.count, 1)
        XCTAssertEqual(
            spellingRanges.first,
            (text as NSString).range(of: "sentnce", options: .backwards)
        )
    }

    func testEmptyTextReturnsImmediately() {
        XCTAssertTrue(NativeWritingService.issues(in: "").isEmpty)
    }
}
