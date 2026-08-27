import Foundation

enum EPUBPublicationWriter {
    static func write(_ book: PublicationRenderedBook, to outputURL: URL, root: URL) throws {
        let temporary = try PublicationArchiveUtility.temporaryDirectory(prefix: "Kistulentz-EPUB")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let metaInf = temporary.appendingPathComponent("META-INF", isDirectory: true)
        let epub = temporary.appendingPathComponent("EPUB", isDirectory: true)
        let text = epub.appendingPathComponent("text", isDirectory: true)
        let styles = epub.appendingPathComponent("styles", isDirectory: true)
        let images = epub.appendingPathComponent("images", isDirectory: true)
        for directory in [metaInf, epub, text, styles, images] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try "application/epub+zip".write(to: temporary.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)
        try containerXML.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)
        try stylesheet(for: book.plan.profile.layout).write(to: styles.appendingPathComponent("book.css"), atomically: true, encoding: .utf8)

        var imageManifest: [(id: String, href: String, mediaType: String, properties: String?)] = []
        for (index, image) in book.images.enumerated() {
            guard let mediaType = PublicationMediaType.epub(for: image.source) else {
                throw PublicationExportError.unsupportedImage(image.source.lastPathComponent)
            }
            try FileManager.default.copyItem(at: image.source, to: images.appendingPathComponent(image.name))
            imageManifest.append(("image-\(index + 1)", "images/\(image.name)", mediaType, nil))
        }

        var coverFileName: String?
        if book.plan.profile.includeCover,
           let coverURL = PublicationDisk.resolveAsset(book.plan.metadata.coverImageRelativePath, at: root) {
            guard let mediaType = PublicationMediaType.epub(for: coverURL) else {
                throw PublicationExportError.unsupportedImage(coverURL.lastPathComponent)
            }
            let name = "cover.\(coverURL.pathExtension.lowercased())"
            try FileManager.default.copyItem(at: coverURL, to: images.appendingPathComponent(name))
            imageManifest.append(("cover-image", "images/\(name)", mediaType, "cover-image"))
            coverFileName = name
            let cover = coverXHTML(book: book, imageName: name)
            try cover.write(to: text.appendingPathComponent("cover.xhtml"), atomically: true, encoding: .utf8)
        }

