import AppKit
import Foundation

private struct DOCXImageAsset {
    var source: URL
    var name: String
    var relationshipID: String
    var mediaType: String
}

enum DOCXPublicationWriter {
    private static let noteMarkerRegex = try! NSRegularExpression(pattern: #"\[(\d+)\]"#)

    static func write(_ book: PublicationRenderedBook, to outputURL: URL, root: URL) throws {
        let temporary = try PublicationArchiveUtility.temporaryDirectory(prefix: "Kistulentz-DOCX")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let relationships = temporary.appendingPathComponent("_rels", isDirectory: true)
        let properties = temporary.appendingPathComponent("docProps", isDirectory: true)
        let word = temporary.appendingPathComponent("word", isDirectory: true)
        let wordRelationships = word.appendingPathComponent("_rels", isDirectory: true)
        let media = word.appendingPathComponent("media", isDirectory: true)
        for directory in [relationships, properties, word, wordRelationships, media] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var imageSources = book.images.map { ($0.source, $0.name) }
        var coverPath: String?
        if book.plan.profile.includeCover,
           let cover = PublicationDisk.resolveAsset(book.plan.metadata.coverImageRelativePath, at: root) {
            let name = "cover.\(cover.pathExtension.lowercased())"
            imageSources.insert((cover, name), at: 0)
            coverPath = cover.standardizedFileURL.path
        }
        var seen: Set<String> = []
        var imageAssets: [DOCXImageAsset] = []
        for (source, name) in imageSources {
            let path = source.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            guard let mediaType = PublicationMediaType.docx(for: source) else {
                throw PublicationExportError.unsupportedImage(source.lastPathComponent)
            }
            let asset = DOCXImageAsset(source: source, name: name, relationshipID: "rIdImage\(imageAssets.count + 1)", mediaType: mediaType)
            try FileManager.default.copyItem(at: source, to: media.appendingPathComponent(name))
            imageAssets.append(asset)
        }
        let imageByPath = Dictionary(uniqueKeysWithValues: imageAssets.map { ($0.source.standardizedFileURL.path, $0) })

        try contentTypes(book: book, images: imageAssets).write(to: temporary.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelationships.write(to: relationships.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try coreProperties(book).write(to: properties.appendingPathComponent("core.xml"), atomically: true, encoding: .utf8)
        try appProperties.write(to: properties.appendingPathComponent("app.xml"), atomically: true, encoding: .utf8)
        try stylesXML(book.plan.profile.layout).write(to: word.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
        try settingsXML.write(to: word.appendingPathComponent("settings.xml"), atomically: true, encoding: .utf8)
        try numberingXML.write(to: word.appendingPathComponent("numbering.xml"), atomically: true, encoding: .utf8)
        try documentRelationships(book: book, images: imageAssets).write(to: wordRelationships.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        try documentXML(book: book, imageByPath: imageByPath, coverPath: coverPath).write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        if book.plan.profile.citationMode == .footnotes, !book.notes.isEmpty {
            try notesXML(book.notes, element: "footnote").write(to: word.appendingPathComponent("footnotes.xml"), atomically: true, encoding: .utf8)
        }
        if book.plan.profile.citationMode == .endnotes, !book.notes.isEmpty {
            try notesXML(book.notes, element: "endnote").write(to: word.appendingPathComponent("endnotes.xml"), atomically: true, encoding: .utf8)
        }
        if book.plan.profile.layout.headerEnabled {
            try headerXML(book.plan.metadata.title).write(to: word.appendingPathComponent("header1.xml"), atomically: true, encoding: .utf8)
        }
        if book.plan.profile.layout.footerEnabled || book.plan.profile.layout.pageNumbersEnabled {
            try footerXML(pageNumbers: book.plan.profile.layout.pageNumbersEnabled).write(to: word.appendingPathComponent("footer1.xml"), atomically: true, encoding: .utf8)
        }
        try PublicationArchiveUtility.zip(directory: temporary, to: outputURL)
    }

    private static func documentXML(
        book: PublicationRenderedBook,
        imageByPath: [String: DOCXImageAsset],
        coverPath: String?
    ) -> String {
        var paragraphs: [String] = []
        var imageIndex = 1
        if let coverPath, let asset = imageByPath[coverPath] {
            paragraphs.append(imageParagraph(asset, index: imageIndex, maximumWidthInches: 5.5, pageBreakAfter: true))
            imageIndex += 1
        }
        for (sectionIndex, section) in book.sections.enumerated() {
            if section.id == "matter-endnotes", book.plan.profile.citationMode == .endnotes { continue }
            if sectionIndex > 0 && book.plan.profile.layout.chapterOpening != .continuous {
                paragraphs.append("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
            }
            if section.id == "matter-tableOfContents" {
                paragraphs.append(textParagraph("Table of Contents", style: "Heading1", book: book))
                paragraphs.append("<w:p><w:fldSimple w:instr=\"TOC \\o &quot;1-3&quot; \\h \\z \\u\"><w:r><w:t>Update this field in Word to refresh the table of contents.</w:t></w:r></w:fldSimple></w:p>")
                continue
            }
            for block in section.blocks {
                if block.kind == .image,
                   let path = block.imageURL?.standardizedFileURL.path,
                   let asset = imageByPath[path] {
                    paragraphs.append(imageParagraph(asset, index: imageIndex, maximumWidthInches: 5.5, pageBreakAfter: false))
                    imageIndex += 1
                    if !block.text.isEmpty { paragraphs.append(textParagraph(block.text, style: "Caption", book: book)) }
                } else {
                    paragraphs.append(blockParagraph(block, book: book))
                }
            }
        }
        let layout = book.plan.profile.layout
        let width = Int(layout.pageSize.widthPoints * 20)
        let height = Int(layout.pageSize.heightPoints * 20)
        let headerReference = layout.headerEnabled ? "<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/>" : ""
        let footerReference = (layout.footerEnabled || layout.pageNumbersEnabled) ? "<w:footerReference w:type=\"default\" r:id=\"rIdFooter\"/>" : ""
        let sectionProperties = """
        <w:sectPr>\(headerReference)\(footerReference)<w:pgSz w:w="\(width)" w:h="\(height)"/><w:pgMar w:top="\(Int(layout.topMargin * 20))" w:right="\(Int(layout.outsideMargin * 20))" w:bottom="\(Int(layout.bottomMargin * 20))" w:left="\(Int(layout.insideMargin * 20))" w:header="360" w:footer="360" w:gutter="0"/><w:mirrorMargins/></w:sectPr>
        """
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>\(paragraphs.joined(separator: "\n"))\(sectionProperties)</w:body>
        </w:document>
        """
    }

    private static func blockParagraph(_ block: PublicationBlock, book: PublicationRenderedBook) -> String {
        let style: String
        switch block.kind {
        case .heading(let level): style = "Heading\(min(level, 6))"
        case .code: style = "Code"
        case .blockquote: style = "Quote"
        case .unorderedItem: style = "ListBullet"
        case .orderedItem: style = "ListNumber"
        case .divider: return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"808080\"/></w:pBdr></w:pPr></w:p>"
        default: style = "Normal"
        }
        let text: String
        switch block.kind {
        case .unorderedItem: text = "• \(block.text)"
        case .orderedItem: text = "1. \(block.text)"
        default: text = block.text
        }
        return textParagraph(text, style: style, book: book)
    }

    private static func textParagraph(_ text: String, style: String, book: PublicationRenderedBook) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr>\(inlineRuns(text, book: book))</w:p>"
    }

    private static func inlineRuns(_ text: String, book: PublicationRenderedBook) -> String {
        guard book.plan.profile.citationMode != .parenthetical else { return textRun(text) }
        let source = text as NSString
        let matches = noteMarkerRegex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return textRun(text) }
        var result = ""
        var cursor = 0
        let noteIDs = Set(book.notes.map(\.id))
        for match in matches {
            let number = Int(source.substring(with: match.range(at: 1))) ?? -1
            guard noteIDs.contains(number) else { continue }
            if match.range.location > cursor {
                result += textRun(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let element = book.plan.profile.citationMode == .footnotes ? "footnoteReference" : "endnoteReference"
            result += "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:\(element) w:id=\"\(number)\"/></w:r>"
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { result += textRun(source.substring(from: cursor)) }
        return result
    }

    private static func textRun(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return "<w:r><w:t xml:space=\"preserve\">\(PublicationXML.escape(text))</w:t></w:r>"
    }

    private static func imageParagraph(_ asset: DOCXImageAsset, index: Int, maximumWidthInches: Double, pageBreakAfter: Bool) -> String {
        let image = NSImage(contentsOf: asset.source)
        let rawSize = image?.size ?? CGSize(width: 600, height: 800)
        let width = min(maximumWidthInches * 914_400, max(1, Double(rawSize.width)) * 9_525)
        let ratio = max(0.01, Double(rawSize.height) / max(1, Double(rawSize.width)))
        let height = width * ratio
        return """
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(Int(width))" cy="\(Int(height))"/><wp:docPr id="\(index)" name="\(PublicationXML.escapeAttribute(asset.name))"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(index)" name="\(PublicationXML.escapeAttribute(asset.name))"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(asset.relationshipID)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(Int(width))" cy="\(Int(height))"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>\(pageBreakAfter ? "<w:r><w:br w:type=\"page\"/></w:r>" : "")</w:p>
        """
    }

    private static func documentRelationships(book: PublicationRenderedBook, images: [DOCXImageAsset]) -> String {
        var relationships = [
            "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>",
            "<Relationship Id=\"rIdSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>",
            "<Relationship Id=\"rIdNumbering\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
        ]
        relationships += images.map {
            "<Relationship Id=\"\($0.relationshipID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(PublicationXML.escapeAttribute($0.name))\"/>"
        }
        if book.plan.profile.citationMode == .footnotes, !book.notes.isEmpty {
            relationships.append("<Relationship Id=\"rIdFootnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/>")
        }
        if book.plan.profile.citationMode == .endnotes, !book.notes.isEmpty {
            relationships.append("<Relationship Id=\"rIdEndnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes\" Target=\"endnotes.xml\"/>")
        }
        if book.plan.profile.layout.headerEnabled {
            relationships.append("<Relationship Id=\"rIdHeader\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\"/>")
        }
        if book.plan.profile.layout.footerEnabled || book.plan.profile.layout.pageNumbersEnabled {
            relationships.append("<Relationship Id=\"rIdFooter\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer\" Target=\"footer1.xml\"/>")
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(relationships.joined())</Relationships>"
    }

    private static func notesXML(_ notes: [PublicationNote], element: String) -> String {
        let root = element + "s"
        let entries = notes.map {
            "<w:\(element) w:id=\"\($0.id)\"><w:p><w:r><w:\(element)Ref/></w:r><w:r><w:t xml:space=\"preserve\"> \(PublicationXML.escape($0.text))</w:t></w:r></w:p></w:\(element)>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:\(root) xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:\(element) w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:\(element)><w:\(element) w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:\(element)>\(entries)</w:\(root)>
        """
    }

    private static func stylesXML(_ layout: PublicationLayout) -> String {
        let line = Int(240 * layout.lineHeightMultiple)
        let after = Int(layout.paragraphSpacing * 20)
        let indent = Int(layout.firstLineIndent * 20)
        var headings = ""
        for level in 1...6 {
            let size = Int(layout.bodyFontSize * ([1: 2.0, 2: 1.55, 3: 1.25, 4: 1.12, 5: 1.05, 6: 1.0][level] ?? 1) * 2)
            headings += "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:pPr><w:keepNext/><w:spacing w:before=\"240\" w:after=\"160\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"\(PublicationXML.escapeAttribute(layout.headingFontName))\" w:hAnsi=\"\(PublicationXML.escapeAttribute(layout.headingFontName))\"/><w:b/><w:sz w:val=\"\(size)\"/></w:rPr></w:style>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="\(PublicationXML.escapeAttribute(layout.bodyFontName))" w:hAnsi="\(PublicationXML.escapeAttribute(layout.bodyFontName))"/><w:sz w:val="\(Int(layout.bodyFontSize * 2))"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:line="\(line)" w:lineRule="auto" w:after="\(after)"/><w:ind w:firstLine="\(indent)"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>\(headings)<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="720" w:right="720"/></w:pPr></w:style><w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="Caption"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:i/><w:sz w:val="18"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="ListNumber"><w:name w:val="List Number"/><w:basedOn w:val="Normal"/></w:style></w:styles>
        """
    }

    private static func contentTypes(book: PublicationRenderedBook, images: [DOCXImageAsset]) -> String {
        let defaults = Dictionary(grouping: images, by: { $0.source.pathExtension.lowercased() }).compactMap { ext, values -> String? in
            guard let type = values.first?.mediaType else { return nil }
            return "<Default Extension=\"\(PublicationXML.escapeAttribute(ext))\" ContentType=\"\(type)\"/>"
        }.joined()
        var overrides = [
            "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>",
            "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>",
            "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/>",
            "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>",
            "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>",
            "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        ]
        if book.plan.profile.citationMode == .footnotes, !book.notes.isEmpty { overrides.append("<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/>") }
        if book.plan.profile.citationMode == .endnotes, !book.notes.isEmpty { overrides.append("<Override PartName=\"/word/endnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/>") }
        if book.plan.profile.layout.headerEnabled { overrides.append("<Override PartName=\"/word/header1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/>") }
        if book.plan.profile.layout.footerEnabled || book.plan.profile.layout.pageNumbersEnabled { overrides.append("<Override PartName=\"/word/footer1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>") }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>\(defaults)\(overrides.joined())</Types>"
    }

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
    """

    private static func coreProperties(_ book: PublicationRenderedBook) -> String {
        let author = book.plan.metadata.authors.joined(separator: ", ")
        let date = ISO8601DateFormatter().string(from: Date())
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(PublicationXML.escape(book.plan.metadata.title))</dc:title><dc:creator>\(PublicationXML.escape(author))</dc:creator><dc:description>\(PublicationXML.escape(book.plan.metadata.description))</dc:description><cp:keywords>\(PublicationXML.escape(book.plan.metadata.keywords.joined(separator: ", ")))</cp:keywords><dcterms:created xsi:type="dcterms:W3CDTF">\(date)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(date)</dcterms:modified></cp:coreProperties>
        """
    }

    private static let appProperties = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Kistulentz</Application><AppVersion>0.9.2</AppVersion></Properties>
    """

    private static let settingsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:mirrorMargins/><w:updateFields w:val="true"/><w:compat/></w:settings>
    """

    private static let numberingXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>
    """

    private static func headerXML(_ title: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>\(PublicationXML.escape(title))</w:t></w:r></w:p></w:hdr>"
    }

    private static func footerXML(pageNumbers: Bool) -> String {
        let field = pageNumbers ? "<w:fldSimple w:instr=\"PAGE\"><w:r><w:t>1</w:t></w:r></w:fldSimple>" : "<w:r><w:t>Kistulentz publication proof</w:t></w:r>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr>\(field)</w:p></w:ftr>"
    }
}
