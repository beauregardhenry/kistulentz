import Foundation

enum SystemicRevisionDisk {
    private static let fileName = "revisions.json"

    static func prepare(at root: URL) throws {
        let url = WritingProjectDisk.metadataURL(at: root).appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try save(SystemicRevisionArchive(), at: root)
    }

    static func load(at root: URL) throws -> SystemicRevisionArchive {
        let url = WritingProjectDisk.metadataURL(at: root).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return SystemicRevisionArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SystemicRevisionArchive.self, from: Data(contentsOf: url))
    }

    static func save(_ archive: SystemicRevisionArchive, at root: URL) throws {
        try FileManager.default.createDirectory(at: WritingProjectDisk.metadataURL(at: root), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(archive).write(
            to: WritingProjectDisk.metadataURL(at: root).appendingPathComponent(fileName),
            options: .atomic
        )
    }
}

enum SystemicRevisionAnalyzer {
    private static let citationRegex = try! NSRegularExpression(pattern: #"\[@([A-Za-z0-9_:\-]+)"#)

    static func analyze(
        projectName: String,
        kind: WritingProjectKind,
        documents: [ManuscriptDocument],
        manuscript: ManuscriptAnalysis?,
        bibliography: ProjectBibliographyArchive,
        sources: [ResearchSource],
        targetGrade: Int
    ) -> [SystemicRevisionFinding] {
        var findings: [SystemicRevisionFinding] = []
        let counts = documents.map { (path: $0.relativePath, count: WritingProjectDisk.wordCount(in: $0.text)) }
        let nonzero = counts.map(\.count).filter { $0 > 0 }
        let average = nonzero.isEmpty ? 0 : Double(nonzero.reduce(0, +)) / Double(nonzero.count)

        for document in documents {
            let count = counts.first(where: { $0.path == document.relativePath })?.count ?? 0
            if count == 0 {
                findings.append(finding(.structure, .confirmedProblem, "Empty manuscript section", "This file contains no manuscript words.", document, excerpt: ""))
            } else if documents.count > 1, average > 500, Double(count) < average * 0.25 {
                findings.append(finding(.structure, .probableProblem, "Section is much shorter than its neighbors", "At \(count.formatted()) words, this section is less than one quarter of the manuscript-section average. Confirm that the imbalance is intentional.", document, excerpt: firstNonemptyLine(document.text)))
            }

            let analysis = ReadabilityEngine.analyze(document.text, targetGrade: targetGrade)
            if analysis.stats.gradeLevel > Double(targetGrade) + 1.5 {
                findings.append(finding(.pacing, .probableProblem, "Reading grade is above the project target", "Estimated grade \(analysis.stats.gradeLevel.formatted(.number.precision(.fractionLength(1)))) versus target grade \(targetGrade). Review sentence and paragraph load in this section.", document, excerpt: firstNonemptyLine(document.text)))
            }
            for issue in analysis.issues.prefix(80) {
                let pass: RevisionPass = issue.replacement == nil ? .voiceAndStyle : .lineEditing
                let classification: RevisionFindingClassification = issue.replacement == nil ? .opportunity : .confirmedProblem
                findings.append(finding(
                    pass,
                    classification,
                    issue.category.title,
                    issue.message,
                    document,
                    excerpt: issue.excerpt,
                    replacement: issue.replacement
                ))
            }

            let source = document.text as NSString
            let citations = citationRegex.matches(in: document.text, range: NSRange(location: 0, length: source.length))
            let known = Set(sources.filter { bibliography.sourceIDs.contains($0.id) }.map { $0.citeKey.lowercased() })
            for match in citations where match.numberOfRanges > 1 {
                let key = source.substring(with: match.range(at: 1))
                if !known.contains(key.lowercased()) {
                    let excerpt = source.substring(with: match.range(at: 0))
                    findings.append(finding(.argumentAndEvidence, .confirmedProblem, "Citation key is not in the project bibliography", "The citation @\(key) does not match a source currently attached to this project.", document, excerpt: excerpt))
                }
            }
        }

        if let manuscript {
            for item in manuscript.continuityChecks {
                findings.append(generalFinding(.continuity, .probableProblem, item.title, item.detail, chapterPath: item.chapterPath))
            }
            for item in manuscript.claimChecks {
                findings.append(generalFinding(.argumentAndEvidence, .authorQuestion, item.title, item.detail, chapterPath: item.chapterPath))
            }
            for phrase in manuscript.repeatedPhrases.prefix(12) {
                findings.append(generalFinding(.voiceAndStyle, .opportunity, "Repeated phrase", "“\(phrase.value)” appears \(phrase.count) times. Confirm that the repetition is purposeful.", excerpt: phrase.value))
            }
            if kind == .fiction {
                for entity in manuscript.entities.filter({ $0.kind == .person && $0.count >= 3 }).prefix(12) {
                    findings.append(generalFinding(.characterAndPeople, .authorQuestion, "Check character through-line: \(entity.name)", "This name appears \(entity.count) times across \(entity.chapters.count) section(s). Confirm that motivation, description, and naming stay consistent.", excerpt: entity.name))
                }
            }
        }

        var seen: Set<String> = []
        return findings.filter { seen.insert($0.signature).inserted }
            .sorted {
                if $0.revisionPass != $1.revisionPass { return RevisionPass.allCases.firstIndex(of: $0.revisionPass)! < RevisionPass.allCases.firstIndex(of: $1.revisionPass)! }
                if $0.classification.rank != $1.classification.rank { return $0.classification.rank < $1.classification.rank }
                return ($0.chapterPath ?? "") < ($1.chapterPath ?? "")
            }
    }

    static func reconcile(_ local: [SystemicRevisionFinding], with archive: SystemicRevisionArchive, now: Date = Date()) -> SystemicRevisionArchive {
        let old = Dictionary(uniqueKeysWithValues: archive.findings.map { ($0.signature, $0) })
        let refreshed = local.map { incoming -> SystemicRevisionFinding in
            guard let previous = old[incoming.signature] else { return incoming }
            var value = incoming
            value.id = previous.id
            value.status = previous.status
            value.createdAt = previous.createdAt
            value.lastSeenAt = now
            return value
        }
        var result = archive
        result.findings = archive.findings.filter { $0.origin == .ai } + refreshed
        result.lastLocalScanAt = now
        return result
    }

    private static func finding(
        _ pass: RevisionPass,
        _ classification: RevisionFindingClassification,
        _ title: String,
        _ detail: String,
        _ document: ManuscriptDocument,
        excerpt: String,
        replacement: String? = nil
    ) -> SystemicRevisionFinding {
        generalFinding(pass, classification, title, detail, chapterPath: document.relativePath, excerpt: excerpt, replacement: replacement)
    }

    private static func generalFinding(
        _ pass: RevisionPass,
        _ classification: RevisionFindingClassification,
        _ title: String,
        _ detail: String,
        chapterPath: String? = nil,
        excerpt: String = "",
        replacement: String? = nil
    ) -> SystemicRevisionFinding {
        let signature = stableSignature([pass.rawValue, classification.rawValue, title, chapterPath ?? "", excerpt.lowercased()])
        return SystemicRevisionFinding(
            signature: signature,
            revisionPass: pass,
            classification: classification,
            title: title,
            detail: detail,
            chapterPath: chapterPath,
            excerpt: excerpt,
            replacement: replacement
        )
    }

    private static func stableSignature(_ parts: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in parts.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func firstNonemptyLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

enum RevisionChangePlanner {
    static func changes(from findings: [SystemicRevisionFinding]) throws -> RevisionChangeSet {
        let changes = findings.compactMap { finding -> RevisionChange? in
            guard let path = finding.chapterPath,
                  !finding.excerpt.isEmpty,
                  let replacement = finding.replacement,
                  replacement != finding.excerpt else { return nil }
            return RevisionChange(
                findingID: finding.id,
                chapterPath: path,
                originalText: finding.excerpt,
                replacementText: replacement,
                explanation: finding.detail
            )
        }
        guard !changes.isEmpty else { throw SystemicRevisionError.noConcreteChanges }
        return RevisionChangeSet(title: "Systemic Revision Changes", summary: "Review every proposed replacement before applying it.", changes: changes)
    }

    static func validate(_ set: RevisionChangeSet, documents: [String: String]) -> RevisionChangeSet {
        var result = set
        var acceptedRanges: [String: [(id: UUID, range: NSRange)]] = [:]
        for index in result.changes.indices {
            guard result.changes[index].isIncluded else { result.changes[index].conflict = nil; continue }
            let change = result.changes[index]
            guard isSafeMarkdownPath(change.chapterPath), let text = documents[change.chapterPath] else {
                result.changes[index].conflict = "The target is not a current project Markdown file."
                continue
            }
            guard change.originalText != change.replacementText, !change.originalText.isEmpty else {
                result.changes[index].conflict = "This proposal does not contain a usable replacement."
                continue
            }
            let ranges = occurrences(of: change.originalText, in: text)
            guard ranges.count == 1, let range = ranges.first else {
                result.changes[index].conflict = ranges.isEmpty
                    ? "The original passage changed after this suggestion was created."
                    : "The original passage occurs more than once, so replacement would be ambiguous."
                continue
            }
            if acceptedRanges[change.chapterPath, default: []].contains(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                result.changes[index].conflict = "This proposal overlaps another included change."
            } else {
                result.changes[index].conflict = nil
                acceptedRanges[change.chapterPath, default: []].append((change.id, range))
            }
        }
        return result
    }

    static func applying(_ set: RevisionChangeSet, to documents: [String: String]) throws -> [String: String] {
        let checked = validate(set, documents: documents)
        guard checked.hasChanges else { throw SystemicRevisionError.noConcreteChanges }
        guard !checked.hasConflicts else {
            let path = checked.includedChanges.first(where: { $0.conflict != nil })?.chapterPath ?? "the manuscript"
            throw SystemicRevisionError.stalePassage(path)
        }
        var result = documents
        for (path, changes) in Dictionary(grouping: checked.includedChanges, by: \.chapterPath) {
            guard let text = result[path] else { throw SystemicRevisionError.stalePassage(path) }
            let source = text as NSString
            let ranged = changes.map { change in (change, source.range(of: change.originalText)) }
                .sorted { $0.1.location > $1.1.location }
            var updated = text
            for (change, range) in ranged {
                updated = (updated as NSString).replacingCharacters(in: range, with: change.replacementText)
            }
            result[path] = updated
        }
        return result
    }

    private static func occurrences(of needle: String, in text: String) -> [NSRange] {
        let source = text as NSString
        var ranges: [NSRange] = []
        var remaining = NSRange(location: 0, length: source.length)
        while remaining.length > 0 {
            let range = source.range(of: needle, range: remaining)
            guard range.location != NSNotFound else { break }
            ranges.append(range)
            let next = NSMaxRange(range)
            guard next < source.length else { break }
            remaining = NSRange(location: next, length: source.length - next)
        }
        return ranges
    }

    private static func isSafeMarkdownPath(_ path: String) -> Bool {
        let components = NSString(string: path).standardizingPath.split(separator: "/")
        return !path.hasPrefix("/") && !components.contains("..") && path.lowercased().hasSuffix(".md")
    }
}
