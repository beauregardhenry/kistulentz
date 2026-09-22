import XCTest
@testable import Kistulentz

final class StringExtensionsTests: XCTestCase {
    func testStringNonEmptyReturnsNilForEmptyAndSelfOtherwise() {
        XCTAssertNil("".nonEmpty)
        XCTAssertEqual("hi".nonEmpty, "hi")
    }

    func testOptionalStringNonEmptyOrFallsBackForNilOrEmptyAndKeepsARealValue() {
        let missing: String? = nil
        let blank: String? = ""
        let present: String? = "hi"

        XCTAssertEqual(missing.nonEmpty(or: "fallback"), "fallback")
        XCTAssertEqual(blank.nonEmpty(or: "fallback"), "fallback")
        XCTAssertEqual(present.nonEmpty(or: "fallback"), "hi")
    }
}
