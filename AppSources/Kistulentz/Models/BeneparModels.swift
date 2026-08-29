import Foundation

struct StructuralProfile: Codable, Equatable {
    let sentencesAnalyzed: Int
    let sentencesAvailable: Int
    let averageTreeDepth: Double
    let maximumTreeDepth: Int
    let averageClausesPerSentence: Double
    let subordinateSentenceRatio: Double
    let averageLongestNounPhraseWords: Double
    let longNounPhraseRatio: Double
    let coordinationRatio: Double
    let passiveCandidateRatio: Double
    let fragmentRatio: Double

    static let empty = StructuralProfile(
        sentencesAnalyzed: 0,
        sentencesAvailable: 0,
        averageTreeDepth: 0,
        maximumTreeDepth: 0,
        averageClausesPerSentence: 0,
        subordinateSentenceRatio: 0,
        averageLongestNounPhraseWords: 0,
        longNounPhraseRatio: 0,
        coordinationRatio: 0,
        passiveCandidateRatio: 0,
        fragmentRatio: 0
    )

    var isSampled: Bool { sentencesAvailable > sentencesAnalyzed }

    var summary: String {
        let sampled = isSampled ? " · sampled from \(sentencesAvailable) available sentences" : ""
        return """
        Benepar sentences: \(sentencesAnalyzed)\(sampled)
        Average parse depth: \(averageTreeDepth.formatted(.number.precision(.fractionLength(1))))
        Average clauses per sentence: \(averageClausesPerSentence.formatted(.number.precision(.fractionLength(1))))
        Sentences with subordination: \((subordinateSentenceRatio * 100).formatted(.number.precision(.fractionLength(0))))%
        Average longest noun phrase: \(averageLongestNounPhraseWords.formatted(.number.precision(.fractionLength(1)))) words
        Sentences with coordination: \((coordinationRatio * 100).formatted(.number.precision(.fractionLength(0))))%
        """
    }

    static func weightedMerge(_ profiles: [(profile: StructuralProfile, weight: Int)]) -> StructuralProfile? {
        let usable = profiles.filter { $0.profile.sentencesAnalyzed > 0 }
        guard !usable.isEmpty else { return nil }
        let totalWeight = max(usable.reduce(0) { $0 + max($1.weight, 1) }, 1)
        func weighted(_ value: (StructuralProfile) -> Double) -> Double {
            usable.reduce(0) { partial, item in
                partial + value(item.profile) * Double(max(item.weight, 1))
            } / Double(totalWeight)
        }
        return StructuralProfile(
            sentencesAnalyzed: usable.reduce(0) { $0 + $1.profile.sentencesAnalyzed },
            sentencesAvailable: usable.reduce(0) { $0 + $1.profile.sentencesAvailable },
            averageTreeDepth: weighted(\.averageTreeDepth),
            maximumTreeDepth: usable.map(\.profile.maximumTreeDepth).max() ?? 0,
            averageClausesPerSentence: weighted(\.averageClausesPerSentence),
            subordinateSentenceRatio: weighted(\.subordinateSentenceRatio),
            averageLongestNounPhraseWords: weighted(\.averageLongestNounPhraseWords),
            longNounPhraseRatio: weighted(\.longNounPhraseRatio),
            coordinationRatio: weighted(\.coordinationRatio),
            passiveCandidateRatio: weighted(\.passiveCandidateRatio),
            fragmentRatio: weighted(\.fragmentRatio)
        )
    }
}

struct BeneparAnalysis: Equatable {
    let metrics: StructuralProfile
    let issues: [WritingIssue]
}

struct BeneparWorkerResponse: Decodable {
    let id: String?
    let ok: Bool
    let engine: String?
    let engineVersion: String?
    let metrics: StructuralProfile?
    let issues: [BeneparWorkerIssue]?
    let error: String?
}

struct BeneparWorkerIssue: Decodable, Equatable {
    let category: String
    let location: Int
    let length: Int
    let excerpt: String
    let message: String

    func writingIssue(in text: String) -> WritingIssue? {
        let source = text as NSString
        let range = NSRange(location: location, length: length)
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= source.length else { return nil }
        let actualExcerpt = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actualExcerpt.isEmpty else { return nil }

        let issueCategory: IssueCategory
        switch category {
        case "adverb": issueCategory = .adverb
        case "passiveVoice": issueCategory = .passiveVoice
        case "structuralComplexity": issueCategory = .structuralComplexity
        default: return nil
        }
        return WritingIssue(
            category: issueCategory,
            range: range,
            excerpt: actualExcerpt,
            message: message,
            source: .local
        )
    }
}

