import SwiftUI
import XCTest
@testable import Kistulentz

@MainActor
final class DocumentUndoCoordinatorTests: XCTestCase {
    func testProgrammaticReplacementRegistersUndoAndRedo() {
        var text = "Original"
        let binding = Binding<String>(
            get: { text },
            set: { text = $0 }
        )
        let undoManager = UndoManager()
        let coordinator = DocumentUndoCoordinator()

        coordinator.replaceText(
            with: "Revised",
            binding: binding,
            undoManager: undoManager,
            actionName: "Accept Suggestion"
        )
        XCTAssertEqual(text, "Revised")

        undoManager.undo()
        XCTAssertEqual(text, "Original")

        undoManager.redo()
        XCTAssertEqual(text, "Revised")
    }
}
