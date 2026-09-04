import AppKit
import Foundation

@MainActor
final class WritingProjectStore: ObservableObject {

    // MARK: - Published State

    @Published private(set) var rootURL: URL?
    @Published var manifest: WritingProjectManifest?
    @Published var chapters: [ProjectChapter] = []
    @Published var selectedChapterPath: String?
    @Published var text = ""
    @Published var snapshots: [ProjectSnapshot] = []
    @Published var manuscriptAnalysis: ManuscriptAnalysis?
    @Published var manuscriptReportText = ""
    @Published var bibleText = ""
    @Published var isAnalyzingManuscript = false
    @Published var lastBibleUpdate: BibleUpdateNotice?
    @Published var outlineNodes: [OutlineNode] = []
    @Published var revisionArchive = SystemicRevisionArchive()
    @Published private(set) var lastMigrationResult: ProjectMigrationResult?
    @Published var recoveryRequest: ProjectRecoveryRequest?
    @Published var isScanningRevisions = false
    @Published var revisionAISummary = ""
    @Published var preservesUndoAcrossFileRelocation = false
    @Published var errorMessage: String?

    // MARK: - Private State
    //
    // These are declared `internal` (module-visible), not `private`, because
    // `openProject`/`closeProject` below load and reset every one of them, while
    // the section that owns each piece of day-to-day state
    // (WritingProjectStore+ChaptersEditing.swift, +Outline.swift, +Bible.swift,
    // +ManuscriptReport.swift, +Snapshots.swift) lives in its own file. Swift's
    // `private` is file-scoped, so state used from more than one file must be
    // at least `internal` -- still only ever touched by WritingProjectStore's
    // own methods, nothing else in the module reaches in.

    var isDirty = false
    var hasCapturedEditingBaseline = false
    var saveTask: Task<Void, Never>?
    var manuscriptAnalysisTask: Task<Void, Never>?
    var bibleSaveTask: Task<Void, Never>?
    var outlineSaveTask: Task<Void, Never>?
    var manuscriptCache = ManuscriptProjectCache()
    var lastStructuralAnalysisAt: Date?
    var lastStructuralAnalysisWordCount = 0
    var hasCapturedBibleAutomaticBaseline = false
    var hasCapturedBibleEditingBaseline = false
    weak var projectUndoManager: UndoManager?

    // MARK: - Why the other six concerns stay combined
    //
    // ChaptersEditing, Outline, SystemicRevision, ManuscriptReport, Bible, and
    // Snapshots are still part of this class, and that's deliberate, not
    // leftover work. Unlike the 5 sub-stores below, these six are coupled by
    // real production behavior, not just file layout: an edit cascades
    // through manuscript analysis into an automatic Bible rewrite plus a
    // snapshot; a file move or a revision-apply both snapshot; autosave
    // triggers a snapshot. Splitting these into independent stores without
    // first designing something that owns "an edit just landed" and fans it
    // out to analysis/Bible/snapshot in the right order would just relocate
    // the coupling, not remove it -- that coordinator design is the real next
    // step here, not a mechanical file split. (The 5 below were split first
    // specifically because they verified as NOT having this problem.)

    // MARK: - Sub-stores
    //
    // These 5 concerns were verified to be genuinely independent -- each
    // touches nothing outside its own state beyond the project root -- and
    // were extracted into their own ObservableObject types so views observing
    // one of them don't re-render on unrelated store activity. Each holds a
    // weak back-reference to this store (wired in `init()` below) for the
    // handful of things it still legitimately needs: `rootURL`, occasionally
    // `manifest`/`outlineNodes`, and the shared `errorMessage` sink.

    let researchStore = ProjectResearchStore()
    let publicationStore = PublicationStore()
    let betaReadersStore = BetaReadersStore()
    let styleLearningStore = StyleLearningStore()
    let searchStore = SearchStore()

    init() {
        researchStore.core = self
        publicationStore.core = self
        publicationStore.research = researchStore
        betaReadersStore.core = self
        styleLearningStore.core = self
        searchStore.core = self
    }

    // MARK: - Computed Properties

    var isOpen: Bool { rootURL != nil && manifest != nil }

    var projectName: String { manifest?.name ?? "Project" }

    var projectKind: WritingProjectKind? { manifest?.kind }

    var selectedFileURL: URL? {
        guard let rootURL, let selectedChapterPath else { return nil }
        return rootURL.appendingPathComponent(selectedChapterPath)
    }

    var selectedChapterTitle: String {
        chapters.first(where: { $0.relativePath == selectedChapterPath })?.title ?? "No chapter"
    }

    var combinedWordCount: Int { chapters.reduce(0) { $0 + $1.wordCount } }

    var hasUnsavedChapterChanges: Bool { isDirty }

    var reportFileURL: URL? { rootURL.map(ManuscriptProjectDisk.reportURL) }

    var bibleFileURL: URL? { rootURL.map(ManuscriptProjectDisk.bibleURL) }

    // MARK: - Project Lifecycle

    func createProject(in parent: URL, name: String, kind: WritingProjectKind) throws {
        let root = try WritingProjectDisk.createProject(in: parent, name: name, kind: kind)
        try openProject(at: root)
    }

