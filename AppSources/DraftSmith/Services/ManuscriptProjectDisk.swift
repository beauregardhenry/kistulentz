import Foundation

enum ManuscriptProjectDisk {
    static let reportFileName = "Kistulentz Manuscript Report.md"
    static let bibleFileName = "Kistulentz Bible.md"
    private static let cacheFileName = "manuscript-cache.json"
    private static let betaReadersFileName = "beta-readers.json"

    static func prepare(at root: URL, projectName: String, kind: WritingProjectKind) throws {
        let manager = FileManager.default
        let reportURL = reportURL(at: root)
        if !manager.fileExists(atPath: reportURL.path) {
            try ManuscriptReportManager.template(projectName: projectName, kind: kind)
                .write(to: reportURL, atomically: true, encoding: .utf8)
        }
        let bibleURL = bibleURL(at: root)
        if !manager.fileExists(atPath: bibleURL.path) {
            try ManuscriptBibleManager.template(projectName: projectName, kind: kind)
                .write(to: bibleURL, atomically: true, encoding: .utf8)
        }
    }

    static func loadReport(at root: URL) throws -> String {
        try String(contentsOf: reportURL(at: root), encoding: .utf8)
    }

    static func saveReport(_ text: String, at root: URL) throws {
        try text.write(to: reportURL(at: root), atomically: true, encoding: .utf8)
    }

    static func loadBible(at root: URL) throws -> String {
        try String(contentsOf: bibleURL(at: root), encoding: .utf8)
    }

    static func saveBible(_ text: String, at root: URL) throws {
        try text.write(to: bibleURL(at: root), atomically: true, encoding: .utf8)
    }

    static func loadCache(at root: URL) throws -> ManuscriptProjectCache {
        let url = cacheURL(at: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ManuscriptProjectCache()
        }
        return try JSONDecoder().decode(ManuscriptProjectCache.self, from: Data(contentsOf: url))
    }

