import Foundation

enum OutlineNodeKind: String, Codable, CaseIterable, Identifiable {
    case part
    case chapter
    case scene
    case section

    var id: String { rawValue }

    var title: String {
        switch self {
        case .part: "Part"
        case .chapter: "Chapter"
        case .scene: "Scene"
        case .section: "Section"
        }
    }

    var isContainer: Bool { self == .part || self == .chapter }
}

enum OutlineDraftStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case drafting
    case revised
    case final

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: "Planned"
        case .drafting: "Drafting"
        case .revised: "Revised"
        case .final: "Final"
        }
    }
}

struct OutlineNodeMetadata: Codable, Equatable {
    var synopsis = ""
    var suggestedSynopsis = ""
    var purpose = ""
    var status: OutlineDraftStatus = .planned
    var labels: [String] = []
    var notes = ""
    var targetWordCount: Int?
    var includedInExport = true

    // Fiction-oriented fields.
    var pointOfView = ""
    var characters: [String] = []
    var location = ""
    var storyDateTime = ""
    var sceneGoal = ""
    var conflict = ""
    var outcome = ""
    var emotionalMovement = ""

    // Nonfiction-oriented fields.
    var centralClaim = ""
    var evidenceStatus = ""
    var sources: [String] = []
    var concepts: [String] = []
    var intendedAudience = ""
    var counterargument = ""
    var targetReadingGrade: Int?
    var readerTakeaway = ""
    var modifiedAt = Date()
}

struct OutlineNode: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var kind: OutlineNodeKind
    var relativePath: String?
    var metadata: OutlineNodeMetadata
    var children: [OutlineNode]

    init(
        id: UUID = UUID(),
        title: String,
        kind: OutlineNodeKind,
        relativePath: String? = nil,
        metadata: OutlineNodeMetadata = OutlineNodeMetadata(),
        children: [OutlineNode] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.relativePath = relativePath
        self.metadata = metadata
        self.children = children
    }
}

struct ProjectOutlineArchive: Codable, Equatable {
    var formatVersion = KistulentzProjectFormat.currentVersion
    var nodes: [OutlineNode] = []
}

struct OutlineFlatRow: Identifiable, Equatable {
    var id: UUID { node.id }
    let node: OutlineNode
    let depth: Int
    let parentID: UUID?
}

struct OutlineFileMove: Identifiable, Equatable {
    let id: UUID
    let nodeID: UUID
    let sourcePath: String
    var destinationPath: String
    var isIncluded: Bool
    var conflict: String?

    init(
        id: UUID = UUID(),
        nodeID: UUID,
        sourcePath: String,
        destinationPath: String,
        isIncluded: Bool = true,
        conflict: String? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.isIncluded = isIncluded
        self.conflict = conflict
    }
}

struct OutlineFileOrganizationPlan: Equatable {
    var moves: [OutlineFileMove]

    var includedMoves: [OutlineFileMove] { moves.filter(\.isIncluded) }
    var hasConflicts: Bool { includedMoves.contains { $0.conflict != nil } }
    var hasChanges: Bool { includedMoves.contains { $0.sourcePath != $0.destinationPath } }
}

struct HeadingSplitSection: Identifiable, Equatable {
    let id: UUID
    let title: String
    let markdown: String
    var fileName: String
    var isIncluded: Bool

    init(
        id: UUID = UUID(),
        title: String,
        markdown: String,
        fileName: String,
        isIncluded: Bool = true
    ) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.fileName = fileName
        self.isIncluded = isIncluded
    }
}

struct HeadingSplitPlan: Equatable {
    let nodeID: UUID
    let chapterPath: String
    let remainingMarkdown: String
    var sections: [HeadingSplitSection]

    var includedSections: [HeadingSplitSection] { sections.filter(\.isIncluded) }

    var resultingChapterMarkdown: String {
        let retained = sections.filter { !$0.isIncluded }.map(\.markdown)
        let pieces = ([remainingMarkdown] + retained)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? "" : pieces.joined(separator: "\n\n") + "\n"
    }
}

struct AIOutlineSynopsisResponse: Decodable, Equatable {
    let summary: String
    let synopsis: String
}

enum ProjectOutlineError: LocalizedError, Equatable {
    case missingNode
    case invalidHierarchy
    case nodeHasNoFile
    case noHeadings
    case invalidDestination(String)
    case fileConflict(String)
    case filesChanged

    var errorDescription: String? {
        switch self {
        case .missingNode: "That outline item no longer exists."
        case .invalidHierarchy: "That item cannot be placed at this level of the outline."
        case .nodeHasNoFile: "This outline item does not have a Markdown file."
        case .noHeadings: "No level-two Markdown headings were found to split."
        case .invalidDestination(let path): "The proposed destination is not a safe project-relative path: \(path)"
        case .fileConflict(let path): "A file or folder already exists at \(path). Edit the destination before continuing."
        case .filesChanged: "The affected Markdown files changed after this operation. Kistulentz left them untouched instead of risking lost work."
        }
    }
}
