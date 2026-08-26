import Foundation

enum WritingProjectKind: String, Codable, CaseIterable, Identifiable {
    case fiction
    case nonfiction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiction: "Fiction"
        case .nonfiction: "Nonfiction"
        }
    }

    var starterFileName: String {
        switch self {
        case .fiction: "Chapter 1.md"
        case .nonfiction: "Draft.md"
        }
    }

    var starterText: String {
        switch self {
        case .fiction:
            "# Chapter 1\n\nBegin the story here.\n"
        case .nonfiction:
            "# Draft\n\nBegin the manuscript here.\n"
        }
    }
}

struct WritingProjectManifest: Codable, Equatable {
    var formatVersion: Int
    var name: String
    var kind: WritingProjectKind
    var chapterOrder: [String]
    var lastOpenedChapter: String?
    var createdAt: Date

    init(
        formatVersion: Int = 1,
        name: String,
        kind: WritingProjectKind,
        chapterOrder: [String] = [],
        lastOpenedChapter: String? = nil,
        createdAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.kind = kind
        self.chapterOrder = chapterOrder
        self.lastOpenedChapter = lastOpenedChapter
        self.createdAt = createdAt
    }
}

struct ProjectChapter: Identifiable, Equatable {
    var id: String { relativePath }
    let relativePath: String
    let title: String
    let wordCount: Int
}

struct ProjectSearchResult: Identifiable, Equatable {
    var id: String { "\(chapterPath):\(range.location):\(range.length)" }
    let chapterPath: String
    let chapterTitle: String
    let line: Int
    let preview: String
    let range: NSRange
}

struct ProjectSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let chapterPath: String
    let name: String
    let reason: String
    let createdAt: Date
    let fileName: String
}

struct ProjectSnapshotIndex: Codable, Equatable {
    var snapshots: [ProjectSnapshot] = []
}

enum StyleDecisionAction: String, Codable {
    case accepted
    case declined
}

struct ProjectStyleDecision: Codable, Equatable {
    let action: StyleDecisionAction
    let category: IssueCategory
    let excerpt: String
    let replacement: String?
    var count: Int
    var lastUsedAt: Date
}

struct ProjectStyleDecisionArchive: Codable, Equatable {
    var decisions: [ProjectStyleDecision] = []
}

enum WritingProjectError: LocalizedError, Equatable {
    case invalidName
    case folderAlreadyExists
    case missingManifest
    case noMarkdownFiles
    case chapterAlreadyExists
    case invalidChapterName

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a project name that does not contain a slash or colon."
        case .folderAlreadyExists: "A folder with that project name already exists."
        case .missingManifest: "This folder has not been set up as a Kistulentz project yet."
        case .noMarkdownFiles: "This project does not contain a Markdown document."
        case .chapterAlreadyExists: "A Markdown file with that name already exists in this project."
        case .invalidChapterName: "Enter a chapter name that does not contain a slash or colon."
        }
    }
}
