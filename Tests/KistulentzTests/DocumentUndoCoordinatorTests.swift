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

    func testBackgroundTextViewUpdatesDoNotCreateUndoActions() {
        let undoManager = UndoManager()

        UndoRegistrationGuard.perform(on: undoManager) {
            undoManager.registerUndo(withTarget: self) { _ in }
        }

        XCTAssertFalse(undoManager.canUndo)
        XCTAssertTrue(undoManager.isUndoRegistrationEnabled)
    }

    func testTextViewCoordinatorDoesNotWriteBindingsDuringSwiftUIUpdates() {
        var text = "Original"
        var selection = NSRange(location: 0, length: 0)
        var textWrites = 0
        var selectionWrites = 0
        let coordinator = MarkdownTextView.Coordinator(
            text: Binding(
                get: { text },
                set: { text = $0; textWrites += 1 }
            ),
            selection: Binding(
                get: { selection },
                set: { selection = $0; selectionWrites += 1 }
            )
        )
        let textView = NSTextView()
        textView.string = "Updated by SwiftUI"
        textView.setSelectedRange(NSRange(location: 3, length: 2))

        coordinator.isApplyingSwiftUIUpdate = true
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )

        XCTAssertEqual(text, "Original")
        XCTAssertEqual(selection, NSRange(location: 0, length: 0))
        XCTAssertEqual(textWrites, 0)
        XCTAssertEqual(selectionWrites, 0)
    }
}
