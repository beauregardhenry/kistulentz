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

    /// A question to show in Practice Mode (`AppSettings.isPracticeModeEnabled`) instead of a
    /// one-click fix, for a category where there's a craft judgment worth practicing. `nil` for
    /// categories that are corrections of an objective error (spelling, grammar), a factual
    /// consistency check rather than a style choice (continuity), or a suggestion the author
    /// already asked for explicitly through its own review flow (an AI suggestion) -- withholding
    /// those wouldn't teach anything, only add friction.
    var practicePrompt: String? {
        switch self {
        case .hardSentence, .veryHardSentence:
            "This sentence is hard to follow. Where would you split it, or what would you cut?"
        case .adverb:
            "Can you cut this adverb and reach for a stronger verb instead?"
        case .passiveVoice:
            "Who's doing the action here? Try rewriting with them as the subject."
        case .structuralComplexity:
            "This sentence's shape is doing a lot of work. What's the simplest way to say it?"
        case .complexPhrase:
            "Is there a plainer way to say this?"
        case .aiTell:
            "This phrasing is a familiar pattern. What would you actually say here?"
        case .referenceVoice:
            "How does this compare to the voice you're matching? What would close the gap?"
        case .avoidedWord:
            "This is a word you've chosen to avoid. What's your replacement?"
        case .spelling, .grammar, .aiSuggestion, .continuity:
            nil
        }
    }

    /// The craft principle behind this category, shown on demand (an expandable "Why this
    /// matters" disclosure in `IssueCard`) rather than always-on, so the sidebar stays scannable.
    /// This is deliberately a *reason*, not a restatement of the category's `title` or `message` --
    /// every case gets one, including the objective categories `practicePrompt` skips, because
    /// understanding why a typo or a grammar slip costs a reader's trust is itself worth knowing,
    /// even though there's no craft judgment to practice on the fix itself.
    var whyThisMatters: String {
        switch self {
        case .hardSentence:
            "Long, dense sentences ask a reader to hold several ideas in mind before any of them resolve. Most readers start skimming once that load gets too high, so the ideas land softer than they should."
        case .veryHardSentence:
            "At this length, most readers lose the thread before reaching the point. Splitting it up doesn't dumb the idea down -- it usually sharpens it, because you're forced to decide what in it actually matters."
        case .adverb:
            "An adverb often patches over a vague verb instead of replacing it. \"Walked quickly\" and \"ran\" describe roughly the same thing, but the second one shows it -- the reader pictures the motion instead of being told its speed."
        case .passiveVoice:
            "Passive voice hides who's doing the action, which can drain a sentence of its energy and its accountability. Naming the actor usually makes the sentence more concrete and easier to follow."
        case .structuralComplexity:
            "A sentence can be grammatically correct and still ask too much of its shape -- clauses nested inside clauses, or a subject separated from its verb by a long detour. The reader has to untangle the structure before they can absorb the meaning."
        case .complexPhrase:
            "A longer or more formal phrase can feel more precise, but it usually just adds friction. The plainer version almost always says the same thing faster."
        case .aiTell:
            "Constructions like \"not just X, but Y,\" stacked qualifiers, or a rhetorical wind-up before the actual point show up disproportionately in AI-generated text. Leaning on them is a good way to sound like everyone else's first draft instead of your own."
        case .spelling:
            "A misspelled word breaks a reader's attention for a moment they don't get back. It's rarely about the word itself -- it's the interruption."
        case .grammar:
            "A grammar slip is a small thing that reads as a big thing -- it signals the sentence wasn't checked, which makes a reader trust the rest of it a little less."
        case .aiSuggestion:
            "This suggestion was generated from the exact request you approved. Review it the way you'd review any collaborator's draft -- a starting point, not a final word."
        case .referenceVoice:
            "Matching a reference's voice isn't about copying its words -- it's noticing what choices make that voice distinct (sentence length, formality, how it handles tension) and asking whether your passage is making similar choices on purpose."
        case .continuity:
            "A reader builds a mental model of your story or argument as they go. Inconsistencies quietly damage their trust in that model, even when they can't name exactly what felt off."
        case .avoidedWord:
            "You already decided this word doesn't belong in this project's voice. The flag isn't new information -- it's a reminder of a choice you already made."
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
