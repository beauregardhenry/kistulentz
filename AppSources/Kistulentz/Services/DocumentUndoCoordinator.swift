import Foundation
import SwiftUI

@MainActor
final class DocumentUndoCoordinator: ObservableObject {
    func replaceText(
        with newText: String,
        binding: Binding<String>,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let oldText = binding.wrappedValue
        guard oldText != newText else { return }

        undoManager?.registerUndo(withTarget: self) { coordinator in
            coordinator.replaceText(
                with: oldText,
                binding: binding,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
        binding.wrappedValue = newText
    }
}