    static func saveCache(_ cache: ManuscriptProjectCache, at root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: cacheURL(at: root), options: .atomic)
    }

    static func loadCustomBetaReaders(at root: URL) throws -> [BetaReaderProfile] {
        let url = betaReadersURL(at: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode(BetaReaderArchive.self, from: Data(contentsOf: url)).readers
    }

    static func saveCustomBetaReaders(_ readers: [BetaReaderProfile], at root: URL) throws {
        let archive = BetaReaderArchive(readers: readers.map { reader in
            var editable = reader
            editable.isBuiltIn = false
            return editable
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: betaReadersURL(at: root), options: .atomic)
    }

    static func reportURL(at root: URL) -> URL {
        root.appendingPathComponent(reportFileName)
    }

    static func bibleURL(at root: URL) -> URL {
        root.appendingPathComponent(bibleFileName)
    }

    private static func cacheURL(at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(cacheFileName)
    }

    private static func betaReadersURL(at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(betaReadersFileName)
    }
}

enum ManuscriptReportManager {
    private static let localStart = "<!-- kistulentz:local-report:start -->"
    private static let localEnd = "<!-- kistulentz:local-report:end -->"
    private static let aiStart = "<!-- kistulentz:ai-report:start -->"
    private static let aiEnd = "<!-- kistulentz:ai-report:end -->"

    static func template(projectName: String, kind: WritingProjectKind) -> String {
        """
        # Kistulentz Manuscript Report

        > **\(projectName)** · \(kind.title). This report updates automatically using local analysis. Cloud and local AI run only when you choose Deepen w/ AI.

        \(localStart)
        ## Waiting for manuscript analysis

        Continue writing. Kistulentz will update this report after a short pause.
        \(localEnd)

        \(aiStart)
        \(aiEnd)
        """
    }

    static func compose(
        current: String,
        localReport: String,
        aiMarkdown: String?,
        projectName: String,
        kind: WritingProjectKind
    ) -> String {
        var result = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty {
            result = template(projectName: projectName, kind: kind)
        }
        result = replaceOrAppend(
            in: result,
            start: localStart,
            end: localEnd,
            content: localReport.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let ai = aiMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        result = replaceOrAppend(in: result, start: aiStart, end: aiEnd, content: ai)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func replaceOrAppend(
        in text: String,
        start: String,
        end: String,
        content: String
    ) -> String {
        let block = content.isEmpty ? "\(start)\n\(end)" : "\(start)\n\(content)\n\(end)"
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block
        }
        return text.replacingCharacters(in: startRange.lowerBound..<endRange.upperBound, with: block)
    }
}

enum ManuscriptBibleManager {
    static let managedStart = "<!-- kistulentz:managed-bible:start -->"
    static let managedEnd = "<!-- kistulentz:managed-bible:end -->"
    private static let aiStart = "<!-- kistulentz:ai-bible:start -->"
    private static let aiEnd = "<!-- kistulentz:ai-bible:end -->"

    static func template(projectName: String, kind: WritingProjectKind) -> String {
        """
        # Kistulentz Bible

        > **\(projectName)** · \(kind.title). Kistulentz updates the managed section locally. Manual notes and corrections outside that section are preserved.

        \(managedStart)
        ## Automatically Tracked Manuscript Facts

        Continue writing. Characters, people, places, organizations, terms, timeline markers, and continuity checks will appear here.
        \(managedEnd)

        \(aiStart)
        \(aiEnd)

        ## Author Notes and Corrections

        Add canon, terminology, source notes, corrections, and other instructions here. Kistulentz preserves this section during automatic updates.
        """
    }

    static func merge(
        currentBible: String,
        previousGeneratedBlock: String,
        newGeneratedBlock: String,
        projectName: String,
        kind: WritingProjectKind
    ) -> String {
        var current = currentBible.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { current = template(projectName: projectName, kind: kind) }
        let currentBlock = extractBlock(from: current, start: managedStart, end: managedEnd) ?? ""
        let mergedBlock = mergeGeneratedLines(
            current: currentBlock,
            previous: previousGeneratedBlock,
            new: newGeneratedBlock
        )
        let replacement = "\(managedStart)\n\(mergedBlock.trimmingCharacters(in: .whitespacesAndNewlines))\n\(managedEnd)"

        guard let startRange = current.range(of: managedStart),
              let endRange = current.range(of: managedEnd, range: startRange.upperBound..<current.endIndex) else {
            return current + "\n\n" + replacement + "\n"
        }
        return current
            .replacingCharacters(in: startRange.lowerBound..<endRange.upperBound, with: replacement)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func addingAIDeepening(
        _ markdown: String,
        to currentBible: String,
        provider: String,
        model: String
    ) -> String {
        let content = """
        ## AI-Deepened Bible Notes

        > Generated on request with \(provider) · \(model). Treat these as editorial observations and correct them when the manuscript says otherwise.

        \(markdown.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        let replacement = "\(aiStart)\n\(content)\n\(aiEnd)"
        guard let startRange = currentBible.range(of: aiStart),
              let endRange = currentBible.range(of: aiEnd, range: startRange.upperBound..<currentBible.endIndex) else {
            return currentBible.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + replacement + "\n"
        }
        return currentBible
            .replacingCharacters(in: startRange.lowerBound..<endRange.upperBound, with: replacement)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func mergeGeneratedLines(current: String, previous: String, new: String) -> String {
        // Before the first scan, the managed block contains only Kistulentz's
        // placeholder. Author notes live outside this block and remain intact.
        if previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return new
        }
        let currentLines = current.components(separatedBy: .newlines)
        let previousLines = previous.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        let currentByID = keyedLines(currentLines)
        let previousByID = keyedLines(previousLines)
        let newByID = keyedLines(newLines)
        var usedIDs: Set<String> = []
        var output: [String] = []

        for line in newLines {
            guard let id = lineID(line) else {
                output.append(line)
                continue
            }
            usedIDs.insert(id)
            if let old = previousByID[id] {
                guard let edited = currentByID[id] else { continue }
                output.append(edited == old ? line : edited)
            } else {
                output.append(line)
            }
        }

        let preservedKeyed = currentByID
            .filter { id, line in
                guard !usedIDs.contains(id) else { return false }
                guard let old = previousByID[id] else { return true }
                return line != old && newByID[id] == nil
            }
            .sorted { $0.key < $1.key }
            .map(\.value)

        let previousUnkeyed = Set(previousLines.map(normalizedLine).filter { !$0.isEmpty })
        let manualUnkeyed = currentLines.filter { line in
            let normalized = normalizedLine(line)
            return !normalized.isEmpty
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
                && !line.contains("<!-- kistulentz:id:")
                && !previousUnkeyed.contains(normalized)
        }

        if !preservedKeyed.isEmpty || !manualUnkeyed.isEmpty {
            output.append("")
            output.append("### Preserved Manual Entries")
            output.append(contentsOf: preservedKeyed)
            output.append(contentsOf: manualUnkeyed)
        }
        return output.joined(separator: "\n")
    }

    private static func extractBlock(from text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keyedLines(_ lines: [String]) -> [String: String] {
        lines.reduce(into: [:]) { result, line in
            if let id = lineID(line) { result[id] = line }
        }
    }

    private static func lineID(_ line: String) -> String? {
        let marker = "<!-- kistulentz:id:"
        guard let start = line.range(of: marker),
              let end = line.range(of: " -->", range: start.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[start.upperBound..<end.lowerBound])
    }

    private static func normalizedLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
