import XCTest
@testable import Kistulentz

/// Tests for `LaunchDocumentSettlement.decide`, the pure decision logic behind
/// `KistulentzAppDelegate.settleLaunchDocuments()`. See that type's doc comment for why this
/// exists as a pure function: it's the part of the window-management fix (duplicate windows on
/// launch, the system panel on a zero-window quit) that can be exercised without a real
/// `NSDocumentController` and window server.
final class LaunchDocumentSettlementTests: XCTestCase {
    private typealias Document = LaunchDocumentSettlement.Document

    func testOpensAnUntitledDocumentWhenNothingIsOpen() {
        XCTAssertEqual(LaunchDocumentSettlement.decide(for: []), .openUntitledDocument)
    }

    func testDoesNothingWithOnlyASingleBlankDocument() {
        let documents = [Document(hasFileURL: false, isEdited: false)]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .doNothing)
    }

    func testDoesNothingWithOnlyASingleRealDocument() {
        let documents = [Document(hasFileURL: true, isEdited: false)]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .doNothing)
    }

    /// The core duplicate-window regression this fix protects: a real, restored document
    /// alongside a blank one that showed up independently (this delegate's own doc comment
    /// records that SwiftUI's `DocumentGroup` can create one on its own during launch).
    func testClosesBlankDocumentsWhenARealDocumentIsAlsoOpen() {
        let documents = [
            Document(hasFileURL: true, isEdited: false),
            Document(hasFileURL: false, isEdited: false)
        ]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .closeBlankDocuments)
    }

    /// A blank document the writer has actually started typing into is not the redundant
    /// launch-time artifact this exists to clean up -- never close real, in-progress work.
    func testDoesNotCloseAnEditedBlankDocumentEvenAlongsideARealOne() {
        let documents = [
            Document(hasFileURL: true, isEdited: false),
            Document(hasFileURL: false, isEdited: true)
        ]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .doNothing)
    }

    func testDoesNothingWithTwoRealDocumentsAndNoBlankOne() {
        let documents = [
            Document(hasFileURL: true, isEdited: false),
            Document(hasFileURL: true, isEdited: false)
        ]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .doNothing)
    }

    func testDoesNothingWithTwoUntouchedBlankDocumentsAndNoRealOne() {
        let documents = [
            Document(hasFileURL: false, isEdited: false),
            Document(hasFileURL: false, isEdited: false)
        ]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .doNothing)
    }

    func testClosesMultipleBlankDocumentsAlongsideARealOne() {
        let documents = [
            Document(hasFileURL: true, isEdited: false),
            Document(hasFileURL: false, isEdited: false),
            Document(hasFileURL: false, isEdited: false)
        ]

        XCTAssertEqual(LaunchDocumentSettlement.decide(for: documents), .closeBlankDocuments)
    }
}
