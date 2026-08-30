import Foundation
import UniformTypeIdentifiers

enum DocumentImportFormat: String, CaseIterable, Identifiable, Equatable {
    case plainText
    case docx
    case rtf
    case rtfd
    case html
    case odt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: "Plain Text"
        case .docx: "Microsoft Word"
        case .rtf: "Rich Text Format"
        case .rtfd: "Rich Text with Attachments"
        case .html: "HTML"
        case .odt: "OpenDocument Text"
        }
    }

    var filenameExtensions: [String] {
        switch self {
        case .plainText: ["txt", "text"]
        case .docx: ["docx"]
        case .rtf: ["rtf"]
        case .rtfd: ["rtfd"]
        case .html: ["html", "htm"]
        case .odt: ["odt"]
        }
    }

    var contentType: UTType? {
        switch self {
        case .plainText: .plainText
        case .rtf: .rtf
        case .rtfd: .rtfd
        case .html: .html
        case .docx: UTType(filenameExtension: "docx")
        case .odt: UTType(filenameExtension: "odt")
        }
    }

    static var importableContentTypes: [UTType] {
        var seen: Set<String> = []
        return allCases.compactMap(\.contentType).filter { seen.insert($0.identifier).inserted }
    }

    static func format(for url: URL) -> DocumentImportFormat? {
        let pathExtension = url.pathExtension.lowercased()
        return allCases.first { $0.filenameExtensions.contains(pathExtension) }
    }
}

enum DocumentImportNoticeSeverity: String, Equatable {
    case information
    case warning
}

struct DocumentImportNotice: Identifiable, Equatable {
    let id: UUID
    let severity: DocumentImportNoticeSeverity
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        severity: DocumentImportNoticeSeverity,
        title: String,
        detail: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

enum DocumentTrackedChangeKind: String, Equatable {
    case insertion
    case deletion

    var title: String {
        switch self {
        case .insertion: "Inserted text"
        case .deletion: "Deleted text"
        }
    }
}

enum DocumentTrackedChangeDecision: String, CaseIterable, Identifiable, Equatable {
    case accept
    case reject

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DocumentImportReviewCard: Identifiable, Equatable {
    let id: UUID
    let kind: DocumentTrackedChangeKind
    let author: String?
    let date: Date?
    let changedMarkdown: String

    init(
        id: UUID = UUID(),
        kind: DocumentTrackedChangeKind,
        author: String? = nil,
        date: Date? = nil,
        changedMarkdown: String
    ) {
        self.id = id
        self.kind = kind
        self.author = author
        self.date = date
        self.changedMarkdown = changedMarkdown
    }

    var acceptedMarkdown: String {
        kind == .insertion ? changedMarkdown : ""
    }

    var rejectedMarkdown: String {
        kind == .deletion ? changedMarkdown : ""
    }
}

struct DocumentImportAsset: Identifiable, Equatable {
    let id: UUID
    let suggestedFilename: String
    let altText: String
    let data: Data

    init(
        id: UUID = UUID(),
        suggestedFilename: String,
        altText: String,
        data: Data
    ) {
        self.id = id
        self.suggestedFilename = suggestedFilename
        self.altText = altText
        self.data = data
    }
}

struct DocumentImportDraft: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let format: DocumentImportFormat
    let templateMarkdown: String
    let reviewCards: [DocumentImportReviewCard]
    let assets: [DocumentImportAsset]
    let notices: [DocumentImportNotice]

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        format: DocumentImportFormat,
        templateMarkdown: String,
        reviewCards: [DocumentImportReviewCard] = [],
        assets: [DocumentImportAsset] = [],
        notices: [DocumentImportNotice] = []
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.format = format
        self.templateMarkdown = templateMarkdown
        self.reviewCards = reviewCards
        self.assets = assets
        self.notices = notices
    }

    var suggestedMarkdownFilename: String {
        sourceURL.deletingPathExtension().lastPathComponent + ".md"
    }

    func renderedMarkdown(
        decisions: [UUID: DocumentTrackedChangeDecision],
        assetFolderName: String? = nil
    ) -> String {
        var result = templateMarkdown
        for card in reviewCards {
            let decision = decisions[card.id] ?? .accept
            result = result.replacingOccurrences(
                of: Self.changeToken(card.id),
                with: decision == .accept ? card.acceptedMarkdown : card.rejectedMarkdown
            )
        }

        for asset in assets {
            let folder = assetFolderName ?? sourceURL.deletingPathExtension().lastPathComponent + "-assets"
            let path = "\(folder)/\(DocumentImportFilename.safe(asset.suggestedFilename))"
            let destination = path.contains(" ") ? "<\(path)>" : path
            let alt = asset.altText.replacingOccurrences(of: "]", with: "\\]")
            result = result.replacingOccurrences(
                of: Self.assetToken(asset.id),
                with: "![\(alt)](\(destination))"
            )
        }

        return Self.normalizedMarkdown(result)
    }

    static func changeToken(_ id: UUID) -> String {
        "KISTULENTZIMPORTCHANGE\(id.uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    static func assetToken(_ id: UUID) -> String {
        "KISTULENTZIMPORTASSET\(id.uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    static func normalizedMarkdown(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

struct DocumentImportSaveResult: Equatable {
    let markdownURL: URL
    let assetFolderURL: URL?
}

enum DocumentImportFilename {
    static func safe(_ proposed: String) -> String {
        let fallback = "attachment"
        let clean = proposed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || clean == "." || clean == ".." ? fallback : clean
    }
}

enum DocumentImportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unreadableDocument
    case documentTooLarge
    case unsafeArchive
    case extractionFailed(String)
    case emptyDocument
    case unresolvedTrackedChanges
    case sourceWouldBeOverwritten
    case markdownExtensionRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let value): "Kistulentz cannot import .\(value) documents yet."
        case .unreadableDocument: "The selected document could not be read."
        case .documentTooLarge: "The selected document is too large to import safely."
        case .unsafeArchive: "The selected document contains unsafe or malformed archive paths."
        case .extractionFailed(let message): "The selected document could not be unpacked: \(message)"
        case .emptyDocument: "The selected document does not contain readable text."
        case .unresolvedTrackedChanges: "Accept or reject every tracked change before saving the Markdown copy."
        case .sourceWouldBeOverwritten: "Choose a different location so the original document remains untouched."
        case .markdownExtensionRequired: "The imported copy must be saved with an .md extension."
        }
    }
}
