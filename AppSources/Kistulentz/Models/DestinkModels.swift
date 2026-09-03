import Foundation

enum DestinkTier: String, CaseIterable, Codable, Identifiable {
    case lexical
    case syntactic
    case formatting
    case discourse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lexical: "Word choice"
        case .syntactic: "Sentence shape"
        case .formatting: "Formatting"
        case .discourse: "Rhythm & repetition"
        }
    }
}

enum DestinkSeverity: String, CaseIterable, Codable, Identifiable {
    case candidate
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .candidate: "Review"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var weight: Double {
        switch self {
        case .candidate: 0.25
        case .low: 1
        case .medium: 2
        case .high: 4
        }
    }
}

struct DestinkFinding: Identifiable, Equatable {
    let id: UUID
    let ruleID: String
    let tier: DestinkTier
    let severity: DestinkSeverity
    let range: NSRange
    let excerpt: String
    let message: String
    let explanation: String
    let usedBenepar: Bool

    init(
        id: UUID = UUID(),
        ruleID: String,
        tier: DestinkTier,
        severity: DestinkSeverity,
        range: NSRange,
        excerpt: String,
        message: String,
        explanation: String,
        usedBenepar: Bool = false
    ) {
        self.id = id
        self.ruleID = ruleID
        self.tier = tier
        self.severity = severity
        self.range = range
        self.excerpt = excerpt
        self.message = message
        self.explanation = explanation
        self.usedBenepar = usedBenepar
    }
}

struct DestinkDocumentReport: Identifiable, Equatable {
    var id: String { relativePath }
    let relativePath: String
    let title: String
    let wordCount: Int
    let findings: [DestinkFinding]
    let usedBenepar: Bool

    var score: Double {
        let denominator = max(wordCount, DestinkReport.minimumWordsForScore)
        return findings.reduce(0) { $0 + $1.severity.weight } / Double(denominator) * 1_000
    }
}

struct DestinkReport: Equatable {
    static let schemaVersion = 1
    static let minimumWordsForScore = 100

    let documents: [DestinkDocumentReport]

    var wordCount: Int { documents.reduce(0) { $0 + $1.wordCount } }
    var findings: [DestinkFinding] { documents.flatMap(\.findings) }
    var findingCount: Int { documents.reduce(0) { $0 + $1.findings.count } }
    var usedBenepar: Bool { documents.contains(where: \.usedBenepar) }

    var score: Double {
        let denominator = max(wordCount, Self.minimumWordsForScore)
        return findings.reduce(0) { $0 + $1.severity.weight } / Double(denominator) * 1_000
    }

    func score(for tier: DestinkTier) -> Double {
        let denominator = max(wordCount, Self.minimumWordsForScore)
        return findings.lazy
            .filter { $0.tier == tier }
            .reduce(0) { $0 + $1.severity.weight } / Double(denominator) * 1_000
    }
}

struct BeneparDestinkAnalysis: Equatable {
    let findings: [DestinkFinding]
}

struct BeneparWorkerDestinkFinding: Decodable, Equatable {
    let ruleId: String
    let tier: String
    let severity: String
    let location: Int
    let length: Int
    let excerpt: String
    let message: String
    let explanation: String

    func finding(in text: String) -> DestinkFinding? {
        let source = text as NSString
        let range = NSRange(location: location, length: length)
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= source.length,
              let parsedTier = DestinkTier(rawValue: tier),
              let parsedSeverity = DestinkSeverity(rawValue: severity) else { return nil }
        let actualExcerpt = source.substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actualExcerpt.isEmpty else { return nil }
        return DestinkFinding(
            ruleID: ruleId,
            tier: parsedTier,
            severity: parsedSeverity,
            range: range,
            excerpt: actualExcerpt,
            message: message,
            explanation: explanation,
            usedBenepar: true
        )
    }
}
