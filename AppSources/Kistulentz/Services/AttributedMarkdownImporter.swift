import AppKit
import Foundation
import UniformTypeIdentifiers

struct AttributedMarkdownImportResult {
    var markdown: String
    var assets: [DocumentImportAsset]
    var notices: [DocumentImportNotice]
}

enum AttributedMarkdownImporter {
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

    static func escapeMarkdown(_ value: String) -> String {
        var result = ""
        let escapable: Set<Character> = ["\\", "`", "*", "_", "{", "}", "[", "]", "<", ">", "~"]
        for character in value {
            if escapable.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