enum BeneparAnalysisMerger {
    static func merge(native: AnalysisResult, benepar: BeneparAnalysis) -> AnalysisResult {
        let replacesSurfaceTags = !benepar.metrics.isSampled
        var issues = native.issues.filter { issue in
            guard replacesSurfaceTags else { return true }
            return issue.category != .adverb && issue.category != .passiveVoice
        }

        for parsed in benepar.issues {
            let isDuplicate = issues.contains { existing in
                existing.category == parsed.category
                    && rangesOverlap(existing.range, parsed.range)
            }
            if !isDuplicate { issues.append(parsed) }
        }
        issues.sort {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
        return AnalysisResult(stats: native.stats, issues: issues)
    }

    private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }
}

enum ReferenceStructuralSampler {
    static func text(from reference: EPUBReference, maximumCharacters: Int = 90_000) -> String {
        text(from: reference.chapters, maximumCharacters: maximumCharacters)
    }

    static func text(from excerpts: [LibraryExcerpt], maximumCharacters: Int = 30_000) -> String {
        let chapters = excerpts.enumerated().map { index, excerpt in
            ReferenceChapter(id: index, title: excerpt.section, text: excerpt.text)
        }
        return text(from: chapters, maximumCharacters: maximumCharacters)
    }

    private static func text(from chapters: [ReferenceChapter], maximumCharacters: Int) -> String {
        guard maximumCharacters > 0, !chapters.isEmpty else { return "" }
        let limit = min(chapters.count, 24)
        let sampled = chapters.count <= limit
            ? chapters
            : (0..<limit).map { chapters[$0 * chapters.count / limit] }
        let perChapter = max(800, maximumCharacters / max(sampled.count, 1))
        let combined = sampled.map { chapter in
            String(chapter.text.prefix(perChapter))
        }
        .joined(separator: "\n\n")
        return String(combined.prefix(maximumCharacters))
    }
}

enum ManuscriptStructuralSampler {
    static func text(from documents: [ManuscriptDocument], maximumCharacters: Int = 150_000) -> String {
        guard !documents.isEmpty, maximumCharacters > 0 else { return "" }
        let limit = min(documents.count, 40)
        let sampled = documents.count <= limit
            ? documents
            : (0..<limit).map { documents[$0 * documents.count / limit] }
        let perDocument = max(1_200, maximumCharacters / max(sampled.count, 1))
        let combined = sampled.map { document in
            String(document.text.prefix(perDocument))
        }.joined(separator: "\n\n")
        return String(combined.prefix(maximumCharacters))
    }
}

struct BeneparLanguagePackManifest: Codable, Equatable {
    let schemaVersion: Int
    let identifier: String
    let version: String
    let architecture: String
    let pythonRelativePath: String
    let modelRelativePath: String
    let installedBytes: Int64?
}

struct BeneparLanguagePackCatalog: Decodable {
    let schemaVersion: Int
    let packs: [BeneparLanguagePackCatalogEntry]
}

struct BeneparLanguagePackCatalogEntry: Decodable, Equatable {
    let architecture: String
    let version: String
    let downloadURL: URL
    let sha256: String
    let downloadBytes: Int64
    let installedBytes: Int64
}

struct BeneparLanguagePackInstallation: Equatable {
    let rootURL: URL
    let pythonURL: URL
    let modelURL: URL
    let manifest: BeneparLanguagePackManifest
}

enum BeneparLanguagePackState: Equatable {
    case notInstalled
    case installed(version: String, installedBytes: Int64?)
    case invalid(reason: String)

    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .installed(let version, _): "English pack \(version) installed"
        case .invalid: "Needs repair"
        }
    }
}

enum BeneparLanguagePackError: LocalizedError {
    case catalogUnavailable
    case unsupportedCatalog
    case invalidCatalog
    case architectureUnavailable(String)
    case unexpectedDownloadSize
    case invalidChecksum
    case invalidArchive
    case invalidManifest(String)
    case workerUnavailable
    case workerStopped(String)
    case workerTimedOut
    case workerRejected(String)

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            "The English language-pack catalog is not available yet. Kistulentz’s native analysis remains active."
        case .unsupportedCatalog:
            "This language-pack catalog is newer than this version of Kistulentz can safely install."
        case .invalidCatalog:
            "The English language-pack catalog contains invalid or unsafe download information."
        case .architectureUnavailable(let architecture):
            "The English language pack is not available for this Mac’s \(architecture) architecture."
        case .unexpectedDownloadSize:
            "The English language-pack download had an unexpected size and was not installed."
        case .invalidChecksum:
            "The downloaded language pack did not match its published SHA-256 checksum and was not installed."
        case .invalidArchive:
            "The downloaded language pack could not be unpacked safely."
        case .invalidManifest(let reason):
            "The English language pack is incomplete or incompatible: \(reason)"
        case .workerUnavailable:
            "Kistulentz could not find its local Benepar analysis worker."
        case .workerStopped(let detail):
            "The English structural analyzer stopped unexpectedly. \(detail)"
        case .workerTimedOut:
            "The English structural analyzer took too long to respond. Kistulentz kept the native analysis instead."
        case .workerRejected(let detail):
            "The English structural analyzer could not analyze this passage: \(detail)"
        }
    }
}