    func importProjectDocuments(
        _ conversions: [ProjectImportConversion],
        decisions: [UUID: DocumentTrackedChangeDecision]
    ) throws -> ProjectImportWriteResult {
        guard let rootURL else { throw ProjectImportError.noCurrentProject }
        saveNow()
        guard !isDirty else { throw ProjectImportError.currentProjectSaveFailed }
        try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: outlineNodes), at: rootURL)
        let result = try ProjectImportOutputService.addToProject(
            conversions,
            decisions: decisions,
            root: rootURL
        )
        manifest = try WritingProjectDisk.loadManifest(at: rootURL)
        outlineNodes = try ProjectOutlineDisk.load(at: rootURL).nodes
        try syncChaptersWithOutline(preferredSelection: result.selectedPath)
        scheduleManuscriptAnalysis(immediately: true)
        return result
    }

    func prepareAndOpenProject(at root: URL, name: String, kind: WritingProjectKind) throws {
        try WritingProjectDisk.prepareExistingProject(at: root, name: name, kind: kind)
        try openProject(at: root)
    }

    func openProject(at root: URL) throws {
        do {
            saveNow()
            saveBibleNow()
            saveOutlineNow()
            manuscriptAnalysisTask?.cancel()
            bibleSaveTask?.cancel()
            outlineSaveTask?.cancel()
            recoveryRequest = nil
            lastMigrationResult = try ProjectCompatibilityManager.prepareForOpen(at: root)
            let loadedManifest = try WritingProjectDisk.loadManifest(at: root)
            try ManuscriptProjectDisk.prepare(at: root, projectName: loadedManifest.name, kind: loadedManifest.kind)
            try ProjectOutlineDisk.prepare(at: root, manifest: loadedManifest)
            try ProjectResearchDisk.prepare(at: root, projectName: loadedManifest.name)
            try SystemicRevisionDisk.prepare(at: root)
            try PublicationDisk.prepare(at: root, projectName: loadedManifest.name, projectKind: loadedManifest.kind)
            let loadedChapters = try WritingProjectDisk.loadChapters(at: root, manifest: loadedManifest)
            let loadedOutline = ProjectOutlineDisk.reconcile(
                try ProjectOutlineDisk.load(at: root),
                chapterPaths: loadedChapters.map(\.relativePath),
                projectKind: loadedManifest.kind,
                root: root
            )
            rootURL = root.standardizedFileURL
            manifest = loadedManifest
            chapters = loadedChapters
            outlineNodes = loadedOutline.nodes
            try ProjectOutlineDisk.save(loadedOutline, at: root)
            try styleLearningStore.load(at: root)
            snapshots = try WritingProjectDisk.loadSnapshots(at: root)
            manuscriptReportText = try ManuscriptProjectDisk.loadReport(at: root)
            bibleText = try ManuscriptProjectDisk.loadBible(at: root)
            manuscriptCache = try ManuscriptProjectDisk.loadCache(at: root)
            lastStructuralAnalysisAt = nil
            lastStructuralAnalysisWordCount = 0
            try betaReadersStore.load(at: root)
            try researchStore.load(at: root)
            revisionArchive = try SystemicRevisionDisk.load(at: root)
            try publicationStore.load(at: root)
            manuscriptAnalysis = nil
            lastBibleUpdate = nil
            hasCapturedBibleAutomaticBaseline = false
            hasCapturedBibleEditingBaseline = false
            try syncChaptersWithOutline(preferredSelection: loadedManifest.lastOpenedChapter)
            scheduleManuscriptAnalysis(immediately: true)
            do {
                _ = try ProjectCompatibilityManager.captureKnownGoodSnapshot(at: root)
            } catch {
                errorMessage = "The project opened, but Kistulentz could not update its recovery snapshot: \(error.localizedDescription)"
            }
        } catch {
            if shouldOfferRecovery(for: error) {
                let backups = (try? ProjectCompatibilityManager.availableBackups(at: root)) ?? []
                if !backups.isEmpty {
                    recoveryRequest = ProjectRecoveryRequest(
                        rootURL: root.standardizedFileURL,
                        failureDescription: error.localizedDescription,
                        backups: backups
                    )
                }
            }
            throw error
        }
    }

    func restoreProject(from backup: ProjectMetadataBackup) throws {
        guard let request = recoveryRequest else {
            throw ProjectCompatibilityError.missingBackup(backup.directoryName)
        }
        try ProjectCompatibilityManager.restore(backup, at: request.rootURL)
        recoveryRequest = nil
        try openProject(at: request.rootURL)
    }

    func dismissRecovery() {
        recoveryRequest = nil
    }

    func closeProject() {
        saveNow()
        saveBibleNow()
        saveOutlineNow()
        saveTask?.cancel()
        searchStore.reset()
        manuscriptAnalysisTask?.cancel()
        bibleSaveTask?.cancel()
        outlineSaveTask?.cancel()
        rootURL = nil
        manifest = nil
        chapters = []
        selectedChapterPath = nil
        text = ""
        styleLearningStore.reset()
        snapshots = []
        manuscriptAnalysis = nil
        manuscriptReportText = ""
        bibleText = ""
        manuscriptCache = ManuscriptProjectCache()
        lastStructuralAnalysisAt = nil
        lastStructuralAnalysisWordCount = 0
        betaReadersStore.reset()
        outlineNodes = []
        researchStore.reset()
        revisionArchive = SystemicRevisionArchive()
        publicationStore.reset()
        lastMigrationResult = nil
        recoveryRequest = nil
        isScanningRevisions = false
        revisionAISummary = ""
        lastBibleUpdate = nil
        isAnalyzingManuscript = false
        isDirty = false
        hasCapturedEditingBaseline = false
        preservesUndoAcrossFileRelocation = false
    }

    private func shouldOfferRecovery(for error: Error) -> Bool {
        if let compatibilityError = error as? ProjectCompatibilityError,
           case .unsupportedProjectVersion = compatibilityError {
            return false
        }
        return true
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        projectUndoManager = undoManager
    }
}
