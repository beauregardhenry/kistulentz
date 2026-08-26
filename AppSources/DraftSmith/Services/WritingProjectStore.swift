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
    @Published var errorMessage: String?

    private var isDirty = false
    private var hasCapturedEditingBaseline = false
    private var saveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

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
        let loadedManifest = try WritingProjectDisk.loadManifest(at: root)
        let loadedChapters = try WritingProjectDisk.loadChapters(at: root, manifest: loadedManifest)
        rootURL = root.standardizedFileURL
        manifest = loadedManifest
        chapters = loadedChapters
        styleText = try ProjectStyleManager.loadStyle(at: root)
        snapshots = try WritingProjectDisk.loadSnapshots(at: root)
        let selection = loadedManifest.lastOpenedChapter.flatMap { path in
            loadedChapters.contains(where: { $0.relativePath == path }) ? path : nil
        } ?? loadedChapters.first?.relativePath
        try loadChapter(selection)
    }

    func closeProject() {
        saveNow()
        saveTask?.cancel()
        searchTask?.cancel()
        rootURL = nil
        manifest = nil
        chapters = []
        selectedChapterPath = nil
        text = ""
        styleText = ""
        snapshots = []
        searchResults = []
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
        if chapterPath == selectedChapterPath { return text }
        guard let rootURL else { return "" }
        return try WritingProjectDisk.readChapter(chapterPath, at: rootURL)
    }

    func restore(_ snapshot: ProjectSnapshot) {
        guard let rootURL else { return }
        do {
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
