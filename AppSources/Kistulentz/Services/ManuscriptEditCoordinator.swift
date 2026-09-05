import Foundation

/// Owns "an edit just landed" and fans it out, in order, to autosave,
/// manuscript analysis, automatic Bible updates, and snapshotting.
///
/// This is the coordinator described in `WritingProjectStore`'s "Why the
/// other six concerns stay combined" note: an edit cascades through
/// manuscript analysis into an automatic Bible rewrite plus a snapshot, and a
/// file move / revision-apply / restore all snapshot too. Every call site
/// used to hand-roll its own version of that sequence (its own debounce
/// task, its own baseline flag, its own ordering); this type is the one
/// place that owns the sequencing and the debounce/baseline bookkeeping
/// behind it, so `WritingProjectStore` and its extensions only ever say
/// *that* an edit landed, not *how* to sequence what follows.
///
/// Manual, out-of-band Bible updates (AI deepening, restoring a Bible
/// snapshot) deliberately bypass this coordinator entirely and call
/// `WritingProjectStore.applyBibleUpdate` directly — they always force their
/// own snapshot and carry their own summary, so there is nothing for the
/// coordinator to sequence.
@MainActor
final class ManuscriptEditCoordinator {

    enum Trigger {
        /// Interactive typing in the selected chapter: debounced save,
        /// debounced analysis.
        case liveTyping
        /// Interactive typing in the Bible tab: debounced save only —
        /// manual Bible edits don't re-trigger manuscript analysis.
        case bibleEditing
        /// A programmatic mutation (chapter created, snapshot restored,
        /// revision applied/undone, documents imported) that has already
        /// snapshotted whatever it needed — via `prepareForProgrammaticEdit`
        /// or its own per-file snapshotting: save and analyze immediately,
        /// no additional snapshot.
        case externalChange
        /// A project just opened (or was just prepared/imported into):
        /// reset all baselines, analyze immediately, no snapshot.
        case projectOpened
    }

    weak var host: ManuscriptEditPipelineHost?

    private var saveTask: Task<Void, Never>?
    private var bibleSaveTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var hasCapturedEditingBaseline = false
    private var hasCapturedBibleEditingBaseline = false
    private var hasCapturedBibleAutomaticBaseline = false

    func editLanded(_ trigger: Trigger) {
        switch trigger {
        case .liveTyping:
            if !hasCapturedEditingBaseline {
                host?.snapshotBeforeEdit(reason: "Before editing")
                hasCapturedEditingBaseline = true
            }
            scheduleChapterSave(debounced: true)
            scheduleAnalysis(debounced: true)

        case .bibleEditing:
            if !hasCapturedBibleEditingBaseline {
                host?.snapshotBibleBeforeEdit(reason: "Before editing Bible")
                hasCapturedBibleEditingBaseline = true
            }
            scheduleBibleSave(debounced: true)

        case .externalChange:
            scheduleChapterSave(debounced: false)
            scheduleAnalysis(debounced: false)

        case .projectOpened:
            reset()
            scheduleAnalysis(debounced: false)
        }
    }

    /// Snapshots unconditionally and marks the chapter-editing baseline as
    /// captured, so a following `.liveTyping`/`.externalChange` edit doesn't
    /// snapshot again. For a caller that is about to mutate the chapter text
    /// directly (a restore) rather than going through interactive typing.
    func prepareForProgrammaticEdit(reason: String) {
        host?.snapshotBeforeEdit(reason: reason)
        hasCapturedEditingBaseline = true
    }

    /// Call when the selected chapter changes, so the next edit re-snapshots.
    func resetEditingBaseline() {
        hasCapturedEditingBaseline = false
    }

    func resetBibleEditingBaseline() {
        hasCapturedBibleEditingBaseline = false
    }

    /// Cancels in-flight work and clears all baseline bookkeeping. Called
    /// from `closeProject`, and internally at the start of `.projectOpened`.
    func reset() {
        saveTask?.cancel()
        bibleSaveTask?.cancel()
        analysisTask?.cancel()
        saveTask = nil
        bibleSaveTask = nil
        analysisTask = nil
        hasCapturedEditingBaseline = false
        hasCapturedBibleEditingBaseline = false
        hasCapturedBibleAutomaticBaseline = false
    }

    private func scheduleChapterSave(debounced: Bool) {
        saveTask?.cancel()
        guard debounced else { host?.persistCurrentChapter(); return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.host?.persistCurrentChapter()
        }
    }

    private func scheduleBibleSave(debounced: Bool) {
        bibleSaveTask?.cancel()
        guard debounced else { host?.persistBible(); return }
        bibleSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.host?.persistBible()
        }
    }

    private func scheduleAnalysis(debounced: Bool) {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            if debounced { try? await Task.sleep(for: .milliseconds(1_400)) }
            guard !Task.isCancelled, let self else { return }
            let bibleChanged = await self.host?.runManuscriptAnalysis(
                forceBibleSnapshotIfChanged: !self.hasCapturedBibleAutomaticBaseline
            ) ?? false
            if bibleChanged { self.hasCapturedBibleAutomaticBaseline = true }
        }
    }
}

/// The narrow surface `ManuscriptEditCoordinator` needs from
/// `WritingProjectStore` to sequence an edit's fan-out. Kept separate from
/// the store's full API so the coordinator can be tested against a fake host.
@MainActor
protocol ManuscriptEditPipelineHost: AnyObject {
    func snapshotBeforeEdit(reason: String)
    func snapshotBibleBeforeEdit(reason: String)
    func persistCurrentChapter()
    func persistBible()

    /// Runs local (and, when warranted, structural) manuscript analysis,
    /// applies the resulting report, and applies any resulting Bible update —
    /// forcing a snapshot before that update only when
    /// `forceBibleSnapshotIfChanged` is true. Returns whether a Bible update
    /// was actually applied, so the coordinator only advances its
    /// once-per-session Bible-snapshot bookkeeping on a real change.
    @discardableResult
    func runManuscriptAnalysis(forceBibleSnapshotIfChanged: Bool) async -> Bool
}
