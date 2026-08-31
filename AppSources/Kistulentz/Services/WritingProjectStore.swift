import AppKit
import Foundation

@MainActor
final class WritingProjectStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var manifest: WritingProjectManifest?
    @Published private(set) var chapters: [ProjectChapter] = []
    @Published private(set) var selectedChapterPath: String?
    @Published private(set) var text = ""
    @Published private(set) var styleText = ""
    @Published private(set) var snapshots: [ProjectSnapshot] = []
    @Published private(set) var searchResults: [ProjectSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var manuscriptAnalysis: ManuscriptAnalysis?
    @Published private(set) var manuscriptReportText = ""
    @Published private(set) var bibleText = ""
    @Published private(set) var isAnalyzingManuscript = false
    @Published private(set) var lastBibleUpdate: BibleUpdateNotice?
    @Published private(set) var customBetaReaders: [BetaReaderProfile] = []
    @Published private(set) var outlineNodes: [OutlineNode] = []
    @Published private(set) var projectBibliography = ProjectBibliographyArchive()
    @Published private(set) var researchNotesText = ""
    @Published private(set) var revisionArchive = SystemicRevisionArchive()
    @Published private(set) var publicationArchive = PublicationArchive()
    @Published private(set) var lastMigrationResult: ProjectMigrationResult?
    @Published var recoveryRequest: ProjectRecoveryRequest?
    @Published private(set) var isScanningRevisions = false
    @Published private(set) var revisionAISummary = ""
    @Published private(set) var preservesUndoAcrossFileRelocation = false
    @Published var errorMessage: String?

    private var isDirty = false
    private var hasCapturedEditingBaseline = false
    private var saveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var manuscriptAnalysisTask: Task<Void, Never>?
    private var bibleSaveTask: Task<Void, Never>?
    private var outlineSaveTask: Task<Void, Never>?
    private var manuscriptCache = ManuscriptProjectCache()
    private var lastStructuralAnalysisAt: Date?
    private var lastStructuralAnalysisWordCount = 0
    private var hasCapturedBibleAutomaticBaseline = false
    private var hasCapturedBibleEditingBaseline = false
    private weak var projectUndoManager: UndoManager?

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
            styleText = try ProjectStyleManager.loadStyle(at: root)
            snapshots = try WritingProjectDisk.loadSnapshots(at: root)
            manuscriptReportText = try ManuscriptProjectDisk.loadReport(at: root)
            bibleText = try ManuscriptProjectDisk.loadBible(at: root)
            manuscriptCache = try ManuscriptProjectDisk.loadCache(at: root)
            lastStructuralAnalysisAt = nil
            lastStructuralAnalysisWordCount = 0
            customBetaReaders = try ManuscriptProjectDisk.loadCustomBetaReaders(at: root)
            projectBibliography = try ProjectResearchDisk.load(at: root)
            researchNotesText = try String(contentsOf: ProjectResearchDisk.notesURL(at: root), encoding: .utf8)
            revisionArchive = try SystemicRevisionDisk.load(at: root)
            publicationArchive = try PublicationDisk.load(at: root)
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
        searchTask?.cancel()
        manuscriptAnalysisTask?.cancel()
        bibleSaveTask?.cancel()
        outlineSaveTask?.cancel()
        rootURL = nil
        manifest = nil
        chapters = []
        selectedChapterPath = nil
        text = ""
        styleText = ""
        snapshots = []
        searchResults = []
        manuscriptAnalysis = nil
        manuscriptReportText = ""
        bibleText = ""
        manuscriptCache = ManuscriptProjectCache()
        lastStructuralAnalysisAt = nil
        lastStructuralAnalysisWordCount = 0
        customBetaReaders = []
        outlineNodes = []
        projectBibliography = ProjectBibliographyArchive()
        researchNotesText = ""
        revisionArchive = SystemicRevisionArchive()
        publicationArchive = PublicationArchive()
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

    func updateText(_ newValue: String) {
        guard isOpen, newValue != text else { return }
        if !hasCapturedEditingBaseline {
            createSnapshot(name: nil, reason: "Before editing")
            hasCapturedEditingBaseline = true
        }
        text = newValue
        isDirty = true
        updateSelectedChapterStatistics()
        scheduleSave()
        scheduleManuscriptAnalysis()
    }

    func saveNow() {
        saveTask?.cancel()
        guard isDirty,
              let rootURL,
              let selectedChapterPath else { return }
        do {
            try WritingProjectDisk.writeChapter(text, relativePath: selectedChapterPath, at: rootURL)
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectChapter(_ relativePath: String) {
        guard relativePath != selectedChapterPath else { return }
        do {
            saveNow()
            try loadChapter(relativePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createChapter(named name: String) {
        guard let rootURL else { return }
        do {
            saveNow()
            let path = try WritingProjectDisk.createChapter(named: name, at: rootURL)
            var updatedManifest = manifest
            updatedManifest?.chapterOrder.append(path)
            if let updatedManifest {
                try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
                manifest = updatedManifest
            }
            chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: manifest!)
            let nodeTitle = chapters.first(where: { $0.relativePath == path })?.title
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let node = OutlineNode(title: nodeTitle, kind: .chapter, relativePath: path)
            _ = OutlineTree.append(node, to: nil, in: &outlineNodes)
            saveOutlineNow()
            try loadChapter(path)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveChapters(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = chapters
        let moving = fromOffsets.sorted().map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) { reordered.remove(at: index) }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = max(0, min(reordered.count, toOffset - removedBeforeDestination))
        reordered.insert(contentsOf: moving, at: destination)
        chapters = reordered
        let flatOutline = outlineNodes.allSatisfy { $0.relativePath != nil && $0.children.isEmpty }
        if flatOutline {
            let byPath = Dictionary(uniqueKeysWithValues: outlineNodes.compactMap { node in
                node.relativePath.map { ($0, node) }
            })
            let reorderedOutline = chapters.compactMap { byPath[$0.relativePath] }
            if reorderedOutline.count == outlineNodes.count {
                outlineNodes = reorderedOutline
                saveOutlineNow()
            }
        }
        persistChapterOrder()
    }

    func saveStyle(_ value: String) {
        guard let rootURL else { return }
        do {
            try ProjectStyleManager.saveStyle(value, at: rootURL)
            styleText = value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func attachUndoManager(_ undoManager: UndoManager?) {
        projectUndoManager = undoManager
    }

    func addResearchSource(_ sourceID: UUID) {
        guard !projectBibliography.sourceIDs.contains(sourceID) else { return }
        projectBibliography.sourceIDs.append(sourceID)
        saveProjectBibliography()
    }

    func removeResearchSource(_ sourceID: UUID) {
        projectBibliography.sourceIDs.removeAll { $0 == sourceID }
        projectBibliography.quotations.removeAll { $0.sourceID == sourceID }
        projectBibliography.claimLinks.removeAll { $0.sourceID == sourceID }
        saveProjectBibliography()
    }

    func setBibliographyStyle(_ style: BibliographyStyle) {
        projectBibliography.style = style
        saveProjectBibliography()
    }

    func addQuotation(sourceID: UUID, text: String, locator: String, note: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        projectBibliography.quotations.append(ProjectResearchQuotation(
            sourceID: sourceID,
            text: clean,
            locator: locator.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        saveProjectBibliography()
    }

    func removeQuotation(_ id: UUID) {
        projectBibliography.quotations.removeAll { $0.id == id }
        saveProjectBibliography()
    }

    func addClaimLink(sourceID: UUID, chapterPath: String, excerpt: String, locator: String, note: String) {
        let clean = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        projectBibliography.claimLinks.append(ProjectClaimSourceLink(
            sourceID: sourceID,
            chapterPath: chapterPath,
            claimExcerpt: clean,
            locator: locator.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        saveProjectBibliography()
    }

    func removeClaimLink(_ id: UUID) {
        projectBibliography.claimLinks.removeAll { $0.id == id }
        saveProjectBibliography()
    }

    func updateResearchNotes(_ value: String) {
        guard let rootURL, value != researchNotesText else { return }
        researchNotesText = value
        do {
            try value.write(to: ProjectResearchDisk.notesURL(at: rootURL), atomically: true, encoding: .utf8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealResearchNotes() {
        guard let rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ProjectResearchDisk.notesURL(at: rootURL)])
    }

    func projectSources(in library: ResearchLibraryStore) -> [ResearchSource] {
        let ids = Set(projectBibliography.sourceIDs)
        return library.sources.filter { ids.contains($0.id) }
    }

    func runLocalRevisionScan(targetGrade: Int, sources: [ResearchSource]) {
        guard let rootURL, let manifest else { return }
        do {
            saveNow()
            let documents = try manuscriptDocuments()
            let manuscript = manuscriptAnalysis
            let bibliography = projectBibliography
            isScanningRevisions = true
            Task { [weak self] in
                let findings = await Task.detached(priority: .utility) {
                    SystemicRevisionAnalyzer.analyze(
                        projectName: manifest.name,
                        kind: manifest.kind,
                        documents: documents,
                        manuscript: manuscript,
                        bibliography: bibliography,
                        sources: sources,
                        targetGrade: targetGrade
                    )
                }.value
                guard let self, self.rootURL == rootURL else { return }
                self.revisionArchive = SystemicRevisionAnalyzer.reconcile(findings, with: self.revisionArchive)
                self.isScanningRevisions = false
                self.saveRevisionArchive()
            }
        } catch {
            isScanningRevisions = false
            errorMessage = error.localizedDescription
        }
    }

    func setRevisionFindingStatus(_ id: UUID, status: RevisionFindingStatus) {
        guard let index = revisionArchive.findings.firstIndex(where: { $0.id == id }) else { return }
        revisionArchive.findings[index].status = status
        saveRevisionArchive()
    }

    func addRevisionGoal(title: String, notes: String, pass: RevisionPass) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        revisionArchive.goals.append(RevisionGoal(title: clean, notes: notes, revisionPass: pass))
        saveRevisionArchive()
    }

    func toggleRevisionGoal(_ id: UUID) {
        guard let index = revisionArchive.goals.firstIndex(where: { $0.id == id }) else { return }
        revisionArchive.goals[index].isComplete.toggle()
        saveRevisionArchive()
    }

    func removeRevisionGoal(_ id: UUID) {
        revisionArchive.goals.removeAll { $0.id == id }
        saveRevisionArchive()
    }

    func revisionDocuments() throws -> [ManuscriptDocument] {
        saveNow()
        return try manuscriptDocuments()
    }

    func revisionAIContext(sources: [ResearchSource]) throws -> String {
        let documents = try revisionDocuments()
        let projectSources = sources.filter { projectBibliography.sourceIDs.contains($0.id) }
        let bibliography = CitationFormatter.bibliography(projectSources, style: projectBibliography.style)
        let manuscript = documents.map {
            "<chapter path=\"\($0.relativePath)\">\n\(String($0.text.prefix(18_000)))\n</chapter>"
        }.joined(separator: "\n\n")
        return """
        <project_research_notes>
        \(String(researchNotesText.prefix(10_000)))
        </project_research_notes>

        <project_bibliography>
        \(bibliography)
        </project_bibliography>

        <manuscript>
        \(String(manuscript.prefix(90_000)))
        </manuscript>
        """
    }

    func addAIRevisionFindings(_ findings: [SystemicRevisionFinding], summary: String) {
        var bySignature = Dictionary(uniqueKeysWithValues: revisionArchive.findings.map { ($0.signature, $0) })
        for finding in findings {
            if let previous = bySignature[finding.signature] {
                var updated = finding
                updated.id = previous.id
                updated.status = previous.status
                updated.createdAt = previous.createdAt
                bySignature[finding.signature] = updated
            } else {
                bySignature[finding.signature] = finding
            }
        }
        revisionArchive.findings = Array(bySignature.values).sorted {
            if $0.classification.rank != $1.classification.rank { return $0.classification.rank < $1.classification.rank }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        revisionAISummary = summary
        saveRevisionArchive()
    }

    func updatePublicationArchive(_ archive: PublicationArchive) {
        guard let rootURL else { return }
        do {
            try PublicationDisk.save(archive, at: rootURL)
            publicationArchive = archive
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publicationPlan(
        sources: [ResearchSource],
        profileID: UUID? = nil,
        format: PublicationExportFormat? = nil
    ) throws -> PublicationExportPlan {
        guard let rootURL, let manifest else { throw PublicationExportError.missingProject }
        saveNow()
        saveOutlineNow()
        let selectedID = profileID ?? publicationArchive.selectedProfileID
        guard let profile = publicationArchive.profiles.first(where: { $0.id == selectedID }) else {
            throw PublicationExportError.missingProfile
        }
        return PublicationPlanBuilder.build(
            projectName: manifest.name,
            root: rootURL,
            outline: outlineNodes,
            archive: publicationArchive,
            bibliography: projectBibliography,
            librarySources: sources,
            profile: profile,
            format: format ?? profile.preferredFormat,
            destinations: publicationArchive.selectedDestinations
        )
    }

    func copyPublicationCover(from url: URL) {
        guard let rootURL else { return }
        do {
            var archive = publicationArchive
            archive.metadata.coverImageRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyPrintCover(from url: URL) {
        guard let rootURL else { return }
        do {
            var archive = publicationArchive
            archive.metadata.printCoverPDFRelativePath = try PublicationDisk.copyPublicationAsset(from: url, preferredName: "print-cover", at: rootURL)
            updatePublicationArchive(archive)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recordPublicationExport(_ result: PublicationExportResult, plan: PublicationExportPlan) {
        var archive = publicationArchive
        archive.history.insert(ExportHistoryRecord(
            profileID: plan.profile.id,
            profileName: plan.profile.name,
            format: plan.format,
            outputPath: (result.packageURL ?? result.outputURL).path,
            sha256: result.sha256,
            byteCount: result.byteCount,
            warningCount: result.preflight.warnings.count
        ), at: 0)
        updatePublicationArchive(archive)
    }

    func makeRevisionChangeSet(findingIDs: Set<UUID>) throws -> RevisionChangeSet {
        try RevisionChangePlanner.changes(from: revisionArchive.findings.filter { findingIDs.contains($0.id) })
    }

    func validateRevisionChangeSet(_ set: RevisionChangeSet) -> RevisionChangeSet {
        do { return RevisionChangePlanner.validate(set, documents: try documentsByPath(for: Set(set.includedChanges.map(\.chapterPath)))) }
        catch { errorMessage = error.localizedDescription; return set }
    }

    func applyRevisionChangeSet(_ set: RevisionChangeSet) {
        guard let rootURL else { return }
        do {
            saveNow()
            let paths = Set(set.includedChanges.map(\.chapterPath))
            let before = try documentsByPath(for: paths)
            let checked = RevisionChangePlanner.validate(set, documents: before)
            guard checked.hasChanges else { throw SystemicRevisionError.noConcreteChanges }
            guard !checked.hasConflicts else { throw SystemicRevisionError.stalePassage(checked.includedChanges.first(where: { $0.conflict != nil })?.chapterPath ?? "the manuscript") }
            let after = try RevisionChangePlanner.applying(checked, to: before)

            for path in paths {
                guard let content = before[path] else { continue }
                if let snapshot = try WritingProjectDisk.createSnapshot(
                    chapterPath: path,
                    content: content,
                    name: nil,
                    reason: "Before systemic revision",
                    at: rootURL
                ) { snapshots.insert(snapshot, at: 0) }
            }
            do {
                for path in paths.sorted() {
                    guard let content = after[path] else { continue }
                    try WritingProjectDisk.writeChapter(content, relativePath: path, at: rootURL)
                }
            } catch {
                for (path, content) in before { try? WritingProjectDisk.writeChapter(content, relativePath: path, at: rootURL) }
                throw error
            }
            for id in checked.includedChanges.compactMap(\.findingID) {
                if let index = revisionArchive.findings.firstIndex(where: { $0.id == id }) { revisionArchive.findings[index].status = .resolved }
            }
            saveRevisionArchive()
            try refreshProjectAfterRevision(preferredSelection: selectedChapterPath)
            registerRevisionUndo(expected: after, replacement: before, resolvedFindingIDs: checked.includedChanges.compactMap(\.findingID), undoing: true)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func documentsByPath(for paths: Set<String>) throws -> [String: String] {
        guard let rootURL else { return [:] }
        var values: [String: String] = [:]
        let known = Set(chapters.map(\.relativePath))
        for path in paths {
            guard known.contains(path) else { throw SystemicRevisionError.stalePassage(path) }
            values[path] = try WritingProjectDisk.readChapter(path, at: rootURL)
        }
        return values
    }

    private func refreshProjectAfterRevision(preferredSelection: String?) throws {
        guard let rootURL, let manifest else { return }
        chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: manifest)
        if let preferredSelection, chapters.contains(where: { $0.relativePath == preferredSelection }) {
            try loadChapter(preferredSelection)
        }
        snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
    }

    private func registerRevisionUndo(
        expected: [String: String],
        replacement: [String: String],
        resolvedFindingIDs: [UUID],
        undoing: Bool
    ) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.performRevisionUndo(expected: expected, replacement: replacement, findingIDs: resolvedFindingIDs, undoing: undoing)
        }
        projectUndoManager?.setActionName(undoing ? "Apply Systemic Revision" : "Undo Systemic Revision")
    }

    private func performRevisionUndo(
        expected: [String: String],
        replacement: [String: String],
        findingIDs: [UUID],
        undoing: Bool
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            for (path, content) in expected {
                guard try WritingProjectDisk.readChapter(path, at: rootURL) == content else { throw SystemicRevisionError.filesChanged }
            }
            for (path, content) in replacement { try WritingProjectDisk.writeChapter(content, relativePath: path, at: rootURL) }
            for id in findingIDs {
                if let index = revisionArchive.findings.firstIndex(where: { $0.id == id }) {
                    revisionArchive.findings[index].status = undoing ? .open : .resolved
                }
            }
            saveRevisionArchive()
            try refreshProjectAfterRevision(preferredSelection: selectedChapterPath)
            registerRevisionUndo(expected: replacement, replacement: expected, resolvedFindingIDs: findingIDs, undoing: !undoing)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRevisionArchive() {
        guard let rootURL else { return }
        do { try SystemicRevisionDisk.save(revisionArchive, at: rootURL) }
        catch { errorMessage = error.localizedDescription }
    }

    private func saveProjectBibliography() {
        guard let rootURL else { return }
        do {
            try ProjectResearchDisk.save(projectBibliography, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var outlineRows: [OutlineFlatRow] { OutlineTree.flattened(outlineNodes) }

    func outlineNode(id: UUID?) -> OutlineNode? {
        guard let id else { return nil }
        return OutlineTree.node(id: id, in: outlineNodes)
    }

    func outlineChildren(of parentID: UUID?) -> [OutlineNode] {
        OutlineTree.children(of: parentID, in: outlineNodes)
    }

    func outlineWordCount(for node: OutlineNode) -> Int {
        let paths = OutlineTree.filePaths(in: [node])
        return chapters.filter { paths.contains($0.relativePath) }.reduce(0) { $0 + $1.wordCount }
    }

    func outlineWarningCount(for node: OutlineNode) -> Int {
        let paths = Set(OutlineTree.filePaths(in: [node]))
        guard let analysis = manuscriptAnalysis else { return 0 }
        return (analysis.continuityChecks + analysis.claimChecks).filter { finding in
            guard let path = finding.chapterPath else { return false }
            return paths.contains(path)
        }.count
    }

    func selectOutlineNode(_ id: UUID) {
        guard let path = outlineNode(id: id)?.relativePath else { return }
        selectChapter(path)
    }

    func updateOutlineNode(_ node: OutlineNode) {
        var updated = node
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty else { return }
        updated.metadata.modifiedAt = Date()
        guard OutlineTree.update(updated, in: &outlineNodes) else { return }
        scheduleOutlineSave()
    }

    @discardableResult
    func addOutlineItem(kind: OutlineNodeKind, title: String, parentID: UUID?) -> UUID? {
        guard let rootURL else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let parentKind = parentID.flatMap { OutlineTree.node(id: $0, in: outlineNodes)?.kind }
        guard OutlineTree.canPlace(kind, under: parentKind) else {
            errorMessage = ProjectOutlineError.invalidHierarchy.localizedDescription
            return nil
        }

        do {
            var relativePath: String?
            if kind != .part {
                let fileName = WritingProjectDisk.uniqueMarkdownFileName(for: cleanTitle, at: rootURL)
                relativePath = try WritingProjectDisk.createMarkdownFile(named: fileName, at: rootURL)
                try WritingProjectDisk.writeChapter("# \(cleanTitle)\n\n", relativePath: relativePath!, at: rootURL)
            }
            var metadata = OutlineNodeMetadata()
            metadata.status = .planned
            let node = OutlineNode(
                title: cleanTitle,
                kind: kind,
                relativePath: relativePath,
                metadata: metadata
            )
            guard OutlineTree.append(node, to: parentID, in: &outlineNodes) else {
                throw ProjectOutlineError.invalidHierarchy
            }
            saveOutlineNow()
            try syncChaptersWithOutline(preferredSelection: relativePath ?? selectedChapterPath)
            scheduleManuscriptAnalysis(immediately: true)
            return node.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func moveOutlineNode(_ nodeID: UUID, onto targetID: UUID) {
        var updated = outlineNodes
        guard OutlineTree.move(nodeID: nodeID, onto: targetID, in: &updated) else {
            errorMessage = ProjectOutlineError.invalidHierarchy.localizedDescription
            return
        }
        outlineNodes = updated
        do {
            saveOutlineNow()
            try syncChaptersWithOutline(preferredSelection: selectedChapterPath)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveOutlineNode(_ nodeID: UUID, toParent parentID: UUID?) {
        var updated = outlineNodes
        guard OutlineTree.move(nodeID: nodeID, toParent: parentID, in: &updated) else {
            errorMessage = ProjectOutlineError.invalidHierarchy.localizedDescription
            return
        }
        outlineNodes = updated
        do {
            saveOutlineNow()
            try syncChaptersWithOutline(preferredSelection: selectedChapterPath)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func suggestSynopsisLocally(for nodeID: UUID) {
        do {
            guard var node = outlineNode(id: nodeID) else { throw ProjectOutlineError.missingNode }
            node.metadata.suggestedSynopsis = OutlineSynopsisGenerator.suggest(from: try outlineText(for: nodeID))
            node.metadata.modifiedAt = Date()
            updateOutlineNode(node)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySuggestedSynopsis(_ synopsis: String, to nodeID: UUID) {
        guard var node = outlineNode(id: nodeID) else { return }
        node.metadata.suggestedSynopsis = synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        updateOutlineNode(node)
    }

    func outlineText(for nodeID: UUID) throws -> String {
        guard let node = outlineNode(id: nodeID), let rootURL else { throw ProjectOutlineError.missingNode }
        return try OutlineTree.filePaths(in: [node]).map { path in
            if path == selectedChapterPath { return text }
            return try WritingProjectDisk.readChapter(path, at: rootURL)
        }.joined(separator: "\n\n")
    }

    func outlineAIContext(for nodeID: UUID) throws -> String {
        guard let node = outlineNode(id: nodeID) else { throw ProjectOutlineError.missingNode }
        let passage = try outlineText(for: nodeID)
        return """
        <outline_item type="\(node.kind.rawValue)" title="\(node.title)">
        \(String(passage.prefix(50_000)))
        </outline_item>

        <project_bible>
        \(String(bibleText.prefix(14_000)))
        </project_bible>
        """
    }

    func fileOrganizationPlan() -> OutlineFileOrganizationPlan? {
        guard let rootURL else { return nil }
        return ProjectFileOrganizer.plan(nodes: outlineNodes, at: rootURL)
    }

    func validateFileOrganizationPlan(_ plan: OutlineFileOrganizationPlan) -> OutlineFileOrganizationPlan {
        guard let rootURL else { return plan }
        return ProjectFileOrganizer.validate(plan, at: rootURL)
    }

    func organizeFiles(_ plan: OutlineFileOrganizationPlan) {
        guard let rootURL else { return }
        saveNow()
        let checked = ProjectFileOrganizer.validate(plan, at: rootURL)
        guard checked.hasChanges, !checked.hasConflicts else {
            if checked.hasConflicts { errorMessage = "Resolve every destination conflict before organizing files." }
            return
        }

        let beforeNodes = outlineNodes
        let beforeSelection = selectedChapterPath
        do {
            for move in checked.includedMoves where move.sourcePath != move.destinationPath {
                let content = try WritingProjectDisk.readChapter(move.sourcePath, at: rootURL)
                if let snapshot = try WritingProjectDisk.createSnapshot(
                    chapterPath: move.sourcePath,
                    content: content,
                    name: nil,
                    reason: "Before organizing files",
                    at: rootURL
                ) {
                    snapshots.insert(snapshot, at: 0)
                }
            }

            let completed = try ProjectFileOrganizer.execute(checked, at: rootURL)
            var afterNodes = beforeNodes
            for move in completed {
                _ = OutlineTree.updatePath(nodeID: move.nodeID, path: move.destinationPath, in: &afterNodes)
            }
            let forwardMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.sourcePath, $0.destinationPath) })
            do {
                try WritingProjectDisk.rewriteSnapshotPaths(forwardMap, at: rootURL)
                outlineNodes = afterNodes
                saveOutlineNow()
                let selectedAfter = beforeSelection.flatMap { forwardMap[$0] } ?? beforeSelection
                preserveUndoForFileRelocation()
                try syncChaptersWithOutline(preferredSelection: selectedAfter)
                snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
                registerFileOrganizationUndo(
                    moves: completed,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes,
                    selectionBefore: beforeSelection,
                    selectionAfter: selectedAfter
                )
                scheduleManuscriptAnalysis(immediately: true)
            } catch {
                try? ProjectFileOrganizer.undo(completed, at: rootURL)
                let reverseMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.destinationPath, $0.sourcePath) })
                try? WritingProjectDisk.rewriteSnapshotPaths(reverseMap, at: rootURL)
                outlineNodes = beforeNodes
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func headingSplitPlan(for nodeID: UUID) throws -> HeadingSplitPlan {
        guard let node = outlineNode(id: nodeID), let rootURL else { throw ProjectOutlineError.missingNode }
        let markdown = node.relativePath == selectedChapterPath
            ? text
            : try WritingProjectDisk.readChapter(node.relativePath ?? "", at: rootURL)
        var plan = try HeadingSplitPlanner.plan(node: node, markdown: markdown)
        let directory = (plan.chapterPath as NSString).deletingLastPathComponent
        var reserved: Set<String> = []
        for index in plan.sections.indices {
            let base = URL(fileURLWithPath: plan.sections[index].fileName).deletingPathExtension().lastPathComponent
            var candidate = "\(base).md"
            var suffix = 2
            func relative(_ file: String) -> String {
                directory == "." ? file : "\(directory)/\(file)"
            }
            while reserved.contains(candidate.lowercased())
                || FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(relative(candidate)).path) {
                candidate = "\(base) \(suffix).md"
                suffix += 1
            }
            plan.sections[index].fileName = candidate
            reserved.insert(candidate.lowercased())
        }
        return plan
    }

    func applyHeadingSplit(_ plan: HeadingSplitPlan) {
        guard let rootURL,
              let manifest,
              let node = outlineNode(id: plan.nodeID) else { return }
        saveNow()
        let included = plan.includedSections
        guard !included.isEmpty else { return }
        let directory = (plan.chapterPath as NSString).deletingLastPathComponent
        func relativePath(_ fileName: String) -> String {
            directory == "." ? fileName : "\(directory)/\(fileName)"
        }
        do {
            var destinations: Set<String> = []
            for section in included {
                guard section.fileName == URL(fileURLWithPath: section.fileName).lastPathComponent,
                      section.fileName.lowercased().hasSuffix(".md"),
                      !section.fileName.contains(":"),
                      section.fileName.lowercased() != ".md" else {
                    throw ProjectOutlineError.invalidDestination(section.fileName)
                }
                let destination = relativePath(section.fileName)
                guard destinations.insert(destination.lowercased()).inserted else {
                    throw ProjectOutlineError.fileConflict(destination)
                }
                guard !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(destination).path) else {
                    throw ProjectOutlineError.fileConflict(destination)
                }
            }

            let original = try WritingProjectDisk.readChapter(plan.chapterPath, at: rootURL)
            if let snapshot = try WritingProjectDisk.createSnapshot(
                chapterPath: plan.chapterPath,
                content: original,
                name: nil,
                reason: "Before splitting headings",
                at: rootURL
            ) {
                snapshots.insert(snapshot, at: 0)
            }
            let beforeNodes = outlineNodes
            var afterNodes = beforeNodes
            var updatedNode = node
            let childKind: OutlineNodeKind = manifest.kind == .fiction ? .scene : .section
            let newChildren = included.map { section in
                var metadata = OutlineNodeMetadata()
                metadata.status = .drafting
                return OutlineNode(
                    title: section.title,
                    kind: childKind,
                    relativePath: relativePath(section.fileName),
                    metadata: metadata
                )
            }
            updatedNode.children.append(contentsOf: newChildren)
            guard OutlineTree.update(updatedNode, in: &afterNodes) else { throw ProjectOutlineError.missingNode }

            var createdPaths: [String] = []
            do {
                try WritingProjectDisk.writeChapter(plan.resultingChapterMarkdown, relativePath: plan.chapterPath, at: rootURL)
                for section in included {
                    let path = relativePath(section.fileName)
                    try section.markdown.write(
                        to: rootURL.appendingPathComponent(path),
                        atomically: true,
                        encoding: .utf8
                    )
                    createdPaths.append(path)
                }
                outlineNodes = afterNodes
                saveOutlineNow()
                try syncChaptersWithOutline(preferredSelection: plan.chapterPath)
                registerHeadingSplitUndo(
                    plan: plan,
                    originalMarkdown: original,
                    createdPaths: createdPaths,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes
                )
                scheduleManuscriptAnalysis(immediately: true)
            } catch {
                try? WritingProjectDisk.writeChapter(original, relativePath: plan.chapterPath, at: rootURL)
                for path in createdPaths { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(path)) }
                outlineNodes = beforeNodes
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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

    func addCustomBetaReader(name: String, focus: String, audience: BetaReaderAudience) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanFocus.isEmpty else { return }
        customBetaReaders.append(BetaReaderProfile(name: cleanName, focus: cleanFocus, audience: audience))
        saveCustomBetaReaders()
    }

    func updateCustomBetaReader(_ reader: BetaReaderProfile) {
        guard !reader.isBuiltIn,
              let index = customBetaReaders.firstIndex(where: { $0.id == reader.id }) else { return }
        customBetaReaders[index] = reader
        saveCustomBetaReaders()
    }

    func removeCustomBetaReader(_ reader: BetaReaderProfile) {
        guard !reader.isBuiltIn else { return }
        customBetaReaders.removeAll { $0.id == reader.id }
        saveCustomBetaReaders()
    }

    func documents(for scope: BetaReaderScope, selection: String?) throws -> [ManuscriptDocument] {
        switch scope {
        case .selection:
            guard let selection,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingAIError.emptySelection
            }
            return [ManuscriptDocument(relativePath: selectedChapterPath ?? "Selection", title: "Selection", text: selection)]
        case .chapter:
            return [ManuscriptDocument(
                relativePath: selectedChapterPath ?? "Chapter",
                title: selectedChapterTitle,
                text: text
            )]
        case .manuscript:
            return try manuscriptDocuments()
        }
    }

    func manuscriptAIContext() throws -> String {
        ManuscriptAnalyzer.context(
            documents: try manuscriptDocuments(),
            report: manuscriptReportText,
            bible: bibleText
        )
    }

    func applyAIReport(_ response: AIManuscriptMarkdownResponse, provider: AIProvider, model: String) {
        guard let rootURL, let manifest else { return }
        do {
            let ai = """
            ## AI-Deepened Editorial Notes

            > Generated on request with \(provider.title) · \(model). \(response.summary)

            \(response.markdown.trimmingCharacters(in: .whitespacesAndNewlines))
            """
            manuscriptCache.aiReportMarkdown = ai
            try ManuscriptProjectDisk.saveCache(manuscriptCache, at: rootURL)
            let current = (try? ManuscriptProjectDisk.loadReport(at: rootURL)) ?? manuscriptReportText
            let local = manuscriptAnalysis?.reportMarkdown ?? "## Local Analysis\n\nWaiting for the next local analysis."
            manuscriptReportText = ManuscriptReportManager.compose(
                current: current,
                localReport: local,
                aiMarkdown: ai,
                projectName: manifest.name,
                kind: manifest.kind
            )
            try ManuscriptProjectDisk.saveReport(manuscriptReportText, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyAIBible(_ response: AIManuscriptMarkdownResponse, provider: AIProvider, model: String) {
        let updated = ManuscriptBibleManager.addingAIDeepening(
            response.markdown,
            to: bibleText,
            provider: provider.title,
            model: model
        )
        applyBibleUpdate(updated, reason: "Before AI Bible deepening", summary: response.summary, forceSnapshot: true)
    }

    func recordStyleDecision(action: StyleDecisionAction, issue: WritingIssue) {
        guard let rootURL else { return }
        do {
            try ProjectStyleManager.record(action: action, issue: issue, at: rootURL)
            styleText = try ProjectStyleManager.loadStyle(at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearLearnedStylePreferences() {
        guard let rootURL else { return }
        do {
            try ProjectStyleManager.clearLearnedPreferences(at: rootURL)
            styleText = try ProjectStyleManager.loadStyle(at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSnapshot(name: String?, reason: String) {
        guard let rootURL, let selectedChapterPath else { return }
        do {
            if let snapshot = try WritingProjectDisk.createSnapshot(
                chapterPath: selectedChapterPath,
                content: text,
                name: name,
                reason: reason,
                at: rootURL
            ) {
                snapshots.insert(snapshot, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareForProgrammaticEdit(reason: String) {
        createSnapshot(name: nil, reason: reason)
        hasCapturedEditingBaseline = true
    }

    func content(for snapshot: ProjectSnapshot) throws -> String {
        guard let rootURL else { return "" }
        return try WritingProjectDisk.snapshotContent(snapshot, at: rootURL)
    }

    func currentContent(for chapterPath: String) throws -> String {
        if chapterPath == ManuscriptProjectDisk.bibleFileName { return bibleText }
        if chapterPath == ManuscriptProjectDisk.reportFileName { return manuscriptReportText }
        if chapterPath == selectedChapterPath { return text }
        guard let rootURL else { return "" }
        return try WritingProjectDisk.readChapter(chapterPath, at: rootURL)
    }

    func restore(_ snapshot: ProjectSnapshot) {
        guard let rootURL else { return }
        do {
            if snapshot.chapterPath == ManuscriptProjectDisk.bibleFileName {
                let restored = try WritingProjectDisk.snapshotContent(snapshot, at: rootURL)
                applyBibleUpdate(
                    restored,
                    reason: "Before restoring \(snapshot.name)",
                    summary: "Restored Bible snapshot “\(snapshot.name)”.",
                    forceSnapshot: true
                )
                return
            }
            if selectedChapterPath != snapshot.chapterPath {
                saveNow()
                try loadChapter(snapshot.chapterPath)
            }
            createSnapshot(name: nil, reason: "Before restoring \(snapshot.name)")
            let restored = try WritingProjectDisk.snapshotContent(snapshot, at: rootURL)
            text = restored
            isDirty = true
            hasCapturedEditingBaseline = true
            updateSelectedChapterStatistics()
            saveNow()
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rootURL else {
            searchResults = []
            isSearching = false
            return
        }
        saveNow()
        let chapterSnapshot = chapters
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                let results = try await Task.detached(priority: .userInitiated) {
                    try WritingProjectDisk.search(trimmed, chapters: chapterSnapshot, at: rootURL)
                }.value
                guard !Task.isCancelled else { return }
                self?.searchResults = results
                self?.isSearching = false
            } catch {
                self?.searchResults = []
                self?.isSearching = false
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func scheduleBibleSave() {
        bibleSaveTask?.cancel()
        bibleSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveBibleNow()
        }
    }

    private func scheduleOutlineSave() {
        outlineSaveTask?.cancel()
        outlineSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveOutlineNow()
        }
    }

    private func saveOutlineNow() {
        outlineSaveTask?.cancel()
        guard let rootURL else { return }
        do {
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: outlineNodes), at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncChaptersWithOutline(preferredSelection: String?) throws {
        guard let rootURL, var updatedManifest = manifest else { return }
        let discovered = try WritingProjectDisk.loadChapters(at: rootURL, manifest: updatedManifest)
        let discoveredPaths = discovered.map(\.relativePath)
        let known = Set(discoveredPaths)
        var ordered = OutlineTree.filePaths(in: outlineNodes).filter(known.contains)
        ordered.append(contentsOf: discoveredPaths.filter { !ordered.contains($0) })
        updatedManifest.chapterOrder = ordered
        let selection = preferredSelection.flatMap { known.contains($0) ? $0 : nil }
            ?? updatedManifest.lastOpenedChapter.flatMap { known.contains($0) ? $0 : nil }
            ?? ordered.first
        updatedManifest.lastOpenedChapter = selection
        try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
        manifest = updatedManifest
        chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: updatedManifest)
        if let selection { try loadChapter(selection) }
    }

    private func registerFileOrganizationUndo(
        moves: [OutlineFileMove],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode],
        selectionBefore: String?,
        selectionAfter: String?
    ) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.undoFileOrganization(
                moves: moves,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes,
                selectionBefore: selectionBefore,
                selectionAfter: selectionAfter
            )
        }
        projectUndoManager?.setActionName("Organize Project Files")
    }

    private func undoFileOrganization(
        moves: [OutlineFileMove],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode],
        selectionBefore: String?,
        selectionAfter: String?
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            try ProjectFileOrganizer.undo(moves, at: rootURL)
            let reverseMap = Dictionary(uniqueKeysWithValues: moves.map { ($0.destinationPath, $0.sourcePath) })
            try WritingProjectDisk.rewriteSnapshotPaths(reverseMap, at: rootURL)
            outlineNodes = beforeNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: beforeNodes), at: rootURL)
            preserveUndoForFileRelocation()
            try syncChaptersWithOutline(preferredSelection: selectionBefore)
            snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
            projectUndoManager?.registerUndo(withTarget: self) { target in
                target.redoFileOrganization(
                    moves: moves,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes,
                    selectionBefore: selectionBefore,
                    selectionAfter: selectionAfter
                )
            }
            projectUndoManager?.setActionName("Organize Project Files")
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func redoFileOrganization(
        moves: [OutlineFileMove],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode],
        selectionBefore: String?,
        selectionAfter: String?
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            let completed = try ProjectFileOrganizer.execute(OutlineFileOrganizationPlan(moves: moves), at: rootURL)
            let forwardMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.sourcePath, $0.destinationPath) })
            try WritingProjectDisk.rewriteSnapshotPaths(forwardMap, at: rootURL)
            outlineNodes = afterNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: afterNodes), at: rootURL)
            preserveUndoForFileRelocation()
            try syncChaptersWithOutline(preferredSelection: selectionAfter)
            snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
            registerFileOrganizationUndo(
                moves: moves,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes,
                selectionBefore: selectionBefore,
                selectionAfter: selectionAfter
            )
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func preserveUndoForFileRelocation() {
        preservesUndoAcrossFileRelocation = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.preservesUndoAcrossFileRelocation = false
        }
    }

    private func registerHeadingSplitUndo(
        plan: HeadingSplitPlan,
        originalMarkdown: String,
        createdPaths: [String],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode]
    ) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.undoHeadingSplit(
                plan: plan,
                originalMarkdown: originalMarkdown,
                createdPaths: createdPaths,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes
            )
        }
        projectUndoManager?.setActionName("Split Chapter Headings")
    }

    private func undoHeadingSplit(
        plan: HeadingSplitPlan,
        originalMarkdown: String,
        createdPaths: [String],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode]
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            guard try WritingProjectDisk.readChapter(plan.chapterPath, at: rootURL) == plan.resultingChapterMarkdown else {
                throw ProjectOutlineError.filesChanged
            }
            for (path, section) in zip(createdPaths, plan.includedSections) {
                guard try WritingProjectDisk.readChapter(path, at: rootURL) == section.markdown else {
                    throw ProjectOutlineError.filesChanged
                }
            }
            try WritingProjectDisk.writeChapter(originalMarkdown, relativePath: plan.chapterPath, at: rootURL)
            for path in createdPaths { try FileManager.default.removeItem(at: rootURL.appendingPathComponent(path)) }
            outlineNodes = beforeNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: beforeNodes), at: rootURL)
            try syncChaptersWithOutline(preferredSelection: plan.chapterPath)
            projectUndoManager?.registerUndo(withTarget: self) { target in
                target.redoHeadingSplit(
                    plan: plan,
                    originalMarkdown: originalMarkdown,
                    createdPaths: createdPaths,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes
                )
            }
            projectUndoManager?.setActionName("Split Chapter Headings")
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func redoHeadingSplit(
        plan: HeadingSplitPlan,
        originalMarkdown: String,
        createdPaths: [String],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode]
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            guard try WritingProjectDisk.readChapter(plan.chapterPath, at: rootURL) == originalMarkdown,
                  createdPaths.allSatisfy({ !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent($0).path) }) else {
                throw ProjectOutlineError.filesChanged
            }
            try WritingProjectDisk.writeChapter(plan.resultingChapterMarkdown, relativePath: plan.chapterPath, at: rootURL)
            for (path, section) in zip(createdPaths, plan.includedSections) {
                try section.markdown.write(to: rootURL.appendingPathComponent(path), atomically: true, encoding: .utf8)
            }
            outlineNodes = afterNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: afterNodes), at: rootURL)
            try syncChaptersWithOutline(preferredSelection: plan.chapterPath)
            registerHeadingSplitUndo(
                plan: plan,
                originalMarkdown: originalMarkdown,
                createdPaths: createdPaths,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes
            )
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleManuscriptAnalysis(immediately: Bool = false) {
        manuscriptAnalysisTask?.cancel()
        guard let rootURL, let manifest else { return }
        let chapterSnapshot = chapters
        let selectedPathSnapshot = selectedChapterPath
        let selectedTextSnapshot = text
        isAnalyzingManuscript = true
        manuscriptAnalysisTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(1_400)) }
            guard let self, !Task.isCancelled, self.rootURL == rootURL else { return }
            let loaded = await Task.detached(priority: .utility) {
                Result {
                    let documents = try Self.loadManuscriptDocuments(
                        chapters: chapterSnapshot,
                        selectedPath: selectedPathSnapshot,
                        selectedText: selectedTextSnapshot,
                        rootURL: rootURL
                    )
                    let analysis = ManuscriptAnalyzer.analyze(
                        projectName: manifest.name,
                        kind: manifest.kind,
                        documents: documents
                    )
                    let wordCount = documents.reduce(0) {
                        $0 + WritingProjectDisk.wordCount(in: $1.text)
                    }
                    return (
                        analysis: analysis,
                        wordCount: wordCount,
                        structuralSample: ManuscriptStructuralSampler.text(from: documents)
                    )
                }
            }.value
            guard !Task.isCancelled, self.rootURL == rootURL else { return }
            var analysis: ManuscriptAnalysis
            let wordCount: Int
            let structuralSample: String
            switch loaded {
            case .success(let work):
                analysis = work.analysis
                wordCount = work.wordCount
                structuralSample = work.structuralSample
            case .failure(let error):
                self.isAnalyzingManuscript = false
                self.errorMessage = error.localizedDescription
                return
            }
            // Publish the native result before waiting for an optional external
            // language pack to start. A cold Benepar worker can take seconds,
            // but it must never delay Kistulentz's built-in report and Bible.
            self.applyLocalManuscriptAnalysis(analysis)
            guard !Task.isCancelled, self.rootURL == rootURL else { return }
            let shouldRefreshStructure = immediately
                || self.manuscriptCache.structuralProfile == nil
                || abs(wordCount - self.lastStructuralAnalysisWordCount) >= 100
                || self.lastStructuralAnalysisAt.map { Date().timeIntervalSince($0) >= 60 } != false
            if shouldRefreshStructure,
               let structure = await BeneparService.shared.analyzeIfAvailable(
                   text: structuralSample,
                   maximumSentences: 160,
                   includeIssues: false
               ) {
                guard !Task.isCancelled, self.rootURL == rootURL else { return }
                self.manuscriptCache.structuralProfile = structure.metrics
                self.lastStructuralAnalysisAt = Date()
                self.lastStructuralAnalysisWordCount = wordCount
            }
            if let structure = self.manuscriptCache.structuralProfile {
                analysis = ManuscriptAnalyzer.addingStructuralProfile(structure, to: analysis)
                guard !Task.isCancelled, self.rootURL == rootURL else { return }
                self.applyLocalManuscriptAnalysis(analysis)
            }
        }
    }

    private func applyLocalManuscriptAnalysis(_ analysis: ManuscriptAnalysis) {
        guard let rootURL, let manifest else { return }
        do {
            manuscriptAnalysis = analysis
            let currentReport = (try? ManuscriptProjectDisk.loadReport(at: rootURL)) ?? manuscriptReportText
            manuscriptReportText = ManuscriptReportManager.compose(
                current: currentReport,
                localReport: analysis.reportMarkdown,
                aiMarkdown: manuscriptCache.aiReportMarkdown,
                projectName: manifest.name,
                kind: manifest.kind
            )
            try ManuscriptProjectDisk.saveReport(manuscriptReportText, at: rootURL)

            let updatedBible = ManuscriptBibleManager.merge(
                currentBible: bibleText,
                previousGeneratedBlock: manuscriptCache.generatedBibleBlock,
                newGeneratedBlock: analysis.generatedBibleBlock,
                projectName: manifest.name,
                kind: manifest.kind
            )
            if updatedBible != bibleText {
                applyBibleUpdate(
                    updatedBible,
                    reason: "Before automatic Bible update",
                    summary: bibleChangeSummary(old: bibleText, new: updatedBible),
                    forceSnapshot: !hasCapturedBibleAutomaticBaseline
                )
                hasCapturedBibleAutomaticBaseline = true
            }
            manuscriptCache.generatedBibleBlock = analysis.generatedBibleBlock
            try ManuscriptProjectDisk.saveCache(manuscriptCache, at: rootURL)
            isAnalyzingManuscript = false
        } catch {
            isAnalyzingManuscript = false
            errorMessage = error.localizedDescription
        }
    }

    private func manuscriptDocuments() throws -> [ManuscriptDocument] {
        guard let rootURL else { return [] }
        return try Self.loadManuscriptDocuments(
            chapters: chapters,
            selectedPath: selectedChapterPath,
            selectedText: text,
            rootURL: rootURL
        )
    }

    nonisolated private static func loadManuscriptDocuments(
        chapters: [ProjectChapter],
        selectedPath: String?,
        selectedText: String,
        rootURL: URL
    ) throws -> [ManuscriptDocument] {
        try chapters.map { chapter in
            let chapterText = chapter.relativePath == selectedPath
                ? selectedText
                : try WritingProjectDisk.readChapter(chapter.relativePath, at: rootURL)
            return ManuscriptDocument(
                relativePath: chapter.relativePath,
                title: chapter.title,
                text: chapterText
            )
        }
    }

    private func applyBibleUpdate(
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

    private func bibleChangeSummary(old: String, new: String) -> String {
        let diff = RevisionDiff.compare(old: old, new: new)
        let added = diff.filter { $0.kind == .added }.count
        let removed = diff.filter { $0.kind == .removed }.count
        if removed == 0 { return "Added \(added) locally tracked Bible \(added == 1 ? "line" : "lines")." }
        return "Updated the local Bible: \(added) added and \(removed) removed \(added + removed == 1 ? "line" : "lines")."
    }

    private func saveCustomBetaReaders() {
        guard let rootURL else { return }
        do {
            try ManuscriptProjectDisk.saveCustomBetaReaders(customBetaReaders, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadChapter(_ relativePath: String?) throws {
        guard let relativePath,
              chapters.contains(where: { $0.relativePath == relativePath }),
              let rootURL else { throw WritingProjectError.noMarkdownFiles }
        selectedChapterPath = relativePath
        text = try WritingProjectDisk.readChapter(relativePath, at: rootURL)
        isDirty = false
        hasCapturedEditingBaseline = false
        var updatedManifest = manifest
        updatedManifest?.lastOpenedChapter = relativePath
        if let updatedManifest {
            try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
            manifest = updatedManifest
        }
    }

    private func updateSelectedChapterStatistics() {
        guard let selectedChapterPath,
              let index = chapters.firstIndex(where: { $0.relativePath == selectedChapterPath }) else { return }
        let fallback = URL(fileURLWithPath: selectedChapterPath).deletingPathExtension().lastPathComponent
        let title = text.components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") })?
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(2)
        chapters[index] = ProjectChapter(
            relativePath: selectedChapterPath,
            title: title.map(String.init).flatMap { $0.isEmpty ? nil : $0 } ?? fallback,
            wordCount: WritingProjectDisk.wordCount(in: text)
        )
    }

    private func persistChapterOrder() {
        guard let rootURL else { return }
        do {
            var updatedManifest = manifest
            updatedManifest?.chapterOrder = chapters.map(\.relativePath)
            if let updatedManifest {
                try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
                manifest = updatedManifest
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
