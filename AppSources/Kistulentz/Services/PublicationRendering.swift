import AppKit
import Foundation

enum PublicationBlockKind: Equatable {
    case heading(Int)
    case paragraph
    case blockquote
    case code
    case unorderedItem
    case orderedItem
    case image
    case divider
}

struct PublicationBlock: Equatable {
    var kind: PublicationBlockKind
    var text: String
    var html: String
    var imageURL: URL?
    var altText: String
}

struct PublicationNote: Identifiable, Equatable {
    var id: Int
    var text: String
}

struct PublicationRenderedSection: Identifiable, Equatable {
    var id: String
    var title: String
    var kind: ExportPlanItemKind
    var blocks: [PublicationBlock]
    var bodyHTML: String
    var sourcePath: String?
    var noteIDs: [Int]
}

struct PublicationRenderedBook: Equatable {
    var plan: PublicationExportPlan
    var sections: [PublicationRenderedSection]
    var notes: [PublicationNote]

    var images: [(source: URL, name: String, altText: String)] {
        var seen: Set<String> = []
        return sections.flatMap(\.blocks).compactMap { block in
            guard block.kind == .image, let source = block.imageURL else { return nil }
            let key = source.standardizedFileURL.path
            guard seen.insert(key).inserted else { return nil }
            let stem = HeadingSplitPlanner.safeFileComponent(source.deletingPathExtension().lastPathComponent)
            let digest = PublicationHash.shortHash(key)
            let ext = source.pathExtension.lowercased()
            return (source, "\(stem)-\(digest).\(ext)", block.altText)
        }
    }
}

enum PublicationHash {
    static func shortHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%08llx", hash & 0xffff_ffff)
    }
}

