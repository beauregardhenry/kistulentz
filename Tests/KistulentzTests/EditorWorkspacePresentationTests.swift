import XCTest
@testable import Kistulentz

final class EditorWorkspacePresentationTests: XCTestCase {
    @MainActor
    func testPresentingAnotherSheetReplacesTheCurrentSheet() {
        let presentation = EditorWorkspacePresentation()

        presentation.present(.projectPolish)
        presentation.present(.revisionHistory)

        XCTAssertEqual(presentation.activeSheet, .revisionHistory)
        XCTAssertFalse(presentation.isPresenting(.projectPolish))
        XCTAssertTrue(presentation.isPresenting(.revisionHistory))
    }

    @MainActor
    func testStaleDismissalCannotDismissANewerSheet() {
        let presentation = EditorWorkspacePresentation()
        let polishBinding = presentation.binding(for: .projectPolish)

        polishBinding.wrappedValue = true
        presentation.present(.publishExport)
        polishBinding.wrappedValue = false

        XCTAssertEqual(presentation.activeSheet, .publishExport)
    }

    @MainActor
    func testActiveSheetBindingDismissesItsOwnSheet() {
        let presentation = EditorWorkspacePresentation()
        let binding = presentation.binding(for: .draftRecovery)

        binding.wrappedValue = true
        XCTAssertTrue(binding.wrappedValue)
        binding.wrappedValue = false

        XCTAssertNil(presentation.activeSheet)
        XCTAssertFalse(binding.wrappedValue)
    }
}
