import Foundation

enum ProjectStyleManager {
    private static let decisionsFileName = "style-decisions.json"
    private static let startMarker = "<!-- KISTULENTZ LEARNED PREFERENCES START -->"
    private static let endMarker = "<!-- KISTULENTZ LEARNED PREFERENCES END -->"

    static func prepare(at root: URL, projectName: String, kind: WritingProjectKind) throws {
        let url = WritingProjectDisk.styleURL(at: root)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let template = """
        # Kistulentz Style

        This project-local style guide is used for both local analysis and optional AI editing. Edit any section outside the learned-preferences markers.

        - Project: \(projectName)
        - Writing type: \(kind.title)

        ## Audience and purpose

        Describe the intended reader and what the manuscript should accomplish.

        ## Voice and tone

        Describe the voice, tone, point of view, and level of formality.

        ## Vocabulary and mechanics

        Record preferred spellings, capitalization, punctuation, terminology, and words to avoid.

        ## Project rules

        Add any rules that Kistulentz should follow when reviewing this manuscript.

        \(startMarker)
        ## Learned from editing decisions

        Kistulentz will summarize accepted and declined suggestions here. You can clear these observations from inside the app.
        \(endMarker)
        """
        try template.write(to: url, atomically: true, encoding: .utf8)
    }

    static func loadStyle(at root: URL) throws -> String {
        try String(contentsOf: WritingProjectDisk.styleURL(at: root), encoding: .utf8)
    }

    static func saveStyle(_ text: String, at root: URL) throws {
        try text.write(to: WritingProjectDisk.styleURL(at: root), atomically: true, encoding: .utf8)
    }

    static func record(
        action: StyleDecisionAction,
        issue: WritingIssue,
        at root: URL,
        now: Date = Date()
    ) throws {
        var archive = try loadArchive(at: root)
        if let index = archive.decisions.firstIndex(where: {
            $0.action == action
                && $0.category == issue.category
                && $0.excerpt == issue.excerpt
                && $0.replacement == issue.replacement
        }) {
            archive.decisions[index].count += 1
            archive.decisions[index].lastUsedAt = now
        } else {
            archive.decisions.append(ProjectStyleDecision(
                action: action,
                category: issue.category,
                excerpt: issue.excerpt,
                replacement: issue.replacement,
                count: 1,
                lastUsedAt: now
            ))
        }
        try saveArchive(archive, at: root)
        try render(archive, at: root)
    }

    static func clearLearnedPreferences(at root: URL) throws {
        try saveArchive(ProjectStyleDecisionArchive(), at: root)
        try render(ProjectStyleDecisionArchive(), at: root)
    }

    static func loadDecisions(at root: URL) throws -> [ProjectStyleDecision] {
        try loadArchive(at: root).decisions
    }

    private static func render(_ archive: ProjectStyleDecisionArchive, at root: URL) throws {
        var style = try loadStyle(at: root)
        let learned = learnedSection(archive)
        if let start = style.range(of: startMarker),
           let end = style.range(of: endMarker),
           start.upperBound <= end.lowerBound {
            style.replaceSubrange(start.upperBound..<end.lowerBound, with: "\n\(learned)\n")
        } else {
            style += "\n\n\(startMarker)\n\(learned)\n\(endMarker)\n"
        }
        try saveStyle(style, at: root)
    }

    private static func learnedSection(_ archive: ProjectStyleDecisionArchive) -> String {
        var lines = [
            "## Learned from editing decisions",
            "",
            "These observations are project-local and remain editable through the decisions Kistulentz records."
        ]
        if archive.decisions.isEmpty {
            lines += ["", "No editing preferences have been learned yet."]
            return lines.joined(separator: "\n")
        }

        let sorted = archive.decisions.sorted {
            if $0.count == $1.count { return $0.lastUsedAt > $1.lastUsedAt }
            return $0.count > $1.count
        }
        lines.append("")
        for decision in sorted.prefix(100) {
            let excerpt = inline(decision.excerpt)
            let count = decision.count == 1 ? "once" : "\(decision.count) times"
            switch (decision.action, decision.replacement) {
            case (.accepted, .some(let replacement)):
                lines.append("- Prefer `\(inline(replacement))` to `\(excerpt)` (\(decision.category.title.lowercased()); accepted \(count)).")
            case (.declined, .some(let replacement)):
                lines.append("- Keep `\(excerpt)` instead of `\(inline(replacement))` (\(decision.category.title.lowercased()); declined \(count)).")
            case (.declined, .none):
                lines.append("- Allow `\(excerpt)` despite the \(decision.category.title.lowercased()) flag (declined \(count)).")
            case (.accepted, .none):
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func inline(_ value: String) -> String {
        let flattened = value
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flattened.prefix(120))
    }

    private static func archiveURL(at root: URL) -> URL {
        WritingProjectDisk.metadataURL(at: root).appendingPathComponent(decisionsFileName)
    }

    private static func loadArchive(at root: URL) throws -> ProjectStyleDecisionArchive {
        let url = archiveURL(at: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return ProjectStyleDecisionArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectStyleDecisionArchive.self, from: Data(contentsOf: url))
    }

    private static func saveArchive(_ archive: ProjectStyleDecisionArchive, at root: URL) throws {
        try FileManager.default.createDirectory(
            at: WritingProjectDisk.metadataURL(at: root),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: archiveURL(at: root), options: .atomic)
    }
}
