import AppKit
import Foundation
import UniformTypeIdentifiers

enum DocumentImportService {
    private static let maximumDocumentBytes: UInt64 = 250_000_000

    static func load(from url: URL) throws -> DocumentImportDraft {
        guard let format = DocumentImportFormat.format(for: url) else {
            throw DocumentImportError.unsupportedFormat(url.pathExtension.lowercased())
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        if format != .rtfd {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard size > 0 else { throw DocumentImportError.unreadableDocument }
            guard size <= maximumDocumentBytes else { throw DocumentImportError.documentTooLarge }
        }

        let draft: DocumentImportDraft
        switch format {
        case .plainText:
            draft = try PlainTextDocumentImporter.load(from: url)
        case .docx:
            draft = try DOCXDocumentImporter.load(from: url)
        case .html:
            draft = try HTMLDocumentImporter.load(from: url)
        case .rtf:
            draft = try AttributedDocumentImporter.load(from: url, format: .rtf, documentType: .rtf)
        case .rtfd:
            draft = try AttributedDocumentImporter.load(from: url, format: .rtfd, documentType: .rtfd)
        case .odt:
            draft = try AttributedDocumentImporter.load(from: url, format: .odt, documentType: .openDocument)
        }

        guard !draft.renderedMarkdown(decisions: [:]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.emptyDocument
        }
        return draft
    }

    static func save(
        _ draft: DocumentImportDraft,
        decisions: [UUID: DocumentTrackedChangeDecision],
        to outputURL: URL
    ) throws -> DocumentImportSaveResult {
        guard Set(decisions.keys).isSuperset(of: Set(draft.reviewCards.map(\.id))) else {
            throw DocumentImportError.unresolvedTrackedChanges
        }
        guard outputURL.standardizedFileURL != draft.sourceURL.standardizedFileURL else {
            throw DocumentImportError.sourceWouldBeOverwritten
        }
        guard outputURL.pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
            throw DocumentImportError.markdownExtensionRequired
        }

        let fileManager = FileManager.default
        var assetFolderURL: URL?
        var createdAssetFolder = false

        do {
            if !draft.assets.isEmpty {
                let parent = outputURL.deletingLastPathComponent()
                let base = outputURL.deletingPathExtension().lastPathComponent + "-assets"
                var candidate = parent.appendingPathComponent(base, isDirectory: true)
                var suffix = 2
                while fileManager.fileExists(atPath: candidate.path) {
                    candidate = parent.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
                    suffix += 1
                }
                try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
                createdAssetFolder = true
                assetFolderURL = candidate
                for asset in draft.assets {
                    try asset.data.write(
                        to: candidate.appendingPathComponent(DocumentImportFilename.safe(asset.suggestedFilename)),
                        options: .atomic
                    )
                }
            }

            let markdown = draft.renderedMarkdown(
                decisions: decisions,
                assetFolderName: assetFolderURL?.lastPathComponent
            )
            try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
            return DocumentImportSaveResult(markdownURL: outputURL, assetFolderURL: assetFolderURL)
        } catch {
            if createdAssetFolder, let assetFolderURL {
                try? fileManager.removeItem(at: assetFolderURL)
            }
            throw error
        }
    }

    static func decodedText(_ data: Data) -> String? {
        if let value = String(data: data, encoding: .utf8) { return value }
        if let value = String(data: data, encoding: .utf16) { return value }
        if let value = String(data: data, encoding: .utf16LittleEndian) { return value }
        if let value = String(data: data, encoding: .utf16BigEndian) { return value }
        return String(data: data, encoding: .isoLatin1)
    }

    static func uniqueAssets(_ assets: [DocumentImportAsset]) -> [DocumentImportAsset] {
        var used: Set<String> = []
        return assets.map { asset in
            let safe = DocumentImportFilename.safe(asset.suggestedFilename)
            let path = URL(fileURLWithPath: safe)
            let stem = path.deletingPathExtension().lastPathComponent
            let ext = path.pathExtension
            var candidate = safe
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
                suffix += 1
            }
            used.insert(candidate.lowercased())
            return DocumentImportAsset(
                id: asset.id,
                suggestedFilename: candidate,
                altText: asset.altText,
                data: asset.data
            )
        }
    }

    static func uniqueNotices(_ notices: [DocumentImportNotice]) -> [DocumentImportNotice] {
        var titles: Set<String> = []
        return notices.filter { titles.insert($0.title).inserted }
    }
}