final class PublicationRenderer {
    private static let citationContainerRegex = try! NSRegularExpression(pattern: #"\[[^\]]*@[A-Za-z0-9_:\-]+[^\]]*\]"#)
    private static let citationKeyRegex = try! NSRegularExpression(pattern: #"@([A-Za-z0-9_:\-]+)"#)
    private static let footnoteReferenceRegex = try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)
    private static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: #"(?m)^\[\^([^\]]+)\]:\s*(.+)$"#)
    private static let noteTokenRegex = try! NSRegularExpression(pattern: #"\{\{KISTU_NOTE_(\d+)\}\}"#)

    private let plan: PublicationExportPlan
    private let root: URL
    private let sourceByKey: [String: ResearchSource]
    private var notes: [PublicationNote] = []
    private var footnoteDefinitions: [String: String] = [:]

    init(plan: PublicationExportPlan, root: URL) {
        self.plan = plan
        self.root = root
        sourceByKey = plan.sources.reduce(into: [:]) { result, source in
            let key = source.citeKey.lowercased()
            if result[key] == nil { result[key] = source }
        }
        for item in plan.includedItems {
            footnoteDefinitions.merge(PublicationMarkdownScanner.footnoteDefinitions(in: item.markdown)) { current, _ in current }
        }
    }

    func render() -> PublicationRenderedBook {
        var sections: [PublicationRenderedSection] = []
        for item in plan.includedItems {
            if item.matterKind == .tableOfContents || item.matterKind == .endnotes || item.matterKind == .bibliography {
                continue
            }
            sections.append(renderSection(item))
        }

        if let tocIndex = plan.includedItems.firstIndex(where: { $0.matterKind == .tableOfContents }) {
            let tocItem = plan.includedItems[tocIndex]
            let entries = sections.filter { $0.kind == .part || $0.kind == .manuscript }
            let list = entries.map { section in
                "<li><a href=\"#\(PublicationXML.slug(section.id))\">\(PublicationXML.escape(section.title))</a></li>"
            }.joined(separator: "\n")
            let html = "<nav epub:type=\"toc\" aria-label=\"Table of Contents\"><h1>Table of Contents</h1><ol>\(list)</ol></nav>"
            let blocks = [PublicationBlock(kind: .heading(1), text: "Table of Contents", html: "<h1>Table of Contents</h1>", imageURL: nil, altText: "")] + entries.map {
                PublicationBlock(kind: .paragraph, text: $0.title, html: "<p>\(PublicationXML.escape($0.title))</p>", imageURL: nil, altText: "")
            }
            sections.insert(PublicationRenderedSection(id: tocItem.id, title: tocItem.title, kind: tocItem.kind, blocks: blocks, bodyHTML: html, sourcePath: nil, noteIDs: []), at: min(tocIndex, sections.count))
        }

        if plan.profile.citationMode == .endnotes,
           let item = plan.includedItems.first(where: { $0.matterKind == .endnotes }) {
            let manual = replacingGeneratedComment(in: item.markdown)
            let list = notes.map { "<li id=\"note-\($0.id)\">\(PublicationXML.escape($0.text))</li>" }.joined(separator: "\n")
            let html = "<section epub:type=\"endnotes\">\(inlineMarkdownToHTML(manual))<ol>\(list)</ol></section>"
            let blocks = markdownBlocks(manual, sourcePath: nil) + notes.map {
                PublicationBlock(kind: .orderedItem, text: $0.text, html: "<li>\(PublicationXML.escape($0.text))</li>", imageURL: nil, altText: "")
            }
            sections.append(PublicationRenderedSection(id: item.id, title: item.title, kind: item.kind, blocks: blocks, bodyHTML: html, sourcePath: nil, noteIDs: notes.map(\.id)))
        }

        if plan.profile.includeBibliography,
           let item = plan.includedItems.first(where: { $0.matterKind == .bibliography }) {
            let manual = replacingGeneratedComment(in: item.markdown)
            let entries = bibliographyEntries()
            let htmlEntries = entries.map { "<p class=\"bibliography-entry\">\(inlineMarkdownToHTML($0))</p>" }.joined(separator: "\n")
            let html = "<section epub:type=\"bibliography\">\(inlineMarkdownToHTML(manual))\(htmlEntries)</section>"
            let blocks = markdownBlocks(manual, sourcePath: nil) + entries.map {
                PublicationBlock(kind: .paragraph, text: PublicationPlainText.inline($0), html: "<p>\(inlineMarkdownToHTML($0))</p>", imageURL: nil, altText: "")
            }
            sections.append(PublicationRenderedSection(id: item.id, title: item.title, kind: item.kind, blocks: blocks, bodyHTML: html, sourcePath: nil, noteIDs: []))
        }

        return PublicationRenderedBook(plan: plan, sections: sections, notes: notes)
    }

    private func renderSection(_ item: ExportPlanItem) -> PublicationRenderedSection {
        let firstNote = notes.count + 1
        var blocks = markdownBlocks(item.markdown, sourcePath: item.sourcePath)
        if !blocks.contains(where: { if case .heading(1) = $0.kind { return true }; return false }) {
            let title = PublicationPlainText.inline(item.title)
            blocks.insert(PublicationBlock(kind: .heading(1), text: title, html: "<h1>\(PublicationXML.escape(title))</h1>", imageURL: nil, altText: ""), at: 0)
        }
        let body = blocks.map(\.html).joined(separator: "\n")
        let noteIDs = firstNote <= notes.count ? Array(firstNote...notes.count) : []
        return PublicationRenderedSection(id: item.id, title: item.title, kind: item.kind, blocks: blocks, bodyHTML: body, sourcePath: item.sourcePath, noteIDs: noteIDs)
    }

    private func markdownBlocks(_ original: String, sourcePath: String?) -> [PublicationBlock] {
        var markdown = Self.footnoteDefinitionRegex.stringByReplacingMatches(
            in: original,
            range: NSRange(location: 0, length: (original as NSString).length),
            withTemplate: ""
        )
        markdown = replaceCitations(in: markdown)
        markdown = replaceFootnoteReferences(in: markdown)
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [PublicationBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: " ")
            blocks.append(contentsOf: splitImages(in: joined, kind: .paragraph, sourcePath: sourcePath))
            paragraph.removeAll()
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushParagraph()
                if inCode {
                    let text = code.joined(separator: "\n")
                    blocks.append(PublicationBlock(kind: .code, text: text, html: "<pre><code>\(PublicationXML.escape(text))</code></pre>", imageURL: nil, altText: ""))
                    code.removeAll()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(PublicationBlock(kind: .divider, text: "", html: "<hr />", imageURL: nil, altText: ""))
                continue
            }
            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(PublicationBlock(kind: .heading(heading.level), text: PublicationPlainText.inline(heading.text), html: "<h\(heading.level)>\(inlineMarkdownToHTML(heading.text))</h\(heading.level)>", imageURL: nil, altText: ""))
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                let value = String(trimmed.dropFirst(2))
                blocks.append(contentsOf: splitImages(in: value, kind: .blockquote, sourcePath: sourcePath))
                continue
            }
            if trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil {
                flushParagraph()
                let value = trimmed.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression)
                blocks.append(contentsOf: splitImages(in: value, kind: .unorderedItem, sourcePath: sourcePath))
                continue
            }
            if trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil {
                flushParagraph()
                let value = trimmed.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
                blocks.append(contentsOf: splitImages(in: value, kind: .orderedItem, sourcePath: sourcePath))
                continue
            }
            if !PublicationMarkdownScanner.images(in: trimmed).isEmpty {
                flushParagraph()
                blocks.append(contentsOf: splitImages(in: trimmed, kind: .paragraph, sourcePath: sourcePath))
            } else {
                paragraph.append(trimmed)
            }
        }
        flushParagraph()
        if !code.isEmpty {
            let text = code.joined(separator: "\n")
            blocks.append(PublicationBlock(kind: .code, text: text, html: "<pre><code>\(PublicationXML.escape(text))</code></pre>", imageURL: nil, altText: ""))
        }
        return blocks
    }

    private func splitImages(in text: String, kind: PublicationBlockKind, sourcePath: String?) -> [PublicationBlock] {
        let matches = PublicationMarkdownScanner.images(in: text)
        guard !matches.isEmpty else {
            return [textBlock(text, kind: kind)]
        }
        let source = text as NSString
        var result: [PublicationBlock] = []
        var cursor = 0
        for image in matches {
            if image.range.location > cursor {
                let before = source.substring(with: NSRange(location: cursor, length: image.range.location - cursor))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty { result.append(textBlock(before, kind: kind)) }
            }
            let url = PublicationMarkdownScanner.resolveImagePath(image.path, sourcePath: sourcePath, root: root)
            let name = HeadingSplitPlanner.safeFileComponent(url.deletingPathExtension().lastPathComponent)
                + "-" + PublicationHash.shortHash(url.standardizedFileURL.path)
                + "." + url.pathExtension.lowercased()
            let alt = PublicationXML.escapeAttribute(image.altText)
            let html = "<figure><img src=\"../images/\(PublicationXML.escapeAttribute(name))\" alt=\"\(alt)\" />" +
                (image.title.isEmpty ? "" : "<figcaption>\(PublicationXML.escape(image.title))</figcaption>") + "</figure>"
            result.append(PublicationBlock(kind: .image, text: image.title, html: html, imageURL: url, altText: image.altText))
            cursor = image.range.location + image.range.length
        }
        if cursor < source.length {
            let after = source.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { result.append(textBlock(after, kind: kind)) }
        }
        return result
    }

    private func textBlock(_ text: String, kind: PublicationBlockKind) -> PublicationBlock {
        let html: String
        switch kind {
        case .paragraph: html = "<p>\(inlineMarkdownToHTML(text))</p>"
        case .blockquote: html = "<blockquote><p>\(inlineMarkdownToHTML(text))</p></blockquote>"
        case .unorderedItem: html = "<ul><li>\(inlineMarkdownToHTML(text))</li></ul>"
        case .orderedItem: html = "<ol><li>\(inlineMarkdownToHTML(text))</li></ol>"
        default: html = inlineMarkdownToHTML(text)
        }
        return PublicationBlock(kind: kind, text: PublicationPlainText.inline(text), html: html, imageURL: nil, altText: "")
    }

    private func replaceCitations(in text: String) -> String {
        let source = text as NSString
        let matches = Self.citationContainerRegex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var result = text
        for match in matches.reversed() {
            let raw = source.substring(with: match.range)
            let rawSource = raw as NSString
            let keys = Self.citationKeyRegex.matches(in: raw, range: NSRange(location: 0, length: rawSource.length)).map {
                rawSource.substring(with: $0.range(at: 1))
            }
            let cited = keys.compactMap { sourceByKey[$0.lowercased()] }
            guard !cited.isEmpty else { continue }
            let locator = raw
                .replacingOccurrences(of: #"^\[|\]$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"-?@[A-Za-z0-9_:\-]+;?\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: ",; "))
            let replacement: String
            switch plan.profile.citationMode {
            case .parenthetical:
                replacement = "(" + cited.map { parentheticalCitation($0, locator: locator) }.joined(separator: "; ") + ")"
            case .footnotes, .endnotes:
                let noteText = cited.enumerated().map { index, value in
                    CitationFormatter.entry(value, style: plan.bibliography.style, number: index + 1)
                }.joined(separator: "; ") + (locator.isEmpty ? "" : " \(locator)")
                let number = appendNote(noteText)
                replacement = "{{KISTU_NOTE_\(number)}}"
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private func replaceFootnoteReferences(in text: String) -> String {
        let source = text as NSString
        let matches = Self.footnoteReferenceRegex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var result = text
        for match in matches.reversed() {
            let key = source.substring(with: match.range(at: 1))
            guard let definition = footnoteDefinitions[key] else { continue }
            let number = appendNote(PublicationPlainText.inline(definition))
            result = (result as NSString).replacingCharacters(in: match.range, with: "{{KISTU_NOTE_\(number)}}")
        }
        return result
    }

    private func appendNote(_ text: String) -> Int {
        let number = notes.count + 1
        notes.append(PublicationNote(id: number, text: PublicationPlainText.inline(text)))
        return number
    }

    private func parentheticalCitation(_ source: ResearchSource, locator: String) -> String {
        let author = source.authors.first?.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (author?.isEmpty == false ? author! : source.primaryCreatorName)
        let year = source.issuedYear.map(String.init) ?? "n.d."
        return [name, year, locator].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func bibliographyEntries() -> [String] {
        let sorted = plan.sources.sorted {
            let creator = $0.primaryCreatorName.localizedCaseInsensitiveCompare($1.primaryCreatorName)
            return creator == .orderedSame
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : creator == .orderedAscending
        }
        return sorted.enumerated().map { CitationFormatter.entry($0.element, style: plan.bibliography.style, number: $0.offset + 1) }
    }

    private func inlineMarkdownToHTML(_ value: String) -> String {
        var html = PublicationXML.escape(value)
        // Note-reference tokens (`{{KISTU_NOTE_1}}`) must be swapped for their anchor markup before any
        // emphasis pattern runs: the token's own underscores (`KISTU_NOTE_1`) otherwise satisfy the
        // single-underscore italic pattern below, which consumes them into an `<em>` and leaves nothing
        // left for `noteTokenRegex` to match. The anchor replacement itself is markdown-syntax-free, so
        // running it first is safe for every emphasis pattern that follows.
        html = replaceNoteTokens(in: html)
        html = replace(pattern: #"`([^`]+)`"#, in: html, with: "<code>$1</code>")
        html = replace(pattern: #"\*\*([^*]+)\*\*"#, in: html, with: "<strong>$1</strong>")
        html = replace(pattern: #"__([^_]+)__"#, in: html, with: "<strong>$1</strong>")
        html = replace(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, in: html, with: "<em>$1</em>")
        html = replace(pattern: #"(?<!_)_([^_]+)_(?!_)"#, in: html, with: "<em>$1</em>")
        html = replace(pattern: #"~~([^~]+)~~"#, in: html, with: "<del>$1</del>")
        html = replace(pattern: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#, in: html, with: "<a href=\"$2\">$1</a>")
        return html
    }

    private func replaceNoteTokens(in html: String) -> String {
        let source = html as NSString
        var result = html
        for match in Self.noteTokenRegex.matches(in: html, range: NSRange(location: 0, length: source.length)).reversed() {
            let number = source.substring(with: match.range(at: 1))
            let replacement = plan.profile.citationMode == .footnotes
                ? "<a role=\"doc-noteref\" epub:type=\"noteref\" href=\"#footnote-\(number)\"><sup>\(number)</sup></a>"
                : "<a role=\"doc-noteref\" epub:type=\"noteref\" href=\"#note-\(number)\"><sup>\(number)</sup></a>"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private func replace(pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private func replacingGeneratedComment(in value: String) -> String {
        value.replacingOccurrences(of: #"<!--\s*Kistulentz generates[^>]*-->"#, with: "", options: .regularExpression)
    }
}

enum PublicationPlainText {
    static func inline(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"!\[([^\]]*)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\{\{KISTU_NOTE_(\d+)\}\}"#, with: "[$1]", options: .regularExpression)
            .replacingOccurrences(of: #"[*_~`]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PublicationXML {
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func escapeAttribute(_ value: String) -> String { escape(value).replacingOccurrences(of: "'", with: "&apos;") }

    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let collapsed = String(scalars).replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