        let sectionFiles = Dictionary(uniqueKeysWithValues: book.sections.enumerated().map { index, section in
            (section.id, "section-\(String(format: "%03d", index + 1)).xhtml")
        })
        var visibleTOC: [(title: String, href: String, depth: Int)] = []
        for (index, section) in book.sections.enumerated() {
            let fileName = sectionFiles[section.id]!
            var body = section.bodyHTML
            if section.id == "matter-tableOfContents" {
                body = visibleTableOfContents(book.sections, files: sectionFiles)
            }
            if book.plan.profile.citationMode == .footnotes {
                let ids = Set(section.noteIDs)
                let sectionNotes = book.notes.filter { ids.contains($0.id) }.map {
                    "<aside id=\"footnote-\($0.id)\" epub:type=\"footnote\" role=\"doc-footnote\"><p><sup>\($0.id)</sup> \(PublicationXML.escape($0.text))</p></aside>"
                }.joined(separator: "\n")
                body += sectionNotes
            }
            let content = xhtmlDocument(
                title: section.title,
                language: book.plan.metadata.language,
                body: "<section id=\"\(PublicationXML.slug(section.id))\">\(body)</section>"
            )
            try content.write(to: text.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            if section.kind == .part || section.kind == .manuscript {
                visibleTOC.append((section.title, "text/\(fileName)", section.kind == .part ? 0 : 1))
            }
            _ = index
        }

        try navigationXHTML(book: book, entries: visibleTOC).write(to: epub.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
        try packageOPF(
            book: book,
            sectionCount: book.sections.count,
            images: imageManifest,
            hasCover: coverFileName != nil,
            hasFootnotes: false
        ).write(to: epub.appendingPathComponent("package.opf"), atomically: true, encoding: .utf8)
        try PublicationArchiveUtility.zip(directory: temporary, to: outputURL, epub: true)
    }

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """

    private static func xhtmlDocument(title: String, language: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(PublicationXML.escapeAttribute(language))" lang="\(PublicationXML.escapeAttribute(language))">
        <head><meta charset="utf-8"/><title>\(PublicationXML.escape(title))</title><link rel="stylesheet" type="text/css" href="../styles/book.css"/></head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func coverXHTML(book: PublicationRenderedBook, imageName: String) -> String {
        xhtmlDocument(
            title: "Cover",
            language: book.plan.metadata.language,
            body: "<section epub:type=\"cover\"><h1 class=\"visually-hidden\">Cover</h1><img class=\"cover\" src=\"../images/\(PublicationXML.escapeAttribute(imageName))\" alt=\"\(PublicationXML.escapeAttribute(book.plan.metadata.coverAltText))\"/></section>"
        )
    }

    private static func visibleTableOfContents(_ sections: [PublicationRenderedSection], files: [String: String]) -> String {
        let entries = sections.filter { $0.kind == .part || $0.kind == .manuscript }.map { section in
            "<li class=\"\(section.kind == .part ? "part" : "chapter")\"><a href=\"\(PublicationXML.escapeAttribute(files[section.id] ?? ""))\">\(PublicationXML.escape(section.title))</a></li>"
        }.joined(separator: "\n")
        return "<nav epub:type=\"toc\" aria-label=\"Table of Contents\"><h1>Table of Contents</h1><ol>\(entries)</ol></nav>"
    }

    private static func navigationXHTML(book: PublicationRenderedBook, entries: [(title: String, href: String, depth: Int)]) -> String {
        let list = entries.map {
            "<li class=\"level-\($0.depth)\"><a href=\"\(PublicationXML.escapeAttribute($0.href))\">\(PublicationXML.escape($0.title))</a></li>"
        }.joined(separator: "\n")
        let landmarks = "<nav epub:type=\"landmarks\" hidden=\"hidden\"><h2>Landmarks</h2><ol><li><a epub:type=\"bodymatter\" href=\"\(PublicationXML.escapeAttribute(entries.first?.href ?? "text/section-001.xhtml"))\">Start of content</a></li></ol></nav>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(PublicationXML.escapeAttribute(book.plan.metadata.language))" lang="\(PublicationXML.escapeAttribute(book.plan.metadata.language))">
        <head><meta charset="utf-8"/><title>Navigation</title><link rel="stylesheet" type="text/css" href="styles/book.css"/></head>
        <body><nav epub:type="toc" id="toc" aria-label="Table of Contents"><h1>Contents</h1><ol>\(list)</ol></nav>\(landmarks)</body>
        </html>
        """
    }

