import Foundation
import SwiftUI

enum IssueCategory: String, Codable, CaseIterable, Identifiable {
    case hardSentence
    case veryHardSentence
    case adverb
    case passiveVoice
    case structuralComplexity
    case complexPhrase
    case spelling
    case grammar
    case aiSuggestion
    case referenceVoice
    case continuity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hardSentence: "Hard to read"
        case .veryHardSentence: "Very hard to read"
        case .adverb: "Adverb"
        case .passiveVoice: "Passive voice"
        case .structuralComplexity: "Sentence structure"
        case .complexPhrase: "Simpler alternative"
        case .spelling: "Spelling"
        case .grammar: "Grammar"
        case .aiSuggestion: "AI suggestion"
        case .referenceVoice: "Reference voice"
        case .continuity: "Continuity"
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
        case .spelling: "Spelling"
        case .grammar: "Grammar"
        case .aiSuggestion: "AI"
        case .referenceVoice: "Voice"
        case .continuity: "Continuity"
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
        case .spelling: Color(red: 0.92, green: 0.27, blue: 0.32)
        case .grammar: Color(red: 0.25, green: 0.68, blue: 0.85)
        case .aiSuggestion: Color(red: 0.21, green: 0.63, blue: 0.58)
        case .referenceVoice: Color(red: 0.95, green: 0.56, blue: 0.25)
        case .continuity: Color(red: 0.90, green: 0.39, blue: 0.62)
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

struct AIReview: Decodable {
    let summary: String
    let gradeEstimate: Double
    let polishedText: String
    let suggestions: [AISuggestion]
}

struct AISuggestion: Decodable, Identifiable {
    var id: String { "\(original)|\(replacement)|\(explanation)" }
    let original: String
    let replacement: String
    let explanation: String
    let category: String
}
