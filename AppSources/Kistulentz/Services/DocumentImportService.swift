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
            draft = try loadPlainText(from: url)
        case .docx:
            draft = try DOCXDocumentImporter.load(from: url)
        case .html:
            draft = try loadHTML(from: url)
        case .rtf:
            draft = try loadAttributedDocument(from: url, format: .rtf, documentType: .rtf)
        case .rtfd:
            draft = try loadAttributedDocument(from: url, format: .rtfd, documentType: .rtfd)
        case .odt:
            draft = try loadAttributedDocument(from: url, format: .odt, documentType: .openDocument)
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

    private static func loadPlainText(from url: URL) throws -> DocumentImportDraft {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = decodedText(data) else { throw DocumentImportError.unreadableDocument }
        return DocumentImportDraft(
            sourceURL: url,
            format: .plainText,
            templateMarkdown: text,
            notices: [
                DocumentImportNotice(
                    severity: .information,
                    title: "Plain text preserved",
                    detail: "Kistulentz will save a separate UTF-8 Markdown copy. The selected text file remains unchanged."
                )
            ]
        )
    }

    private static func loadHTML(from url: URL) throws -> DocumentImportDraft {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let source = decodedText(data) else { throw DocumentImportError.unreadableDocument }
        let sanitized = HTMLImportSanitizer.prepare(source, sourceURL: url)
        guard let cleanData = sanitized.html.data(using: .utf8) else {
            throw DocumentImportError.unreadableDocument
        }
        let attributed = try NSAttributedString(
            data: cleanData,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        )
        let converted = AttributedMarkdownImporter.convert(
            attributed,
            seededAssets: sanitized.assets,
            seededNotices: sanitized.notices
        )
        return richDraft(
            sourceURL: url,
            format: .html,
            conversion: converted,
            layoutDetail: "CSS, page layout, forms, scripts, and interactive elements are not carried into Markdown."
        )
    }

    private static func loadAttributedDocument(
        from url: URL,
        format: DocumentImportFormat,
        documentType: NSAttributedString.DocumentType
    ) throws -> DocumentImportDraft {
        let attributed: NSAttributedString
        if format == .rtfd || format == .odt {
            attributed = try NSAttributedString(
                url: url,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
        } else {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            attributed = try NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
        }
        let converted = AttributedMarkdownImporter.convert(attributed)
        return richDraft(
            sourceURL: url,
            format: format,
            conversion: converted,
            layoutDetail: "Page geometry, headers, footers, and exact typography are not carried into Markdown."
        )
    }

    private static func richDraft(
        sourceURL: URL,
        format: DocumentImportFormat,
        conversion: AttributedMarkdownImportResult,
        layoutDetail: String
    ) -> DocumentImportDraft {
        var notices = conversion.notices
        notices.insert(DocumentImportNotice(
            severity: .information,
            title: "Original preserved",
            detail: "Kistulentz creates a separate Markdown copy and never rewrites the selected \(format.title) document."
        ), at: 0)
        notices.append(DocumentImportNotice(
            severity: .warning,
            title: "Review the converted structure",
            detail: layoutDetail
        ))
        return DocumentImportDraft(
            sourceURL: sourceURL,
            format: format,
            templateMarkdown: conversion.markdown,
            assets: uniqueAssets(conversion.assets),
            notices: uniqueNotices(notices)
        )
    }

    fileprivate static func decodedText(_ data: Data) -> String? {
        if let value = String(data: data, encoding: .utf8) { return value }
        if let value = String(data: data, encoding: .utf16) { return value }
        if let value = String(data: data, encoding: .utf16LittleEndian) { return value }
        if let value = String(data: data, encoding: .utf16BigEndian) { return value }
        return String(data: data, encoding: .isoLatin1)
    }

    fileprivate static func uniqueAssets(_ assets: [DocumentImportAsset]) -> [DocumentImportAsset] {
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

    fileprivate static func uniqueNotices(_ notices: [DocumentImportNotice]) -> [DocumentImportNotice] {
        var titles: Set<String> = []
        return notices.filter { titles.insert($0.title).inserted }
    }
}

private struct AttributedMarkdownImportResult {
    var markdown: String
    var assets: [DocumentImportAsset]
    var notices: [DocumentImportNotice]
}

private enum AttributedMarkdownImporter {
    static func convert(
        _ attributed: NSAttributedString,
        seededAssets: [DocumentImportAsset] = [],
        seededNotices: [DocumentImportNotice] = []
    ) -> AttributedMarkdownImportResult {
        let string = attributed.string as NSString
        var assets = seededAssets
        var notices = seededNotices
        var paragraphs: [String] = []
        var location = 0

        while location < string.length {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            var contentRange = paragraphRange
            while contentRange.length > 0 {
                let scalar = string.character(at: NSMaxRange(contentRange) - 1)
                if scalar == 10 || scalar == 13 {
                    contentRange.length -= 1
                } else {
                    break
                }
            }

            let style = attributed.attribute(
                .paragraphStyle,
                at: min(contentRange.location, max(attributed.length - 1, 0)),
                effectiveRange: nil
            ) as? NSParagraphStyle
            let raw = contentRange.length > 0 ? string.substring(with: contentRange) : ""
            let markerRange = raw.range(of: #"^\t[^\t]+\t"#, options: .regularExpression)
            let marker = markerRange.map { String(raw[$0]) }
            if let markerRange {
                let skipped = (raw as NSString).range(of: String(raw[markerRange])).length
                contentRange.location += skipped
                contentRange.length = max(0, contentRange.length - skipped)
            }

            var inline = renderInline(
                attributed,
                range: contentRange,
                suppressBold: (style?.headerLevel ?? 0) > 0,
                assets: &assets,
                notices: &notices
            ).trimmingCharacters(in: .whitespaces)

            if inline.isEmpty {
                paragraphs.append("")
            } else if let style, style.headerLevel > 0 {
                let level = min(max(style.headerLevel, 1), 6)
                paragraphs.append(String(repeating: "#", count: level) + " " + inline)
            } else if let style, !style.textLists.isEmpty {
                let depth = max(0, style.textLists.count - 1)
                let ordered = marker?.range(of: #"\d"#, options: .regularExpression) != nil
                let prefix = ordered ? "1. " : "- "
                paragraphs.append(String(repeating: "  ", count: depth) + prefix + inline)
            } else if let style, !style.textBlocks.isEmpty {
                inline = inline.replacingOccurrences(of: "\n", with: "\n> ")
                paragraphs.append("> " + inline)
            } else {
                paragraphs.append(inline)
            }

            location = NSMaxRange(paragraphRange)
        }

        if !assets.isEmpty {
            notices.append(DocumentImportNotice(
                severity: .information,
                title: "Images will be copied",
                detail: "Imported images will be placed in a sibling assets folder beside the Markdown file."
            ))
        }

        return AttributedMarkdownImportResult(
            markdown: DocumentImportDraft.normalizedMarkdown(paragraphs.joined(separator: "\n\n")),
            assets: DocumentImportService.uniqueAssets(assets),
            notices: DocumentImportService.uniqueNotices(notices)
        )
    }

    private static func renderInline(
        _ attributed: NSAttributedString,
        range: NSRange,
        suppressBold: Bool,
        assets: inout [DocumentImportAsset],
        notices: inout [DocumentImportNotice]
    ) -> String {
        guard range.length > 0 else { return "" }
        let source = attributed.string as NSString
        var result = ""

        attributed.enumerateAttributes(in: range) { attributes, runRange, _ in
            let raw = source.substring(with: runRange)
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                if let asset = asset(from: attachment, number: assets.count + 1) {
                    assets.append(asset)
                    result += DocumentImportDraft.assetToken(asset.id)
                } else {
                    result += "[Attachment omitted during import]"
                    notices.append(DocumentImportNotice(
                        severity: .warning,
                        title: "An attachment could not be copied",
                        detail: "The conversion preview contains a placeholder where Kistulentz could not read embedded attachment data."
                    ))
                }
                return
            }

            var value = escapeMarkdown(raw)
            guard !value.isEmpty else { return }
            if let link = attributes[.link] {
                let destination = (link as? URL)?.absoluteString ?? String(describing: link)
                value = "[\(value)](<\(destination.replacingOccurrences(of: ">", with: "%3E"))>)"
            }
            if let strike = attributes[.strikethroughStyle] as? NSNumber, strike.intValue != 0 {
                value = "~~\(value)~~"
            }
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.italic) { value = "*\(value)*" }
                if !suppressBold, traits.contains(.bold) { value = "**\(value)**" }
            }
            result += value
        }
        return result
    }

    private static func asset(from attachment: NSTextAttachment, number: Int) -> DocumentImportAsset? {
        let wrapper = attachment.fileWrapper
        let data = wrapper?.regularFileContents ?? attachment.contents
        guard let data, !data.isEmpty else { return nil }
        let proposed = wrapper?.preferredFilename
            ?? attachment.fileType.flatMap { UTType($0)?.preferredFilenameExtension }.map { "image-\(number).\($0)" }
            ?? "image-\(number).png"
        return DocumentImportAsset(
            suggestedFilename: proposed,
            altText: URL(fileURLWithPath: proposed).deletingPathExtension().lastPathComponent,
            data: data
        )
    }

    fileprivate static func escapeMarkdown(_ value: String) -> String {
        var result = ""
        let escapable: Set<Character> = ["\\", "`", "*", "_", "{", "}", "[", "]", "<", ">", "~"]
        for character in value {
            if escapable.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}

private struct SanitizedHTMLImport {
    var html: String
    var assets: [DocumentImportAsset]
    var notices: [DocumentImportNotice]
}

private enum HTMLImportSanitizer {
    private static let maximumImageBytes = 40_000_000

    static func prepare(_ source: String, sourceURL: URL) -> SanitizedHTMLImport {
        var html = source
        var assets: [DocumentImportAsset] = []
        var notices: [DocumentImportNotice] = []
        var omittedRemoteImages = 0

        for pattern in [
            #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            #"(?is)<style\b[^>]*>.*?</style\s*>"#,
            #"(?is)<iframe\b[^>]*>.*?</iframe\s*>"#,
            #"(?is)<object\b[^>]*>.*?</object\s*>"#,
            #"(?is)<video\b[^>]*>.*?</video\s*>"#,
            #"(?is)<audio\b[^>]*>.*?</audio\s*>"#,
            #"(?is)<svg\b[^>]*>.*?</svg\s*>"#,
            #"(?is)<canvas\b[^>]*>.*?</canvas\s*>"#,
            #"(?is)<embed\b[^>]*>"#,
            #"(?is)<source\b[^>]*>"#,
            #"(?is)<meta\b[^>]*>"#,
            #"(?is)<link\b[^>]*>"#,
            #"(?is)<base\b[^>]*>"#
        ] {
            html = replacing(pattern: pattern, in: html, with: "")
        }
        for attributePattern in [
            #"(?is)\sstyle\s*=\s*([\"']).*?\1"#,
            #"(?is)\sbackground\s*=\s*([\"']).*?\1"#,
            #"(?is)\ssrcset\s*=\s*([\"']).*?\1"#
        ] {
            html = replacing(pattern: attributePattern, in: html, with: "")
        }

        guard let imageRegex = try? NSRegularExpression(pattern: #"(?is)<img\b[^>]*>"#) else {
            return SanitizedHTMLImport(html: html, assets: assets, notices: notices)
        }
        let range = NSRange(location: 0, length: (html as NSString).length)
        for match in imageRegex.matches(in: html, range: range).reversed() {
            let tag = (html as NSString).substring(with: match.range)
            let sourceValue = attribute("src", in: tag) ?? ""
            let alt = attribute("alt", in: tag)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement: String

            if let asset = dataURIAsset(sourceValue, alt: alt, number: assets.count + 1) {
                assets.append(asset)
                replacement = "<p>\(DocumentImportDraft.assetToken(asset.id))</p>"
            } else if let asset = localAsset(sourceValue, alt: alt, sourceURL: sourceURL, number: assets.count + 1) {
                assets.append(asset)
                replacement = "<p>\(DocumentImportDraft.assetToken(asset.id))</p>"
            } else {
                if sourceValue.lowercased().hasPrefix("http://") || sourceValue.lowercased().hasPrefix("https://") {
                    omittedRemoteImages += 1
                }
                replacement = "<p>[Image omitted during import: \(escapedHTML(alt?.isEmpty == false ? alt! : "unavailable image"))]</p>"
            }
            html = (html as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        if omittedRemoteImages > 0 {
            notices.append(DocumentImportNotice(
                severity: .warning,
                title: "Remote images were not downloaded",
                detail: "Kistulentz omitted \(omittedRemoteImages) remote image\(omittedRemoteImages == 1 ? "" : "s") so importing the HTML remained local."
            ))
        }
        return SanitizedHTMLImport(html: html, assets: assets, notices: notices)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)\\b\(escaped)\\s*=\\s*([\"'])(.*?)\\1"
        ) else { return nil }
        let fullRange = NSRange(location: 0, length: (tag as NSString).length)
        guard let match = regex.firstMatch(in: tag, range: fullRange), match.numberOfRanges > 2 else { return nil }
        return (tag as NSString).substring(with: match.range(at: 2))
    }

    private static func dataURIAsset(_ source: String, alt: String?, number: Int) -> DocumentImportAsset? {
        guard source.lowercased().hasPrefix("data:image/"),
              let comma = source.firstIndex(of: ",") else { return nil }
        let metadata = String(source[..<comma]).lowercased()
        guard metadata.contains(";base64") else { return nil }
        let encoded = String(source[source.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              !data.isEmpty,
              data.count <= maximumImageBytes else { return nil }
        let subtype = metadata
            .dropFirst("data:image/".count)
            .split(separator: ";").first.map(String.init) ?? "png"
        let ext = subtype == "jpeg" ? "jpg" : DocumentImportFilename.safe(subtype)
        return DocumentImportAsset(
            suggestedFilename: "image-\(number).\(ext)",
            altText: alt?.isEmpty == false ? alt! : "Imported image \(number)",
            data: data
        )
    }

    private static func localAsset(
        _ source: String,
        alt: String?,
        sourceURL: URL,
        number: Int
    ) -> DocumentImportAsset? {
        guard !source.isEmpty,
              !source.contains(":"),
              let decoded = source.removingPercentEncoding else { return nil }
        let root = sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(decoded).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              let data = try? Data(contentsOf: candidate, options: .mappedIfSafe),
              !data.isEmpty,
              data.count <= maximumImageBytes else { return nil }
        let proposed = candidate.lastPathComponent.isEmpty ? "image-\(number).png" : candidate.lastPathComponent
        return DocumentImportAsset(
            suggestedFilename: proposed,
            altText: alt?.isEmpty == false ? alt! : candidate.deletingPathExtension().lastPathComponent,
            data: data
        )
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(location: 0, length: (value as NSString).length)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    private static func escapedHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class ImportXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [ImportXMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name.split(separator: ":").last.map { String($0).lowercased() } ?? name.lowercased()
        self.attributes = attributes
    }

    func attribute(_ localName: String) -> String? {
        attributes.first {
            $0.key.split(separator: ":").last.map { String($0).lowercased() } == localName.lowercased()
        }?.value
    }

    func child(_ localName: String) -> ImportXMLNode? {
        children.first { $0.name == localName.lowercased() }
    }

    func descendants(named localName: String) -> [ImportXMLNode] {
        let name = localName.lowercased()
        return children.flatMap { child in
            (child.name == name ? [child] : []) + child.descendants(named: name)
        }
    }

    var allText: String {
        text + children.map(\.allText).joined()
    }
}

private final class ImportXMLTreeParser: NSObject, XMLParserDelegate {
    private(set) var root: ImportXMLNode?
    private var stack: [ImportXMLNode] = []

    func parse(_ data: Data) -> ImportXMLNode? {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        return parser.parse() ? root : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = ImportXMLNode(name: qName ?? elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }
}

private struct DOCXRelationship {
    let target: String
    let type: String
    let isExternal: Bool
}

private final class DOCXArchiveReader {
    private static let maximumArchiveBytes: UInt64 = 250_000_000
    private static let maximumEntryBytes = 50_000_000
    let url: URL
    let entries: Set<String>

    init(url: URL) throws {
        self.url = url
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > 0, size <= Self.maximumArchiveBytes else {
            throw DocumentImportError.documentTooLarge
        }
        let listing = try Self.run(arguments: ["-Z1", url.path])
        guard let listingText = String(data: listing, encoding: .utf8) else {
            throw DocumentImportError.unsafeArchive
        }
        let names = listingText.split(whereSeparator: \.isNewline).map(String.init)
        guard !names.isEmpty, names.count <= 25_000 else { throw DocumentImportError.unsafeArchive }
        for name in names {
            let normalized = name.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            guard normalized.utf8.count <= 1_024,
                  !normalized.hasPrefix("/"),
                  !normalized.hasPrefix("~"),
                  !components.contains("..") else {
                throw DocumentImportError.unsafeArchive
            }
        }
        entries = Set(names)
    }

    func data(for entry: String, required: Bool = true) throws -> Data? {
        guard entries.contains(entry) else {
            if required { throw DocumentImportError.unreadableDocument }
            return nil
        }
        let data = try Self.run(arguments: ["-p", url.path, entry])
        guard data.count <= Self.maximumEntryBytes else { throw DocumentImportError.documentTooLarge }
        return data
    }

    private static func run(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw DocumentImportError.extractionFailed(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DocumentImportError.extractionFailed(message?.isEmpty == false ? message! : "The system unzip utility failed.")
        }
        return data
    }
}

private enum DOCXDocumentImporter {
    static func load(from url: URL) throws -> DocumentImportDraft {
        let archive = try DOCXArchiveReader(url: url)
        guard let documentData = try archive.data(for: "word/document.xml"),
              let document = ImportXMLTreeParser().parse(documentData) else {
            throw DocumentImportError.unreadableDocument
        }

        let relationships = try parseRelationships(archive)
        let numbering = try parseNumbering(archive)
        let footnotes = try parseIndexedNodes(archive, entry: "word/footnotes.xml", nodeName: "footnote")
        let comments = try parseIndexedNodes(archive, entry: "word/comments.xml", nodeName: "comment")
        let renderer = DOCXMarkdownRenderer(
            archive: archive,
            relationships: relationships,
            numbering: numbering,
            footnotes: footnotes,
            comments: comments
        )
        let conversion = try renderer.render(document)
        guard !conversion.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.emptyDocument
        }

        var notices = conversion.notices
        notices.insert(DocumentImportNotice(
            severity: .information,
            title: "Original preserved",
            detail: "Kistulentz creates a separate Markdown copy and never rewrites the selected Microsoft Word document."
        ), at: 0)
        notices.append(DocumentImportNotice(
            severity: .warning,
            title: "Review the converted structure",
            detail: "Page layout, headers, footers, fields, floating objects, and exact typography are not carried into Markdown."
        ))
        if !conversion.reviewCards.isEmpty {
            notices.append(DocumentImportNotice(
                severity: .information,
                title: "Tracked changes require a decision",
                detail: "Accept or reject every imported Word change before saving the Markdown copy."
            ))
        }
        if !conversion.assets.isEmpty {
            notices.append(DocumentImportNotice(
                severity: .information,
                title: "Images will be copied",
                detail: "Imported images will be placed in a sibling assets folder beside the Markdown file."
            ))
        }

        return DocumentImportDraft(
            sourceURL: url,
            format: .docx,
            templateMarkdown: conversion.markdown,
            reviewCards: conversion.reviewCards,
            assets: DocumentImportService.uniqueAssets(conversion.assets),
            notices: DocumentImportService.uniqueNotices(notices)
        )
    }

    private static func parseRelationships(_ archive: DOCXArchiveReader) throws -> [String: DOCXRelationship] {
        guard let data = try archive.data(for: "word/_rels/document.xml.rels", required: false),
              let root = ImportXMLTreeParser().parse(data) else { return [:] }
        var result: [String: DOCXRelationship] = [:]
        for node in root.descendants(named: "relationship") {
            guard let id = node.attribute("id"), let target = node.attribute("target") else { continue }
            result[id] = DOCXRelationship(
                target: target,
                type: node.attribute("type") ?? "",
                isExternal: node.attribute("targetmode")?.caseInsensitiveCompare("External") == .orderedSame
            )
        }
        return result
    }

    private static func parseNumbering(_ archive: DOCXArchiveReader) throws -> DOCXNumbering {
        guard let data = try archive.data(for: "word/numbering.xml", required: false),
              let root = ImportXMLTreeParser().parse(data) else { return DOCXNumbering() }
        var abstractFormats: [String: [Int: String]] = [:]
        for abstract in root.descendants(named: "abstractnum") {
            guard let id = abstract.attribute("abstractnumid") else { continue }
            var levels: [Int: String] = [:]
            for level in abstract.children.filter({ $0.name == "lvl" }) {
                let index = Int(level.attribute("ilvl") ?? "0") ?? 0
                levels[index] = level.child("numfmt")?.attribute("val") ?? "bullet"
            }
            abstractFormats[id] = levels
        }
        var numberToAbstract: [String: String] = [:]
        for number in root.descendants(named: "num") {
            if let id = number.attribute("numid"), let abstract = number.child("abstractnumid")?.attribute("val") {
                numberToAbstract[id] = abstract
            }
        }
        return DOCXNumbering(abstractFormats: abstractFormats, numberToAbstract: numberToAbstract)
    }

    private static func parseIndexedNodes(
        _ archive: DOCXArchiveReader,
        entry: String,
        nodeName: String
    ) throws -> [String: ImportXMLNode] {
        guard let data = try archive.data(for: entry, required: false),
              let root = ImportXMLTreeParser().parse(data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: root.descendants(named: nodeName).compactMap { node in
            node.attribute("id").map { ($0, node) }
        })
    }
}

private struct DOCXNumbering {
    var abstractFormats: [String: [Int: String]] = [:]
    var numberToAbstract: [String: String] = [:]

    func isOrdered(numberID: String, level: Int) -> Bool {
        guard let abstract = numberToAbstract[numberID],
              let format = abstractFormats[abstract]?[level] else { return false }
        return format.caseInsensitiveCompare("bullet") != .orderedSame
    }
}

private struct DOCXMarkdownConversion {
    var markdown: String
    var reviewCards: [DocumentImportReviewCard]
    var assets: [DocumentImportAsset]
    var notices: [DocumentImportNotice]
}

private final class DOCXMarkdownRenderer {
    private let archive: DOCXArchiveReader
    private let relationships: [String: DOCXRelationship]
    private let numbering: DOCXNumbering
    private let footnotes: [String: ImportXMLNode]
    private let comments: [String: ImportXMLNode]
    private var reviewCards: [DocumentImportReviewCard] = []
    private var assets: [DocumentImportAsset] = []
    private var assetByRelationship: [String: UUID] = [:]
    private var usedFootnotes: [String] = []
    private var usedComments: [String] = []
    private var notices: [DocumentImportNotice] = []

    init(
        archive: DOCXArchiveReader,
        relationships: [String: DOCXRelationship],
        numbering: DOCXNumbering,
        footnotes: [String: ImportXMLNode],
        comments: [String: ImportXMLNode]
    ) {
        self.archive = archive
        self.relationships = relationships
        self.numbering = numbering
        self.footnotes = footnotes
        self.comments = comments
    }

    func render(_ document: ImportXMLNode) throws -> DOCXMarkdownConversion {
        guard let body = document.descendants(named: "body").first else {
            throw DocumentImportError.unreadableDocument
        }
        var blocks: [String] = []
        for child in body.children {
            if let block = try renderBlock(child), !block.isEmpty { blocks.append(block) }
        }

        for id in usedFootnotes where id != "-1" && id != "0" {
            guard let node = footnotes[id] else { continue }
            let value = try node.descendants(named: "p")
                .map { try renderParagraphContent($0, allowsChangeCards: true) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !value.isEmpty { blocks.append("[^\(id)]: \(value)") }
        }
        for id in usedComments {
            guard let node = comments[id] else { continue }
            let value = try node.descendants(named: "p")
                .map { try renderParagraphContent($0, allowsChangeCards: false) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !value.isEmpty else { continue }
            let author = node.attribute("author")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = author?.isEmpty == false ? "Comment by \(author!): " : "Comment: "
            blocks.append("[^comment-\(id)]: \(prefix)\(value)")
        }
        if !usedComments.isEmpty {
            notices.append(DocumentImportNotice(
                severity: .information,
                title: "Word comments became Markdown notes",
                detail: "Imported comments are preserved as attributed footnote-style notes for review."
            ))
        }

        return DOCXMarkdownConversion(
            markdown: DocumentImportDraft.normalizedMarkdown(blocks.joined(separator: "\n\n")),
            reviewCards: reviewCards,
            assets: assets,
            notices: notices
        )
    }

    private func renderBlock(_ node: ImportXMLNode) throws -> String? {
        switch node.name {
        case "p": return try renderParagraph(node)
        case "tbl": return try renderTable(node)
        case "sdt", "customxml":
            let blocks = try node.children.compactMap { try renderBlock($0) }
            return blocks.joined(separator: "\n\n")
        default: return nil
        }
    }

    private func renderParagraph(_ paragraph: ImportXMLNode) throws -> String {
        let value = try renderParagraphContent(paragraph, allowsChangeCards: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let properties = paragraph.child("ppr")
        let style = properties?.child("pstyle")?.attribute("val")?.lowercased() ?? ""

        if let heading = headingLevel(style) {
            return String(repeating: "#", count: heading) + " " + value
        }
        if style.contains("quote") {
            return "> " + value.replacingOccurrences(of: "\n", with: "\n> ")
        }
        if let numberingProperties = properties?.child("numpr"),
           let numberID = numberingProperties.child("numid")?.attribute("val") {
            let level = Int(numberingProperties.child("ilvl")?.attribute("val") ?? "0") ?? 0
            let prefix = numbering.isOrdered(numberID: numberID, level: level) ? "1. " : "- "
            return String(repeating: "  ", count: max(0, level)) + prefix + value
        }
        return value
    }

    private func renderParagraphContent(_ paragraph: ImportXMLNode, allowsChangeCards: Bool) throws -> String {
        try renderInlineNodes(paragraph.children.filter { $0.name != "ppr" }, allowsChangeCards: allowsChangeCards)
    }

    private func renderInlineNodes(_ nodes: [ImportXMLNode], allowsChangeCards: Bool) throws -> String {
        var result = ""
        for node in nodes {
            switch node.name {
            case "r": result += try renderRun(node)
            case "hyperlink":
                let label = try renderInlineNodes(node.children, allowsChangeCards: allowsChangeCards)
                if let relationshipID = node.attribute("id"),
                   let relationship = relationships[relationshipID],
                   relationship.isExternal {
                    result += "[\(label)](<\(relationship.target.replacingOccurrences(of: ">", with: "%3E"))>)"
                } else {
                    result += label
                }
            case "ins", "moveto", "del", "movefrom":
                if allowsChangeCards {
                    let kind: DocumentTrackedChangeKind = (node.name == "ins" || node.name == "moveto") ? .insertion : .deletion
                    let changed = try renderInlineNodes(node.children, allowsChangeCards: false)
                    if !changed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let card = DocumentImportReviewCard(
                            kind: kind,
                            author: node.attribute("author"),
                            date: node.attribute("date").flatMap { ISO8601DateFormatter().date(from: $0) },
                            changedMarkdown: changed
                        )
                        reviewCards.append(card)
                        result += DocumentImportDraft.changeToken(card.id)
                    }
                } else {
                    result += try renderInlineNodes(node.children, allowsChangeCards: false)
                }
            case "commentreferencerange", "commentrangestart", "commentrangeend":
                continue
            case "fldsimple", "smarttag", "sdt", "customxml":
                result += try renderInlineNodes(node.children, allowsChangeCards: allowsChangeCards)
            default:
                if !node.children.isEmpty {
                    result += try renderInlineNodes(node.children, allowsChangeCards: allowsChangeCards)
                }
            }
        }
        return result
    }

    private func renderRun(_ run: ImportXMLNode) throws -> String {
        var value = ""
        for child in run.children where child.name != "rpr" {
            switch child.name {
            case "t", "deltext": value += AttributedMarkdownImporter.escapeMarkdown(child.allText)
            case "tab": value += "\t"
            case "br", "cr": value += "  \n"
            case "drawing", "pict", "object": value += try renderImage(in: child)
            case "footnotereference":
                if let id = child.attribute("id") {
                    if !usedFootnotes.contains(id) { usedFootnotes.append(id) }
                    value += "[^\(id)]"
                }
            case "commentreference":
                if let id = child.attribute("id") {
                    if !usedComments.contains(id) { usedComments.append(id) }
                    value += "[^comment-\(id)]"
                }
            default:
                break
            }
        }
        guard !value.isEmpty else { return "" }
        let properties = run.child("rpr")
        if isEnabled(properties?.child("strike")) { value = "~~\(value)~~" }
        if isEnabled(properties?.child("i")) || isEnabled(properties?.child("ics")) { value = "*\(value)*" }
        if isEnabled(properties?.child("b")) || isEnabled(properties?.child("bcs")) { value = "**\(value)**" }
        if let vertical = properties?.child("vertalign")?.attribute("val")?.lowercased() {
            if vertical == "superscript" { value = "<sup>\(value)</sup>" }
            if vertical == "subscript" { value = "<sub>\(value)</sub>" }
        }
        return value
    }

    private func renderImage(in node: ImportXMLNode) throws -> String {
        let reference = node.descendants(named: "blip").first?.attribute("embed")
            ?? node.descendants(named: "imagedata").first?.attribute("id")
        guard let reference, let relationship = relationships[reference], !relationship.isExternal else {
            return "[Image omitted during import]"
        }
        if let existing = assetByRelationship[reference] {
            return DocumentImportDraft.assetToken(existing)
        }
        guard let entry = archiveEntry(for: relationship.target),
              let data = try archive.data(for: entry, required: false),
              !data.isEmpty else {
            notices.append(DocumentImportNotice(
                severity: .warning,
                title: "A Word image could not be copied",
                detail: "The conversion preview contains a placeholder for an unreadable embedded image."
            ))
            return "[Image omitted during import]"
        }
        let proposed = URL(fileURLWithPath: relationship.target).lastPathComponent
        let description = node.descendants(named: "docpr").first?.attribute("descr")
            ?? node.descendants(named: "docpr").first?.attribute("name")
            ?? URL(fileURLWithPath: proposed).deletingPathExtension().lastPathComponent
        let asset = DocumentImportAsset(suggestedFilename: proposed, altText: description, data: data)
        assets.append(asset)
        assetByRelationship[reference] = asset.id
        return DocumentImportDraft.assetToken(asset.id)
    }

    private func renderTable(_ table: ImportXMLNode) throws -> String {
        let rows = table.children.filter { $0.name == "tr" }.map { row in
            row.children.filter { $0.name == "tc" }.map { cell in
                let text = (try? cell.descendants(named: "p")
                    .map { try renderParagraphContent($0, allowsChangeCards: true) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "<br>")) ?? ""
                return text.replacingOccurrences(of: "|", with: "\\|")
            }
        }.filter { !$0.isEmpty }
        guard let first = rows.first else { return "" }
        let columnCount = rows.map(\.count).max() ?? first.count
        func padded(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }
        var lines = ["| " + padded(first).joined(separator: " | ") + " |"]
        lines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append("| " + padded(row).joined(separator: " | ") + " |")
        }
        notices.append(DocumentImportNotice(
            severity: .warning,
            title: "Word tables became Markdown tables",
            detail: "Verify the first row and any merged cells after conversion."
        ))
        return lines.joined(separator: "\n")
    }

    private func headingLevel(_ style: String) -> Int? {
        if style == "title" { return 1 }
        guard let range = style.range(of: #"heading\s*([1-6])"#, options: .regularExpression) else { return nil }
        return Int(style[range].last.map(String.init) ?? "")
    }

    private func isEnabled(_ node: ImportXMLNode?) -> Bool {
        guard let node else { return false }
        let value = node.attribute("val")?.lowercased()
        return value == nil || !["0", "false", "off", "none"].contains(value!)
    }

    private func archiveEntry(for target: String) -> String? {
        guard !target.isEmpty, !target.contains(":") else { return nil }
        let base = URL(fileURLWithPath: "/word", isDirectory: true)
        let resolved = base.appendingPathComponent(target).standardizedFileURL.path
        guard resolved.hasPrefix("/word/") else { return nil }
        let entry = String(resolved.dropFirst())
        return archive.entries.contains(entry) ? entry : nil
    }
}
