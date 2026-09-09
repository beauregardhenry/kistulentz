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
    var outlineSaveTask: Task<Void, Never>?
    var manuscriptCache = ManuscriptProjectCache()
    var lastStructuralAnalysisAt: Date?
    var lastStructuralAnalysisWordCount = 0
    weak var projectUndoManager: UndoManager?

    // MARK: - Why the other six concerns stay combined
    //
    // ChaptersEditing, Outline, SystemicRevision, ManuscriptReport, Bible, and
    // Snapshots are still part of this class, and that's deliberate, not
    // leftover work. Unlike the 5 sub-stores below, these six are coupled by
    // real production behavior, not just file layout: an edit cascades
    // through manuscript analysis into an automatic Bible rewrite plus a
    // snapshot; a file move or a revision-apply both snapshot; autosave
    // triggers a snapshot. That cascade's sequencing and debounce/baseline
    // bookkeeping now lives in `editCoordinator` (ManuscriptEditCoordinator),
    // which is what actually made this class's job smaller -- but the six
    // extensions still all read and write the same @Published, MainActor
    // state below (text, bibleText, chapters, snapshots, ...), which is the
    // remaining reason they stay one class rather than independent stores.
    // (The 5 below were split first specifically because they verified as
    // NOT having this problem.)

    let editCoordinator = ManuscriptEditCoordinator()

    // MARK: - Sub-stores
    //
    // These 5 concerns receive only the project capabilities they require.
    // Explicit dependencies avoid hidden parent-store coupling and allow each
    // failure path to be tested without constructing the entire editor.

    lazy var researchStore = ProjectResearchStore(
        projectRoot: { [weak self] in self?.rootURL },
        reportError: { [weak self] error in self?.errorMessage = error.localizedDescription }
    )
    lazy var publicationStore = PublicationStore(
        projectRoot: { [weak self] in self?.rootURL },
        projectManifest: { [weak self] in self?.manifest },
        projectOutline: { [weak self] in self?.outlineNodes ?? [] },
        bibliography: { [weak self] in
            self?.researchStore.projectBibliography ?? ProjectBibliographyArchive()
        },
        saveCurrentDocument: { [weak self] in self?.saveNow() },
        saveProjectOutline: { [weak self] in self?.saveOutlineNow() },
        reportError: { [weak self] error in self?.errorMessage = error.localizedDescription }
    )
    lazy var betaReadersStore = BetaReadersStore(
        projectRoot: { [weak self] in self?.rootURL },
        currentChapter: { [weak self] in
            guard let self else { return nil }
            return (self.selectedChapterPath, self.selectedChapterTitle, self.text)
        },
        manuscriptProvider: { [weak self] in try self?.manuscriptDocuments() ?? [] },
        reportError: { [weak self] error in self?.errorMessage = error.localizedDescription }
    )
    lazy var styleLearningStore = StyleLearningStore(
        projectRoot: { [weak self] in self?.rootURL },
        reportError: { [weak self] error in self?.errorMessage = error.localizedDescription }
    )
    lazy var searchStore = SearchStore(
        projectRoot: { [weak self] in self?.rootURL },
        chapters: { [weak self] in self?.chapters ?? [] },
        saveCurrentDocument: { [weak self] in self?.saveNow() },
        reportError: { [weak self] error in self?.errorMessage = error.localizedDescription }
    )

    init() {
        editCoordinator.host = self
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
        editCoordinator.editLanded(.externalChange)
        return result
    }

    func prepareAndOpenProject(at root: URL, name: String, kind: WritingProjectKind) throws {
        try WritingProjectDisk.prepareExistingProject(at: root, name: name, kind: kind)
        try openProject(at: root)
    }

    func openProject(at root: URL) throws {
        saveNow()
        guard !isDirty else { throw WritingProjectError.unsavedCurrentProject }
        saveBibleNow()
        saveOutlineNow()
        do {
            let loaded = try WritingProjectLoader.load(at: root)
            install(loaded)
            do {
                _ = try ProjectCompatibilityManager.captureKnownGoodSnapshot(at: loaded.rootURL)
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

    private func install(_ loaded: LoadedWritingProject) {
        editCoordinator.reset()
        outlineSaveTask?.cancel()
        recoveryRequest = nil
        searchStore.reset()

        rootURL = loaded.rootURL
        lastMigrationResult = loaded.migrationResult
        manifest = loaded.manifest
        chapters = loaded.chapters
        selectedChapterPath = loaded.selectedChapterPath
        text = loaded.text
        outlineNodes = loaded.outlineNodes
        styleLearningStore.replaceContents(
            styleText: loaded.styleText,
            decisions: loaded.styleDecisions
        )
        snapshots = loaded.snapshots
        manuscriptReportText = loaded.manuscriptReportText
        bibleText = loaded.bibleText
        manuscriptCache = loaded.manuscriptCache
        betaReadersStore.replaceContents(loaded.customBetaReaders)
        researchStore.replaceContents(
            bibliography: loaded.projectBibliography,
            notesText: loaded.researchNotesText
        )
        revisionArchive = loaded.revisionArchive
        publicationStore.replaceContents(loaded.publicationArchive)

        lastStructuralAnalysisAt = nil
        lastStructuralAnalysisWordCount = 0
        manuscriptAnalysis = nil
        lastBibleUpdate = nil
        isScanningRevisions = false
        revisionAISummary = ""
        isAnalyzingManuscript = false
        isDirty = false
        preservesUndoAcrossFileRelocation = false
        errorMessage = nil
        editCoordinator.editLanded(.projectOpened)
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
        editCoordinator.reset()
        searchStore.reset()
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
