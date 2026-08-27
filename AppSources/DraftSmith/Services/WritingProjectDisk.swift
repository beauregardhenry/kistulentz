import Foundation

enum WritingProjectDisk {
    static let metadataDirectoryName = ".kistulentz"
    static let styleFileName = "Kistulentz Style.md"
    private static let manifestFileName = "project.json"
    private static let historyDirectoryName = "history"
    private static let historyIndexFileName = "index.json"

    static func hasManifest(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(at: root).path)
    }

    static func createProject(
        in parent: URL,
        name: String,
        kind: WritingProjectKind
    ) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw WritingProjectError.invalidName }
        let root = parent.appendingPathComponent(trimmed, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else {
            throw WritingProjectError.folderAlreadyExists
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try prepareExistingProject(at: root, name: trimmed, kind: kind)
        return root
    }

    static func prepareExistingProject(
        at root: URL,
        name: String,
        kind: WritingProjectKind
    ) throws {
        try prepareDirectories(at: root)
        var chapterPaths = try scanMarkdownPaths(at: root)
        if chapterPaths.isEmpty {
            let starterURL = root.appendingPathComponent(kind.starterFileName)
            try kind.starterText.write(to: starterURL, atomically: true, encoding: .utf8)
            chapterPaths = [kind.starterFileName]
        }
        let manifest = WritingProjectManifest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            chapterOrder: chapterPaths,
            lastOpenedChapter: chapterPaths.first
        )
        try saveManifest(manifest, at: root)
        try ProjectStyleManager.prepare(at: root, projectName: manifest.name, kind: kind)
        try ManuscriptProjectDisk.prepare(at: root, projectName: manifest.name, kind: kind)
        try ProjectOutlineDisk.prepare(at: root, manifest: manifest)
        try ProjectResearchDisk.prepare(at: root, projectName: manifest.name)
        try SystemicRevisionDisk.prepare(at: root)
    }

    static func loadManifest(at root: URL) throws -> WritingProjectManifest {
        let url = manifestURL(at: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WritingProjectError.missingManifest
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WritingProjectManifest.self, from: Data(contentsOf: url))
    }

    static func saveManifest(_ manifest: WritingProjectManifest, at root: URL) throws {
        try prepareDirectories(at: root)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL(at: root), options: .atomic)
    }

    static func loadChapters(at root: URL, manifest: WritingProjectManifest) throws -> [ProjectChapter] {
        let discovered = try scanMarkdownPaths(at: root)
        guard !discovered.isEmpty else { throw WritingProjectError.noMarkdownFiles }

        let known = Set(discovered)
        var ordered = manifest.chapterOrder.filter { known.contains($0) }
        ordered.append(contentsOf: discovered.filter { !ordered.contains($0) })
        return try ordered.map { relativePath in
            let text = try readChapter(relativePath, at: root)
            return ProjectChapter(
                relativePath: relativePath,
                title: chapterTitle(from: text, fallback: URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent),
                wordCount: wordCount(in: text)
            )
        }
    }

    static func readChapter(_ relativePath: String, at root: URL) throws -> String {
        let data = try Data(contentsOf: chapterURL(relativePath, at: root))
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    static func writeChapter(_ text: String, relativePath: String, at root: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: chapterURL(relativePath, at: root), options: .atomic)
    }

    static func createChapter(named name: String, at root: URL) throws -> String {
        try createMarkdownFile(named: name, at: root)
    }

    static func createMarkdownFile(named name: String, at root: URL) throws -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw WritingProjectError.invalidChapterName }
        if !trimmed.lowercased().hasSuffix(".md") { trimmed += ".md" }
        let url = root.appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw WritingProjectError.chapterAlreadyExists
        }
        let title = url.deletingPathExtension().lastPathComponent
        try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
        return trimmed
    }

    static func uniqueMarkdownFileName(for title: String, at root: URL) -> String {
        let base = HeadingSplitPlanner.safeFileComponent(title)
        var candidate = "\(base).md"
        var suffix = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(suffix).md"
            suffix += 1
        }
        return candidate
    }

    static func createSnapshot(
        chapterPath: String,
        content: String,
        name: String?,
        reason: String,
        at root: URL,
        now: Date = Date()
    ) throws -> ProjectSnapshot? {
        try prepareDirectories(at: root)
        var index = try loadSnapshotIndex(at: root)
        if name == nil,
           let latest = index.snapshots
            .filter({ $0.chapterPath == chapterPath })
            .max(by: { $0.createdAt < $1.createdAt }),
           try snapshotContent(latest, at: root) == content {
            return nil
        }

        let id = UUID()
        let fileName = "\(id.uuidString).md"
        try content.write(
            to: historyURL(at: root).appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = ProjectSnapshot(
            id: id,
            chapterPath: chapterPath,
            name: title?.isEmpty == false ? title! : reason,
            reason: reason,
            createdAt: now,
            fileName: fileName
        )
        index.snapshots.append(snapshot)
        try saveSnapshotIndex(index, at: root)
        return snapshot
    }

    static func loadSnapshots(at root: URL) throws -> [ProjectSnapshot] {
        try loadSnapshotIndex(at: root).snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    static func snapshotContent(_ snapshot: ProjectSnapshot, at root: URL) throws -> String {
        try String(
            contentsOf: historyURL(at: root).appendingPathComponent(snapshot.fileName),
            encoding: .utf8
        )
    }

    static func rewriteSnapshotPaths(_ mapping: [String: String], at root: URL) throws {
        guard !mapping.isEmpty else { return }
        var index = try loadSnapshotIndex(at: root)
        for snapshotIndex in index.snapshots.indices {
            if let updated = mapping[index.snapshots[snapshotIndex].chapterPath] {
                index.snapshots[snapshotIndex].chapterPath = updated
            }
        }
        try saveSnapshotIndex(index, at: root)
    }

    static func search(
        _ query: String,
        chapters: [ProjectChapter],
        at root: URL,
        maximumResults: Int = 100
    ) throws -> [ProjectSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var results: [ProjectSearchResult] = []

        for chapter in chapters {
            let text = try readChapter(chapter.relativePath, at: root)
            let source = text as NSString
            var remaining = NSRange(location: 0, length: source.length)
            while remaining.length > 0 && results.count < maximumResults {
                let found = source.range(of: needle, options: [.caseInsensitive], range: remaining)
                guard found.location != NSNotFound else { break }
                let lineRange = source.lineRange(for: found)
                let preview = source.substring(with: lineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = source.substring(to: found.location)
                let line = prefix.reduce(into: 1) { count, character in
                    if character == "\n" { count += 1 }
                }
                results.append(ProjectSearchResult(
                    chapterPath: chapter.relativePath,
                    chapterTitle: chapter.title,
                    line: line,
                    preview: preview,
                    range: found
                ))
                let next = NSMaxRange(found)
                guard next < source.length else { break }
                remaining = NSRange(location: next, length: source.length - next)
            }
            if results.count >= maximumResults { break }
        }
        return results
    }

    static func wordCount(in text: String) -> Int {
        text.split { character in
            character.isWhitespace || character.isPunctuation
        }.count
    }

    static func styleURL(at root: URL) -> URL {
        root.appendingPathComponent(styleFileName)
    }

    static func metadataURL(at root: URL) -> URL {
        root.appendingPathComponent(metadataDirectoryName, isDirectory: true)
    }

    private static func prepareDirectories(at root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: metadataURL(at: root), withIntermediateDirectories: true)
        try manager.createDirectory(at: historyURL(at: root), withIntermediateDirectories: true)
    }

    private static func manifestURL(at root: URL) -> URL {
        metadataURL(at: root).appendingPathComponent(manifestFileName)
    }

    private static func historyURL(at root: URL) -> URL {
        metadataURL(at: root).appendingPathComponent(historyDirectoryName, isDirectory: true)
    }

    private static func historyIndexURL(at root: URL) -> URL {
        historyURL(at: root).appendingPathComponent(historyIndexFileName)
    }

    private static func chapterURL(_ relativePath: String, at root: URL) -> URL {
        root.appendingPathComponent(relativePath)
    }

    private static func loadSnapshotIndex(at root: URL) throws -> ProjectSnapshotIndex {
        try prepareDirectories(at: root)
        let url = historyIndexURL(at: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return ProjectSnapshotIndex() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectSnapshotIndex.self, from: Data(contentsOf: url))
    }

    private static func saveSnapshotIndex(_ index: ProjectSnapshotIndex, at root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: historyIndexURL(at: root), options: .atomic)
    }

    private static func scanMarkdownPaths(at root: URL) throws -> [String] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }
        let rootPath = root.standardizedFileURL.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            if values.isDirectory == true && (values.isHidden == true || url.lastPathComponent == metadataDirectoryName) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory != true,
                  url.pathExtension.lowercased() == "md",
                  !projectSupportFileNames.contains(url.lastPathComponent) else { continue }
            let standardized = url.standardizedFileURL.path
            guard standardized.hasPrefix(rootPath) else { continue }
            paths.append(String(standardized.dropFirst(rootPath.count)))
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func chapterTitle(from text: String, fallback: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return fallback
    }

    private static func isValidName(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains(":") && value != "." && value != ".."
    }

    private static var projectSupportFileNames: Set<String> {
        [
            styleFileName,
            ManuscriptProjectDisk.reportFileName,
            ManuscriptProjectDisk.bibleFileName,
            ProjectResearchDisk.notesFileName
        ]
    }
}
