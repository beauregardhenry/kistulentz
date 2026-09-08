import AppKit
import Foundation
import UniformTypeIdentifiers

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

enum DOCXDocumentImporter {
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
