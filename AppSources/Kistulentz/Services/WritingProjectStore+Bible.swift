import Foundation

extension WritingProjectStore {

    // MARK: - Bible

    func updateBibleText(_ value: String) {
        guard isOpen, value != bibleText else { return }
        if !hasCapturedBibleEditingBaseline {
            createBibleSnapshot(content: bibleText, reason: "Before editing Bible")
            hasCapturedBibleEditingBaseline = true
        }
        bibleText = value
        scheduleBibleSave()
    }

    func saveBibleNow() {
        bibleSaveTask?.cancel()
        guard let rootURL else { return }
        do {
            try ManuscriptProjectDisk.saveBible(bibleText, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyBibleUpdate(
        _ updated: String,
        reason: String,
        summary: String,
        forceSnapshot: Bool
    ) {
        guard updated != bibleText else { return }
        let previous = bibleText
        if forceSnapshot { createBibleSnapshot(content: previous, reason: reason) }
        registerBibleUndo(previous: previous, updated: updated, actionName: "Update Project Bible")
        bibleText = updated
        saveBibleNow()
        lastBibleUpdate = BibleUpdateNotice(
            createdAt: Date(),
            summary: summary,
            previousText: previous,
            updatedText: updated,
            diff: RevisionDiff.compare(old: previous, new: updated)
        )
    }

    private func registerBibleUndo(previous: String, updated: String, actionName: String) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.restoreBibleForUndo(previous, inverse: updated, actionName: actionName)
        }
        projectUndoManager?.setActionName(actionName)
    }

    private func restoreBibleForUndo(_ value: String, inverse: String, actionName: String) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.restoreBibleForUndo(inverse, inverse: value, actionName: actionName)
        }
        projectUndoManager?.setActionName(actionName)
        let previous = bibleText
        bibleText = value
        saveBibleNow()
        lastBibleUpdate = BibleUpdateNotice(
            createdAt: Date(),
            summary: "Restored the previous Bible text with Undo.",
            previousText: previous,
            updatedText: value,
            diff: RevisionDiff.compare(old: previous, new: value)
        )
    }

    private func createBibleSnapshot(content: String, reason: String) {
        guard let rootURL else { return }
        do {
            if let snapshot = try WritingProjectDisk.createSnapshot(
                chapterPath: ManuscriptProjectDisk.bibleFileName,
                content: content,
                name: nil,
                reason: reason,
                at: rootURL
            ) {
                snapshots.insert(snapshot, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bibleChangeSummary(old: String, new: String) -> String {
        let diff = RevisionDiff.compare(old: old, new: new)
        let added = diff.filter { $0.kind == .added }.count
        let removed = diff.filter { $0.kind == .removed }.count
        if removed == 0 { return "Added \(added) locally tracked Bible \(added == 1 ? "line" : "lines")." }
        return "Updated the local Bible: \(added) added and \(removed) removed \(added + removed == 1 ? "line" : "lines")."
    }

    private func scheduleBibleSave() {
        bibleSaveTask?.cancel()
        bibleSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveBibleNow()
        }
    }
}
