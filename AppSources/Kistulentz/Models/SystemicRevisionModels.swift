import Foundation

enum RevisionPass: String, Codable, CaseIterable, Identifiable {
    case structure
    case pacing
    case continuity
    case characterAndPeople
    case argumentAndEvidence
    case voiceAndStyle
    case lineEditing

    var id: String { rawValue }
    var title: String {
        switch self {
        case .structure: "Structure"
        case .pacing: "Pacing"
        case .continuity: "Continuity"
        case .characterAndPeople: "Characters & People"
        case .argumentAndEvidence: "Argument & Evidence"
        case .voiceAndStyle: "Voice & Style"
        case .lineEditing: "Line Editing"
        }
    }

    var systemImage: String {
        switch self {
        case .structure: "rectangle.3.group"
        case .pacing: "waveform.path.ecg"
        case .continuity: "point.3.connected.trianglepath.dotted"
        case .characterAndPeople: "person.2"
        case .argumentAndEvidence: "checkmark.seal"
        case .voiceAndStyle: "quote.bubble"
        case .lineEditing: "text.badge.checkmark"
        }
    }
}

enum RevisionFindingClassification: String, Codable, CaseIterable, Identifiable {
    case confirmedProblem
    case probableProblem
    case authorQuestion
    case opportunity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .confirmedProblem: "Confirmed Problem"
        case .probableProblem: "Probable Problem"
        case .authorQuestion: "Author Question"
        case .opportunity: "Opportunity"
        }
    }

    var rank: Int {
        switch self {
        case .confirmedProblem: 0
        case .probableProblem: 1
        case .authorQuestion: 2
        case .opportunity: 3
        }
    }
}

enum RevisionFindingStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case resolved
    case dismissed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum RevisionFindingOrigin: String, Codable, Equatable {
    case local
    case ai
}

struct SystemicRevisionFinding: Codable, Identifiable, Equatable {
    var id: UUID
    var signature: String
    var revisionPass: RevisionPass
    var classification: RevisionFindingClassification
    var status: RevisionFindingStatus
    var title: String
    var detail: String
    var chapterPath: String?
    var excerpt: String
    var replacement: String?
    var origin: RevisionFindingOrigin
    var provider: String?
    var model: String?
    var createdAt: Date
    var lastSeenAt: Date

    init(
        id: UUID = UUID(),
        signature: String,
        revisionPass: RevisionPass,
        classification: RevisionFindingClassification,
        status: RevisionFindingStatus = .open,
        title: String,
        detail: String,
        chapterPath: String? = nil,
        excerpt: String = "",
        replacement: String? = nil,
        origin: RevisionFindingOrigin = .local,
        provider: String? = nil,
        model: String? = nil,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.signature = signature
        self.revisionPass = revisionPass
        self.classification = classification
        self.status = status
        self.title = title
        self.detail = detail
        self.chapterPath = chapterPath
        self.excerpt = excerpt
        self.replacement = replacement
        self.origin = origin
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

struct RevisionGoal: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var revisionPass: RevisionPass
    var isComplete: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        revisionPass: RevisionPass,
        isComplete: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.revisionPass = revisionPass
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}

struct SystemicRevisionArchive: Codable, Equatable {
    var schemaVersion = KistulentzProjectFormat.currentVersion
    var findings: [SystemicRevisionFinding] = []
    var goals: [RevisionGoal] = []
    var lastLocalScanAt: Date?
}

struct RevisionChange: Codable, Identifiable, Equatable {
    var id: UUID
    var findingID: UUID?
    var chapterPath: String
    var originalText: String
    var replacementText: String
    var explanation: String
    var isIncluded: Bool
    var conflict: String?

    init(
        id: UUID = UUID(),
        findingID: UUID? = nil,
        chapterPath: String,
        originalText: String,
        replacementText: String,
        explanation: String,
        isIncluded: Bool = true,
        conflict: String? = nil
    ) {
        self.id = id
        self.findingID = findingID
        self.chapterPath = chapterPath
        self.originalText = originalText
        self.replacementText = replacementText
        self.explanation = explanation
        self.isIncluded = isIncluded
        self.conflict = conflict
    }
}

struct RevisionChangeSet: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var summary: String
    var changes: [RevisionChange]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        changes: [RevisionChange],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.changes = changes
        self.createdAt = createdAt
    }

    var includedChanges: [RevisionChange] { changes.filter(\.isIncluded) }
    var hasConflicts: Bool { includedChanges.contains { $0.conflict != nil } }
    var hasChanges: Bool { includedChanges.contains { $0.originalText != $0.replacementText } }
}

struct AISystemicRevisionResponse: Decodable {
    let summary: String
    let findings: [AISystemicRevisionFinding]
}

struct AISystemicRevisionFinding: Decodable {
    let revisionPass: String
    let classification: String
    let title: String
    let detail: String
    let chapterPath: String
    let excerpt: String
    let replacement: String
}

enum SystemicRevisionError: LocalizedError, Equatable {
    case stalePassage(String)
    case duplicatePassage(String)
    case overlappingChanges(String)
    case noConcreteChanges
    case filesChanged

    var errorDescription: String? {
        switch self {
        case .stalePassage(let path): "A proposed passage no longer matches \(path). Recheck the manuscript before applying it."
        case .duplicatePassage(let path): "A proposed passage occurs more than once in \(path), so Kistulentz cannot replace it safely."
        case .overlappingChanges(let path): "Two proposed changes overlap in \(path). Choose only one of them."
        case .noConcreteChanges: "No selected findings contain safe, concrete replacements."
        case .filesChanged: "One or more affected files changed after this revision. Kistulentz left them untouched instead of risking lost work."
        }
    }
}
