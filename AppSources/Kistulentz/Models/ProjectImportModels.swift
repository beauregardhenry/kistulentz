import Foundation

struct ProjectImportSource: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var title: String
    var kind: OutlineNodeKind

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        kind: OutlineNodeKind = .chapter
    ) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.kind = kind
    }
}

struct ProjectImportDiscoveryResult: Equatable {
    var sources: [ProjectImportSource]
    var skippedItems: [String]
}

struct ProjectImportConversion: Identifiable, Equatable {
    var id: UUID { source.id }
    let source: ProjectImportSource
    let templateMarkdown: String
    let reviewCards: [DocumentImportReviewCard]
    let assets: [DocumentImportAsset]
    let notices: [DocumentImportNotice]

    init(
        source: ProjectImportSource,
        templateMarkdown: String,
        reviewCards: [DocumentImportReviewCard] = [],
        assets: [DocumentImportAsset] = [],
        notices: [DocumentImportNotice] = []
    ) {
        self.source = source
        self.templateMarkdown = templateMarkdown
        self.reviewCards = reviewCards
        self.assets = assets
        self.notices = notices
    }

    init(source: ProjectImportSource, draft: DocumentImportDraft) {
        self.init(
            source: source,
            templateMarkdown: draft.templateMarkdown,
            reviewCards: draft.reviewCards,
            assets: draft.assets,
            notices: draft.notices
        )
    }

    func renderedMarkdown(
        decisions: [UUID: DocumentTrackedChangeDecision],
        assetReferences: [UUID: String] = [:]
    ) -> String {
        var result = templateMarkdown
        for card in reviewCards {
            let decision = decisions[card.id] ?? .accept
            result = result.replacingOccurrences(
                of: DocumentImportDraft.changeToken(card.id),
                with: decision == .accept ? card.acceptedMarkdown : card.rejectedMarkdown
            )
        }
        for asset in assets {
            let reference = assetReferences[asset.id] ?? DocumentImportFilename.safe(asset.suggestedFilename)
            let destination = reference.contains(" ") ? "<\(reference)>" : reference
            let alt = asset.altText.replacingOccurrences(of: "]", with: "\\]")
            result = result.replacingOccurrences(
                of: DocumentImportDraft.assetToken(asset.id),
                with: "![\(alt)](\(destination))"
            )
        }
        return DocumentImportDraft.normalizedMarkdown(result)
    }
}

struct ProjectImportFailure: Identifiable, Equatable {
    var id: UUID { source.id }
    let source: ProjectImportSource
    let message: String
}

enum ProjectImportDestination: String, CaseIterable, Identifiable {
    case combinedMarkdown
    case newProject
    case currentProject

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combinedMarkdown: "One combined Markdown file"
        case .newProject: "A new Kistulentz project"
        case .currentProject: "The current project"
        }
    }
}

struct ProjectImportWriteResult: Equatable {
    let rootURL: URL
    let importedPaths: [String]
    let selectedPath: String?
}

enum ProjectImportError: LocalizedError, Equatable {
    case noSupportedDocuments
    case unreadableMarkdown
    case invalidHierarchy(String)
    case unresolvedTrackedChanges
    case destinationExists(String)
    case invalidProjectName
    case noCurrentProject
    case currentProjectSaveFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noSupportedDocuments:
            "No supported documents were found. Choose Markdown, DOCX, RTF, RTFD, HTML, ODT, or plain-text files."
        case .unreadableMarkdown:
            "The Markdown document could not be decoded as text."
        case .invalidHierarchy(let message):
            message
        case .unresolvedTrackedChanges:
            "Accept or reject every tracked change before finishing the import."
        case .destinationExists(let name):
            "A file or folder named \(name) already exists. Choose another destination."
        case .invalidProjectName:
            "Enter a project name that does not contain a slash or colon."
        case .noCurrentProject:
            "Open a Kistulentz project before importing into the current project."
        case .currentProjectSaveFailed:
            "Kistulentz could not save the current project before importing. The new documents were not added."
        case .cancelled:
            "The project import was cancelled. No documents were added."
        }
    }
}
