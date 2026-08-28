import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

enum ResearchLibraryDisk {
    private static let metadataDirectory = ".kistulentz"
    private static let indexFile = "research-library.json"
    private static let attachmentsDirectory = "Attachments"
    private static let extractedTextDirectory = "Extracted Text"
    static let knowledgeBaseFileName = "Kistulentz Research Library.md"

    static func prepare(at root: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        for component in [metadataDirectory, attachmentsDirectory, extractedTextDirectory] {
            try manager.createDirectory(
                at: root.appendingPathComponent(component, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    static func load(from root: URL) throws -> ResearchLibraryArchive {
        try prepare(at: root)
        let url = indexURL(at: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return ResearchLibraryArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResearchLibraryArchive.self, from: Data(contentsOf: url))
    }

    static func save(_ archive: ResearchLibraryArchive, to root: URL) throws {
        try prepare(at: root)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: indexURL(at: root), options: .atomic)
        try renderKnowledgeBase(archive).write(
            to: root.appendingPathComponent(knowledgeBaseFileName),
            atomically: true,
            encoding: .utf8
        )
    }

    static func addAttachment(
        from sourceURL: URL,
        to sourceID: UUID,
        storage: ResearchAttachmentStorage,
        at root: URL
    ) throws -> ResearchAttachment {
        try prepare(at: root)
        let standardized = sourceURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            throw ResearchLibraryError.unreadableAttachment(sourceURL.lastPathComponent)
        }
        var storedPath: String?
        if storage == .managedCopy {
            let sourceFolder = root
                .appendingPathComponent(attachmentsDirectory, isDirectory: true)
                .appendingPathComponent(sourceID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            let destination = uniqueDestination(for: standardized.lastPathComponent, in: sourceFolder)
            try FileManager.default.copyItem(at: standardized, to: destination)
            storedPath = relativePath(of: destination, within: root)
        }
        return ResearchAttachment(
            displayName: standardized.lastPathComponent,
            kind: ResearchAttachmentKind.infer(from: standardized),
            storage: storage,
            storedRelativePath: storedPath,
            originalPath: standardized.path
        )
    }

    static func attachmentURL(_ attachment: ResearchAttachment, at root: URL) -> URL {
        if attachment.storage == .managedCopy, let path = attachment.storedRelativePath {
            return root.appendingPathComponent(path)
        }
        return URL(fileURLWithPath: attachment.originalPath)
    }

    static func saveExtractedText(_ text: String, for attachmentID: UUID, at root: URL) throws -> String {
        try prepare(at: root)
        let relativePath = "\(extractedTextDirectory)/\(attachmentID.uuidString).txt"
        try text.write(
            to: root.appendingPathComponent(relativePath),
            atomically: true,
            encoding: .utf8
        )
        return relativePath
    }

    static func loadExtractedText(for attachment: ResearchAttachment, at root: URL) -> String? {
        guard let path = attachment.extractedTextRelativePath else { return nil }
        return try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func removeManagedAttachment(_ attachment: ResearchAttachment, at root: URL) throws {
        if let stored = attachment.storedRelativePath {
            let url = root.appendingPathComponent(stored)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        if let extracted = attachment.extractedTextRelativePath {
            let url = root.appendingPathComponent(extracted)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private static func indexURL(at root: URL) -> URL {
        root.appendingPathComponent(metadataDirectory, isDirectory: true).appendingPathComponent(indexFile)
    }

    private static func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let original = URL(fileURLWithPath: fileName)
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        }
        return candidate
    }

    private static func relativePath(of url: URL, within root: URL) -> String {
        let rootPath = root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : url.lastPathComponent
    }

    private static func renderKnowledgeBase(_ archive: ResearchLibraryArchive) -> String {
        var lines = [
            "<!-- Generated by Kistulentz. Edit source records inside the app. -->",
            "# Kistulentz Research Library",
            "",
            "- Sources: \(archive.sources.count)",
            "- Managed and linked attachments: \(archive.sources.flatMap(\.attachments).count)",
            "",
            "## Sources",
            ""
        ]
        for source in archive.sources.sorted(by: sourceSort) {
            let year = source.issuedYear.map(String.init) ?? "n.d."
            lines.append("### [@\(source.citeKey)] \(source.title)")
            lines.append("")
            lines.append("- Type: \(source.type.title)")
            lines.append("- Creator: \(source.primaryCreatorName)")
            lines.append("- Year: \(year)")
            if !source.DOI.isEmpty { lines.append("- DOI: \(source.DOI)") }
            if !source.ISBN.isEmpty { lines.append("- ISBN: \(source.ISBN)") }
            if !source.URLString.isEmpty { lines.append("- URL: \(source.URLString)") }
            if !source.keywords.isEmpty { lines.append("- Keywords: \(source.keywords.joined(separator: ", "))") }
            lines.append("- Attachments: \(source.attachments.count)")
            if !source.libraryNotes.isEmpty {
                lines += ["", source.libraryNotes]
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func sourceSort(_ lhs: ResearchSource, _ rhs: ResearchSource) -> Bool {
        let creatorOrder = lhs.primaryCreatorName.localizedCaseInsensitiveCompare(rhs.primaryCreatorName)
        if creatorOrder != .orderedSame { return creatorOrder == .orderedAscending }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

enum ResearchTextExtractor {
    private static let maximumCharacters = 2_000_000

    static func extract(from url: URL, kind: ResearchAttachmentKind) throws -> String {
        let text: String
        switch kind {
        case .pdf:
            text = try extractPDF(url)
        case .epub:
            let reference = try EPUBProcessor.load(url: url)
            text = reference.chapters.map { "# \($0.title)\n\n\($0.text)" }.joined(separator: "\n\n")
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw ResearchLibraryError.unreadableAttachment(url.lastPathComponent)
            }
            text = try recognize(image)
        case .webArchive:
            text = try extractWebContent(url)
        case .text:
            text = try String(contentsOf: url, encoding: .utf8)
        case .other:
            if let value = try? String(contentsOf: url, encoding: .utf8) { text = value }
            else { throw ResearchLibraryError.unreadableAttachment(url.lastPathComponent) }
        }
        let normalized = text
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ResearchLibraryError.unreadableAttachment(url.lastPathComponent) }
        return String(normalized.prefix(maximumCharacters))
    }

    private static func extractPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw ResearchLibraryError.unreadableAttachment(url.lastPathComponent)
        }
        let direct = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if direct.count >= 80 { return direct }

        var pages: [String] = []
        for pageIndex in 0..<min(document.pageCount, 400) {
            guard let page = document.page(at: pageIndex) else { continue }
            let thumbnail = page.thumbnail(of: NSSize(width: 1800, height: 2400), for: .mediaBox)
            var proposed = CGRect(origin: .zero, size: thumbnail.size)
            guard let image = thumbnail.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { continue }
            let recognized = try recognize(image)
            if !recognized.isEmpty { pages.append(recognized) }
        }
        return pages.joined(separator: "\n\n")
    }

    private static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func extractWebContent(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "webarchive",
           let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let resource = root["WebMainResource"] as? [String: Any],
           let resourceData = resource["WebResourceData"] as? Data {
            return htmlText(resourceData)
        }
        return htmlText(data)
    }

    private static func htmlText(_ data: Data) -> String {
        if let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
