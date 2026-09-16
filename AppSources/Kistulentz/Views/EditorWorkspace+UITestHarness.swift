import AppKit
import Foundation

// Split out of EditorWorkspace.swift: the UI-test-only harness (project auto-open, file-backed
// edit commands, undo-status reporting) that never runs in a real launch. Entirely
// #if UI_TEST_HOST, matching the original.
#if UI_TEST_HOST
extension EditorWorkspace {
    func configureUITestProjectIfNeeded() {
        guard !didConfigureUITestProject else { return }
        didConfigureUITestProject = true
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["KISTULENTZ_UI_TEST_PROJECT_PATH"], !path.isEmpty else { return }

        let root = URL(fileURLWithPath: path, isDirectory: true)
        do {
            if WritingProjectDisk.hasManifest(at: root) {
                try projectStore.openProject(at: root)
            } else {
                let name = environment["KISTULENTZ_UI_TEST_PROJECT_NAME"]
                    ?? root.lastPathComponent
                let kind = WritingProjectKind(
                    rawValue: environment["KISTULENTZ_UI_TEST_PROJECT_KIND"] ?? "fiction"
                ) ?? .fiction
                try projectStore.prepareAndOpenProject(at: root, name: name, kind: kind)
            }
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }

    /// XCTest's macOS keyboard driver can select text in the AppKit editor while silently
    /// discarding replacement characters on headless runners. This file-backed command is
    /// available only in the UI-test host and exercises the same binding, undo coordinator,
    /// autosave, and recovery pipeline as a user edit without changing production launches.
    @MainActor
    func monitorUITestEditCommand() async {
        guard let path = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_EDIT_COMMAND_PATH"] else {
            return
        }
        let url = URL(fileURLWithPath: path)
        while !Task.isCancelled {
            if let replacement = try? String(contentsOf: url, encoding: .utf8),
               !replacement.isEmpty,
               replacement != lastUITestEditCommand {
                lastUITestEditCommand = replacement
                if replacement == "__KISTULENTZ_UNDO__" {
                    uiTestEditUndoManager.undo()
                    continue
                }
                if replacement == "__KISTULENTZ_REDO__" {
                    uiTestEditUndoManager.redo()
                    continue
                }
                if replacement == "__KISTULENTZ_PROJECT_UNDO__" {
                    let manager = suppliedUndoManager ?? projectStore.projectUndoManager
                    manager?.undo()
                    writeUITestProjectUndoStatus(manager: manager, operation: "undo")
                    continue
                }
                if replacement == "__KISTULENTZ_PROJECT_REDO__" {
                    let manager = suppliedUndoManager ?? projectStore.projectUndoManager
                    manager?.redo()
                    writeUITestProjectUndoStatus(manager: manager, operation: "redo")
                    continue
                }
                if replacement == "__KISTULENTZ_PROJECT_UNDO_STATUS__" {
                    let manager = suppliedUndoManager ?? projectStore.projectUndoManager
                    writeUITestProjectUndoStatus(manager: manager, operation: "status")
                    continue
                }
                if projectStore.isOpen {
                    projectStore.prepareForProgrammaticEdit(reason: "Before UI test edit")
                }
                projectStore.attachUndoManager(uiTestEditUndoManager)
                undoCoordinator.replaceText(
                    with: replacement,
                    binding: activeTextBinding,
                    undoManager: uiTestEditUndoManager,
                    actionName: "UI Test Edit"
                )
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func writeUITestProjectUndoStatus(manager: UndoManager?, operation: String) {
        guard let statusPath = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_STATUS_PATH"] else {
            return
        }
        let status = [
            "operation=\(operation)",
            "manager=\(manager != nil)",
            "canUndo=\(manager?.canUndo == true)",
            "canRedo=\(manager?.canRedo == true)",
            "undoName=\(manager?.undoActionName ?? "none")",
            "redoName=\(manager?.redoActionName ?? "none")",
            "grouping=\(manager?.groupingLevel ?? -1)",
            "error=\(projectStore.errorMessage ?? "none")",
            "text=\(projectStore.text.debugDescription)"
        ].joined(separator: ",")
        try? status.write(
            to: URL(fileURLWithPath: statusPath),
            atomically: true,
            encoding: .utf8
        )
    }
}
#endif
