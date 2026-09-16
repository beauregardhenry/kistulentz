import Foundation
import SwiftUI

enum IssueCategory: String, Codable, CaseIterable, Identifiable {
    case hardSentence
    case veryHardSentence
    case adverb
    case passiveVoice
    case structuralComplexity
    case complexPhrase
    case aiTell
    case spelling
    case grammar
    case aiSuggestion
    case referenceVoice
    case continuity
    case avoidedWord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hardSentence: "Hard to read"
        case .veryHardSentence: "Very hard to read"
        case .adverb: "Adverb"
        case .passiveVoice: "Passive voice"
        case .structuralComplexity: "Sentence structure"
        case .complexPhrase: "Simpler alternative"
        case .aiTell: "AI-sounding phrasing"
        case .spelling: "Spelling"
        case .grammar: "Grammar"
        case .aiSuggestion: "AI suggestion"
        case .referenceVoice: "Reference voice"
        case .continuity: "Continuity"
        case .avoidedWord: "Avoided word"
        }
    }

    var shortLabel: String {
        switch self {
        case .hardSentence: "Hard"
        case .veryHardSentence: "Very hard"
        case .adverb: "Adverbs"
        case .passiveVoice: "Passive"
        case .structuralComplexity: "Structure"
        case .complexPhrase: "Phrases"
        case .aiTell: "AI tells"
        case .spelling: "Spelling"
        case .grammar: "Grammar"
        case .aiSuggestion: "AI"
        case .referenceVoice: "Voice"
        case .continuity: "Continuity"
        case .avoidedWord: "Avoided"
        }
    }

    var color: Color {
        switch self {
        case .hardSentence: Color(red: 0.97, green: 0.78, blue: 0.25)
        case .veryHardSentence: Color(red: 0.93, green: 0.35, blue: 0.31)
        case .adverb: Color(red: 0.34, green: 0.63, blue: 0.95)
        case .passiveVoice: Color(red: 0.34, green: 0.76, blue: 0.55)
        case .structuralComplexity: Color(red: 0.96, green: 0.50, blue: 0.22)
        case .complexPhrase: Color(red: 0.70, green: 0.48, blue: 0.91)
        case .aiTell: Color(red: 0.46, green: 0.42, blue: 0.86)
        case .spelling: Color(red: 0.92, green: 0.27, blue: 0.32)
        case .grammar: Color(red: 0.25, green: 0.68, blue: 0.85)
        case .aiSuggestion: Color(red: 0.21, green: 0.63, blue: 0.58)
        case .referenceVoice: Color(red: 0.95, green: 0.56, blue: 0.25)
        case .continuity: Color(red: 0.90, green: 0.39, blue: 0.62)
        case .avoidedWord: Color(red: 0.60, green: 0.47, blue: 0.31)
        }
    }
}

enum IssueSource: String, Codable {
    case local
    case system
    case ai
}

struct WritingIssue: Identifiable, Equatable {
    let id: UUID
    let category: IssueCategory
    let range: NSRange
    let excerpt: String
    let message: String
    let replacement: String?
    let source: IssueSource

    init(
        id: UUID = UUID(),
        category: IssueCategory,
        range: NSRange,
        excerpt: String,
        message: String,
        replacement: String? = nil,
        source: IssueSource = .local
    ) {
        self.id = id
        self.category = category
        self.range = range
        self.excerpt = excerpt
        self.message = message
        self.replacement = replacement
        self.source = source
    }
}

struct WritingStats: Equatable {
    var words = 0
    var sentences = 0
    var characters = 0
    var readingMinutes = 0
    var gradeLevel = 0.0
    var readabilityScore = 0

    static let empty = WritingStats()
}

struct AnalysisResult: Equatable {
    var stats: WritingStats
    var issues: [WritingIssue]

    static let empty = AnalysisResult(stats: .empty, issues: [])
}

/// Whether a document's measured reading grade is close enough to the author's target grade to
/// call it "on target", or meaningfully harder or easier than intended.
enum ReadabilityTargetStatus: Equatable {
    case onTarget
    case aboveTarget
    case belowTarget

    /// `tolerance` is how many grades away from `targetGrade` still counts as "on target," in
    /// either direction. Prose far simpler than the target is just as much a mismatch with the
    /// intended audience as prose far harder than it, so the tolerance is symmetric: a document
    /// several grades below a 12th-grade target isn't "on target" just because it isn't too hard.
    static func classify(gradeLevel: Double, targetGrade: Int, tolerance: Double = 1) -> ReadabilityTargetStatus {
        let difference = gradeLevel - Double(targetGrade)
        if difference > tolerance { return .aboveTarget }
        if difference < -tolerance { return .belowTarget }
        return .onTarget
    }
}
