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
    @Published var errorMessage: String?

    private var isDirty = false
    private var hasCapturedEditingBaseline = false
    private var saveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var manuscriptAnalysisTask: Task<Void, Never>?
    private var bibleSaveTask: Task<Void, Never>?
    private var manuscriptCache = ManuscriptProjectCache()
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

    var reportFileURL: URL? { rootURL.map(ManuscriptProjectDisk.reportURL) }
    var bibleFileURL: URL? { rootURL.map(ManuscriptProjectDisk.bibleURL) }

    func createProject(in parent: URL, name: String, kind: WritingProjectKind) throws {
        let root = try WritingProjectDisk.createProject(in: parent, name: name, kind: kind)
        try openProject(at: root)
    }

    func prepareAndOpenProject(at root: URL, name: String, kind: WritingProjectKind) throws {
        try WritingProjectDisk.prepareExistingProject(at: root, name: name, kind: kind)
        try openProject(at: root)
    }

    func openProject(at root: URL) throws {
        saveNow()
        saveBibleNow()
        manuscriptAnalysisTask?.cancel()
        bibleSaveTask?.cancel()
        let loadedManifest = try WritingProjectDisk.loadManifest(at: root)
        try ManuscriptProjectDisk.prepare(at: root, projectName: loadedManifest.name, kind: loadedManifest.kind)
        let loadedChapters = try WritingProjectDisk.loadChapters(at: root, manifest: loadedManifest)
        rootURL = root.standardizedFileURL
        manifest = loadedManifest
        chapters = loadedChapters
        styleText = try ProjectStyleManager.loadStyle(at: root)
        snapshots = try WritingProjectDisk.loadSnapshots(at: root)
        manuscriptReportText = try ManuscriptProjectDisk.loadReport(at: root)
        bibleText = try ManuscriptProjectDisk.loadBible(at: root)
        manuscriptCache = try ManuscriptProjectDisk.loadCache(at: root)
        customBetaReaders = try ManuscriptProjectDisk.loadCustomBetaReaders(at: root)
        manuscriptAnalysis = nil
        lastBibleUpdate = nil
        hasCapturedBibleAutomaticBaseline = false
        hasCapturedBibleEditingBaseline = false
        let selection = loadedManifest.lastOpenedChapter.flatMap { path in
            loadedChapters.contains(where: { $0.relativePath == path }) ? path : nil
        } ?? loadedChapters.first?.relativePath
        try loadChapter(selection)
        scheduleManuscriptAnalysis(immediately: true)
    }

    func closeProject() {
        saveNow()
        saveBibleNow()
        saveTask?.cancel()
        searchTask?.cancel()
        manuscriptAnalysisTask?.cancel()
        bibleSaveTask?.cancel()
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
        customBetaReaders = []
        lastBibleUpdate = nil
        isAnalyzingManuscript = false
        isDirty = false
        hasCapturedEditingBaseline = false
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

    private func scheduleManuscriptAnalysis(immediately: Bool = false) {
        manuscriptAnalysisTask?.cancel()
        guard let rootURL, let manifest else { return }
        let documents: [ManuscriptDocument]
        do {
            documents = try manuscriptDocuments()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isAnalyzingManuscript = true
        manuscriptAnalysisTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(1_400)) }
            guard !Task.isCancelled else { return }
            let analysis = await Task.detached(priority: .utility) {
                ManuscriptAnalyzer.analyze(
                    projectName: manifest.name,
                    kind: manifest.kind,
                    documents: documents
                )
            }.value
            guard !Task.isCancelled, self?.rootURL == rootURL else { return }
            self?.applyLocalManuscriptAnalysis(analysis)
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
        return try chapters.map { chapter in
            let chapterText = chapter.relativePath == selectedChapterPath
                ? text
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