    private static func packageOPF(
        book: PublicationRenderedBook,
        sectionCount: Int,
        images: [(id: String, href: String, mediaType: String, properties: String?)],
        hasCover: Bool,
        hasFootnotes: Bool
    ) -> String {
        let metadata = book.plan.metadata
        let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: #"\.\d+Z$"#, with: "Z", options: .regularExpression)
        let creators = metadata.authors.enumerated().map { index, author in
            "<dc:creator id=\"creator-\(index + 1)\">\(PublicationXML.escape(author))</dc:creator>"
        }.joined(separator: "\n")
        let subjects = metadata.keywords.map { "<dc:subject>\(PublicationXML.escape($0))</dc:subject>" }.joined(separator: "\n")
        let optional = [
            metadata.publisher.isEmpty ? "" : "<dc:publisher>\(PublicationXML.escape(metadata.publisher))</dc:publisher>",
            metadata.rights.isEmpty ? "" : "<dc:rights>\(PublicationXML.escape(metadata.rights))</dc:rights>",
            metadata.description.isEmpty ? "" : "<dc:description>\(PublicationXML.escape(metadata.description))</dc:description>",
            metadata.publicationDate.isEmpty ? "" : "<dc:date>\(PublicationXML.escape(metadata.publicationDate))</dc:date>"
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        let accessibility = """
        <meta property="schema:accessMode">textual</meta>
        <meta property="schema:accessModeSufficient">textual</meta>
        <meta property="schema:accessibilityFeature">tableOfContents</meta>
        <meta property="schema:accessibilityFeature">structuralNavigation</meta>
        <meta property="schema:accessibilityHazard">none</meta>
        """
        let sectionManifest = (1...sectionCount).map {
            "<item id=\"section-\($0)\" href=\"text/section-\(String(format: "%03d", $0)).xhtml\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")
        let imageItems = images.map { image in
            "<item id=\"\(image.id)\" href=\"\(PublicationXML.escapeAttribute(image.href))\" media-type=\"\(image.mediaType)\"\(image.properties.map { " properties=\"\($0)\"" } ?? "")/>"
        }.joined(separator: "\n")
        let spine = (1...sectionCount).map { "<itemref idref=\"section-\($0)\"/>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="publication-id" prefix="schema: http://schema.org/">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="publication-id">\(PublicationXML.escape(metadata.identifier))</dc:identifier>
            <dc:title>\(PublicationXML.escape(metadata.title))</dc:title>
            <dc:language>\(PublicationXML.escape(metadata.language))</dc:language>
            \(creators)
            \(subjects)
            \(optional)
            <meta property="dcterms:modified">\(modified)</meta>
            \(accessibility)
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="css" href="styles/book.css" media-type="text/css"/>
            \(hasCover ? "<item id=\"cover-page\" href=\"text/cover.xhtml\" media-type=\"application/xhtml+xml\"/>" : "")
            \(hasFootnotes ? "<item id=\"footnotes\" href=\"text/footnotes.xhtml\" media-type=\"application/xhtml+xml\"/>" : "")
            \(sectionManifest)
            \(imageItems)
          </manifest>
          <spine>
            \(hasCover ? "<itemref idref=\"cover-page\"/>" : "")
            \(spine)
            \(hasFootnotes ? "<itemref idref=\"footnotes\"/>" : "")
          </spine>
        </package>
        """
    }

    private static func stylesheet(for layout: PublicationLayout) -> String {
        """
        :root { color-scheme: light dark; }
        html { -webkit-hyphens: \(layout.hyphenationEnabled ? "auto" : "none"); hyphens: \(layout.hyphenationEnabled ? "auto" : "none"); }
        body { font-family: \"\(layout.bodyFontName)\", serif; line-height: \(layout.lineHeightMultiple); margin: 5%; }
        h1, h2, h3, h4, h5, h6 { font-family: \"\(layout.headingFontName)\", sans-serif; line-height: 1.2; break-after: avoid; }
        h1 { margin-top: 15%; text-align: center; }
        p { margin: 0 0 \(layout.paragraphSpacing / max(layout.bodyFontSize, 1))em; text-indent: \(layout.firstLineIndent / max(layout.bodyFontSize, 1))em; }
        blockquote { margin: 1em 8%; }
        pre { white-space: pre-wrap; }
        figure { break-inside: avoid; margin: 1.5em auto; text-align: center; }
        img { height: auto; max-width: 100%; }
        img.cover { display: block; margin: 0 auto; max-height: 95vh; }
        figcaption { font-size: .85em; margin-top: .35em; }
        .bibliography-entry { padding-left: 1.5em; text-indent: -1.5em; }
        .visually-hidden { clip: rect(1px,1px,1px,1px); clip-path: inset(50%); height: 1px; overflow: hidden; position: absolute; width: 1px; }
        nav ol { list-style: none; padding-left: 0; }
        nav .level-1 { margin-left: 1.5em; }
        """
    }
}
