import Foundation

struct ManuscriptDocument: Equatable {
    let relativePath: String
    let title: String
    let text: String
}

struct ManuscriptChapterMetrics: Identifiable, Equatable {
    var id: String { relativePath }
    let relativePath: String
    let title: String
    let wordCount: Int
    let sentenceCount: Int
    let gradeLevel: Double
    let averageSentenceWords: Double
    let averageParagraphWords: Double
    let dialogueRatio: Double
    let headingCount: Int
    let adverbCount: Int
    let passiveVoiceCount: Int
    let citationCount: Int
}

enum ManuscriptEntityKind: String, Codable, CaseIterable, Identifiable {
    case person
    case place
    case organization
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .person: "Characters & People"
        case .place: "Places & Settings"
        case .organization: "Organizations & Groups"
        case .other: "Other Named Entities"
        }
    }
}

struct ManuscriptEntity: Identifiable, Equatable {
    var id: String { "\(kind.rawValue):\(name.lowercased())" }
    let name: String
    let kind: ManuscriptEntityKind
    let count: Int
    let chapters: [String]
}

struct ManuscriptFrequency: Identifiable, Equatable {
    var id: String { value.lowercased() }
    let value: String
    let count: Int
}

struct ManuscriptFinding: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let chapterPath: String?

    init(id: UUID = UUID(), title: String, detail: String, chapterPath: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.chapterPath = chapterPath
    }
}

struct ManuscriptAnalysis: Equatable {
    let projectName: String
    let kind: WritingProjectKind
    let chapters: [ManuscriptChapterMetrics]
    let entities: [ManuscriptEntity]
    let keyTerms: [ManuscriptFrequency]
    let repeatedPhrases: [ManuscriptFrequency]
    let timelineMarkers: [ManuscriptFrequency]
    let claimChecks: [ManuscriptFinding]
    let continuityChecks: [ManuscriptFinding]
    let totalWords: Int
    let totalSentences: Int
    let overallGrade: Double
    let averageSentenceWords: Double
    let averageParagraphWords: Double
    let dialogueRatio: Double
    let citationCount: Int
    let adverbCount: Int
    let passiveVoiceCount: Int
    var reportMarkdown: String
    var generatedBibleBlock: String

    static func empty(projectName: String = "Project", kind: WritingProjectKind = .fiction) -> ManuscriptAnalysis {
        ManuscriptAnalysis(
            projectName: projectName,
            kind: kind,
            chapters: [],
            entities: [],
            keyTerms: [],
            repeatedPhrases: [],
            timelineMarkers: [],
            claimChecks: [],
            continuityChecks: [],
            totalWords: 0,
            totalSentences: 0,
            overallGrade: 0,
            averageSentenceWords: 0,
            averageParagraphWords: 0,
            dialogueRatio: 0,
            citationCount: 0,
            adverbCount: 0,
            passiveVoiceCount: 0,
            reportMarkdown: "",
            generatedBibleBlock: ""
        )
    }
}

struct BibleUpdateNotice: Identifiable, Equatable {
    let id = UUID()
    let createdAt: Date
    let summary: String
    let previousText: String
    let updatedText: String
    let diff: [RevisionDiffLine]

    static func == (lhs: BibleUpdateNotice, rhs: BibleUpdateNotice) -> Bool {
        lhs.id == rhs.id
    }
}

enum BetaReaderScope: String, Codable, CaseIterable, Identifiable {
    case selection
    case chapter
    case manuscript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "Selection"
        case .chapter: "Chapter"
        case .manuscript: "Whole Manuscript"
        }
    }
}

enum BetaReaderAudience: String, Codable, CaseIterable, Identifiable {
    case fiction
    case nonfiction
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiction: "Fiction"
        case .nonfiction: "Nonfiction"
        case .general: "Both"
        }
    }
}

struct BetaReaderProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var focus: String
    var audience: BetaReaderAudience
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        focus: String,
        audience: BetaReaderAudience,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.focus = focus
        self.audience = audience
        self.isBuiltIn = isBuiltIn
    }

    static let builtIns: [BetaReaderProfile] = [
        BetaReaderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "General Reader",
            focus: "Overall engagement, clarity, momentum, confusing passages, and unanswered questions.",
            audience: .general,
            isBuiltIn: true
        ),
        BetaReaderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            name: "Structure & Momentum",
            focus: "Organization, chapter balance, pacing, transitions, escalation, and whether each section earns its place.",
            audience: .general,
            isBuiltIn: true
        ),
        BetaReaderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            name: "Character & Emotion",
            focus: "Character motivation, emotional credibility, relationships, point of view, and reader investment.",
            audience: .fiction,
            isBuiltIn: true
        ),
        BetaReaderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            name: "Continuity Reader",
            focus: "Names, chronology, settings, repeated facts, terminology, internal rules, and cross-chapter consistency.",
            audience: .general,
            isBuiltIn: true
        ),
        BetaReaderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            name: "Clarity & Accessibility",
            focus: "Reading difficulty, jargon, assumptions, definitions, sentence load, and accessibility for a general audience.",
            audience: .nonfiction,
            isBuiltIn: true
        ),
        BetaReaderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
            name: "Skeptical Evidence Reader",
            focus: "Claims, evidence, citations, counterarguments, causal leaps, precision, and unsupported generalizations.",
            audience: .nonfiction,
            isBuiltIn: true
        )
    ]
}

struct BetaReaderArchive: Codable, Equatable {
    var readers: [BetaReaderProfile] = []
}

enum BetaFeedbackSource: Equatable {
    case local
    case ai(provider: String, model: String)

    var title: String {
        switch self {
        case .local: "Local analysis"
        case .ai(let provider, let model): "\(provider) · \(model)"
        }
    }
}

struct BetaReaderFeedback: Identifiable, Equatable {
    let id: UUID
    let reader: BetaReaderProfile
    let scope: BetaReaderScope
    let source: BetaFeedbackSource
    let summary: String
    let reaction: String
    let strengths: [String]
    let concerns: [String]
    let questions: [String]

    init(
        id: UUID = UUID(),
        reader: BetaReaderProfile,
        scope: BetaReaderScope,
        source: BetaFeedbackSource,
        summary: String,
        reaction: String,
        strengths: [String],
        concerns: [String],
        questions: [String]
    ) {
        self.id = id
        self.reader = reader
        self.scope = scope
        self.source = source
        self.summary = summary
        self.reaction = reaction
        self.strengths = strengths
        self.concerns = concerns
        self.questions = questions
    }
}

struct AIBetaReaderResponse: Decodable {
    let summary: String
    let reaction: String
    let strengths: [String]
    let concerns: [String]
    let questions: [String]
}

struct AIManuscriptMarkdownResponse: Decodable {
    let summary: String
    let markdown: String
}

struct ManuscriptProjectCache: Codable, Equatable {
    var generatedBibleBlock = ""
    var aiReportMarkdown: String?
}
