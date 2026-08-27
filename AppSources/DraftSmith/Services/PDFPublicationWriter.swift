import AppKit
import CoreGraphics
import Foundation

private struct PublicationPDFPlacedBlock {
    var block: PublicationBlock
    var rect: CGRect
    var attributedText: NSAttributedString?
}

private struct PublicationPDFPage {
    var blocks: [PublicationPDFPlacedBlock] = []
    var sectionTitle = ""
}

enum PDFPublicationWriter {
    static func write(_ book: PublicationRenderedBook, to outputURL: URL, root: URL) throws {
        let layout = book.plan.profile.layout
        let pageSize = CGSize(width: layout.pageSize.widthPoints, height: layout.pageSize.heightPoints)
        var pages: [PublicationPDFPage] = []

        if book.plan.format == .readerPDF,
           book.plan.profile.includeCover,
           let coverURL = PublicationDisk.resolveAsset(book.plan.metadata.coverImageRelativePath, at: root),
           let image = NSImage(contentsOf: coverURL) {
            let coverBlock = PublicationBlock(kind: .image, text: "", html: "", imageURL: coverURL, altText: book.plan.metadata.coverAltText)
            let fitted = aspectFit(image.size, inside: CGRect(origin: .zero, size: pageSize).insetBy(dx: 24, dy: 24))
            pages.append(PublicationPDFPage(blocks: [PublicationPDFPlacedBlock(block: coverBlock, rect: fitted, attributedText: nil)], sectionTitle: "Cover"))
        }

        var current = PublicationPDFPage()
        var y: CGFloat = 0
        let top = CGFloat(layout.topMargin) + (layout.headerEnabled ? 18 : 0)
        let bottom = CGFloat(layout.bottomMargin) + ((layout.footerEnabled || layout.pageNumbersEnabled) ? 18 : 0)

        func contentRect(pageNumber: Int) -> CGRect {
            let printMirrored = book.plan.format == .printPDF
            let isOdd = pageNumber % 2 == 1
            let left = CGFloat(printMirrored && isOdd ? layout.insideMargin : layout.outsideMargin)
            let right = CGFloat(printMirrored && isOdd ? layout.outsideMargin : layout.insideMargin)
            return CGRect(x: left, y: top, width: pageSize.width - left - right, height: pageSize.height - top - bottom)
        }

        func finishPage() {
            if !current.blocks.isEmpty {
                pages.append(current)
                current = PublicationPDFPage()
            }
            y = top
        }

        func ensurePage(sectionTitle: String) {
            if current.blocks.isEmpty {
                current.sectionTitle = sectionTitle
                y = top
            }
        }

        func addBlock(_ block: PublicationBlock, sectionTitle: String) {
            ensurePage(sectionTitle: sectionTitle)
            var rect = contentRect(pageNumber: pages.count + 1)
            let width = rect.width
            let spacing = verticalSpacing(for: block, layout: layout)
            y += spacing.before
            if block.kind == .image, let url = block.imageURL, let image = NSImage(contentsOf: url) {
                let maximum = CGSize(width: width, height: rect.height * 0.55)
                let size = aspectFit(image.size, inside: CGRect(origin: .zero, size: maximum)).size
                if y + size.height > rect.maxY, !current.blocks.isEmpty {
                    finishPage()
                    ensurePage(sectionTitle: sectionTitle)
                    rect = contentRect(pageNumber: pages.count + 1)
                    y += spacing.before
                }
                let placed = CGRect(x: rect.midX - size.width / 2, y: y, width: size.width, height: size.height)
                current.blocks.append(PublicationPDFPlacedBlock(block: block, rect: placed, attributedText: nil))
                y += size.height + spacing.after
                if !block.text.isEmpty {
                    addBlock(PublicationBlock(kind: .paragraph, text: block.text, html: "", imageURL: nil, altText: ""), sectionTitle: sectionTitle)
                }
                return
            }

            let attributed = attributedString(for: block, layout: layout)
            let measured = attributed.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).integral
            if measured.height > rect.height {
                let chunks = splitText(block.text, kind: block.kind, width: width, maximumHeight: rect.height, layout: layout)
                if chunks.count > 1 {
                    for chunk in chunks {
                        var continuation = block
                        continuation.text = chunk
                        addBlock(continuation, sectionTitle: sectionTitle)
                    }
                    return
                }
            }
            let blockFont = font(for: block, layout: layout)
            let minimumLineHeight = blockFont.ascender - blockFont.descender + blockFont.leading
            let height = max(ceil(measured.height), minimumLineHeight)
            if y + height > rect.maxY, !current.blocks.isEmpty {
                finishPage()
                ensurePage(sectionTitle: sectionTitle)
                rect = contentRect(pageNumber: pages.count + 1)
                y += spacing.before
            }
            let placed = CGRect(x: rect.minX, y: y, width: width, height: min(height, rect.maxY - y))
            current.blocks.append(PublicationPDFPlacedBlock(block: block, rect: placed, attributedText: attributed))
            y += height + spacing.after
        }

        for (sectionIndex, section) in book.sections.enumerated() {
            if sectionIndex > 0 && book.plan.profile.layout.chapterOpening != .continuous {
                finishPage()
                if book.plan.format == .printPDF,
                   book.plan.profile.layout.chapterOpening == .recto,
                   (pages.count + 1) % 2 == 0 {
                    pages.append(PublicationPDFPage(sectionTitle: ""))
                }
            }
            for block in section.blocks { addBlock(block, sectionTitle: section.title) }
            if book.plan.profile.citationMode == .footnotes, !section.noteIDs.isEmpty {
                addBlock(PublicationBlock(kind: .heading(3), text: "Notes", html: "", imageURL: nil, altText: ""), sectionTitle: section.title)
                let ids = Set(section.noteIDs)
                for note in book.notes where ids.contains(note.id) {
                    addBlock(PublicationBlock(kind: .paragraph, text: "\(note.id). \(note.text)", html: "", imageURL: nil, altText: ""), sectionTitle: section.title)
                }
            }
        }
        finishPage()
        guard !pages.isEmpty else { throw PublicationExportError.outputCreationFailed("No printable pages were generated.") }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PublicationExportError.outputCreationFailed("The PDF destination could not be opened.")
        }
        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            NSColor.textColor.set()
            for placed in page.blocks {
                if placed.block.kind == .image,
                   let url = placed.block.imageURL,
                   let image = NSImage(contentsOf: url) {
                    image.draw(in: placed.rect, from: .zero, operation: .sourceOver, fraction: 1)
                } else {
                    placed.attributedText?.draw(with: placed.rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
                }
            }
            drawRunningMatter(page: page, pageNumber: index + 1, pageSize: pageSize, layout: layout)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func attributedString(for block: PublicationBlock, layout: PublicationLayout) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = layout.lineHeightMultiple
        paragraph.paragraphSpacing = 0
        paragraph.hyphenationFactor = layout.hyphenationEnabled ? 0.85 : 0
        paragraph.firstLineHeadIndent = block.kind == .paragraph ? layout.firstLineIndent : 0
        if block.kind == .blockquote {
            paragraph.headIndent = 22
            paragraph.tailIndent = -22
        }
        if block.kind == .unorderedItem || block.kind == .orderedItem { paragraph.headIndent = 18 }
        if case .heading(1) = block.kind { paragraph.alignment = .center }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: block, layout: layout),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph
        ]
        let prefix: String
        switch block.kind {
        case .unorderedItem: prefix = "•  "
        case .orderedItem: prefix = "1.  "
        default: prefix = ""
        }
        return NSAttributedString(string: prefix + block.text, attributes: attributes)
    }

    private static func font(for block: PublicationBlock, layout: PublicationLayout) -> NSFont {
        let body = NSFont(name: layout.bodyFontName, size: layout.bodyFontSize)
            ?? NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.serif) ?? .preferredFontDescriptor(forTextStyle: .body), size: layout.bodyFontSize)
            ?? NSFont.systemFont(ofSize: layout.bodyFontSize)
        switch block.kind {
        case .heading(let level):
            let multiplier: CGFloat = [1: 2.0, 2: 1.55, 3: 1.25, 4: 1.12, 5: 1.05, 6: 1.0][level] ?? 1
            return NSFont(name: layout.headingFontName, size: layout.bodyFontSize * multiplier)
                ?? NSFont.systemFont(ofSize: layout.bodyFontSize * multiplier, weight: level <= 2 ? .bold : .semibold)
        case .code:
            return NSFont.monospacedSystemFont(ofSize: max(8, layout.bodyFontSize - 1), weight: .regular)
        default:
            return body
        }
    }

    private static func verticalSpacing(for block: PublicationBlock, layout: PublicationLayout) -> (before: CGFloat, after: CGFloat) {
        switch block.kind {
        case .heading(1): (18, 18)
        case .heading(2): (14, 10)
        case .heading: (10, 6)
        case .divider: (9, 9)
        case .image: (10, 10)
        case .code: (6, 8)
        default: (0, layout.paragraphSpacing)
        }
    }

    private static func splitText(
        _ text: String,
        kind: PublicationBlockKind,
        width: CGFloat,
        maximumHeight: CGFloat,
        layout: PublicationLayout
    ) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else { return [text] }
        var chunks: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            let block = PublicationBlock(kind: kind, text: candidate, html: "", imageURL: nil, altText: "")
            let height = attributedString(for: block, layout: layout).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            if height <= maximumHeight || current.isEmpty {
                current = candidate
            } else {
                chunks.append(current)
                current = word
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func drawRunningMatter(page: PublicationPDFPage, pageNumber: Int, pageSize: CGSize, layout: PublicationLayout) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        if layout.headerEnabled, !page.sectionTitle.isEmpty {
            let title = NSAttributedString(string: page.sectionTitle, attributes: attributes)
            title.draw(in: CGRect(x: layout.outsideMargin, y: max(12, layout.topMargin - 24), width: pageSize.width - layout.insideMargin - layout.outsideMargin, height: 12))
        }
        if layout.footerEnabled {
            let footer = NSAttributedString(string: "Kistulentz publication proof", attributes: attributes)
            footer.draw(in: CGRect(x: layout.outsideMargin, y: pageSize.height - layout.bottomMargin + 8, width: 180, height: 12))
        }
        if layout.pageNumbersEnabled {
            let number = NSAttributedString(string: String(pageNumber), attributes: attributes)
            let size = number.size()
            number.draw(at: CGPoint(x: (pageSize.width - size.width) / 2, y: pageSize.height - max(18, layout.bottomMargin - 20)))
        }
    }

    private static func aspectFit(_ imageSize: CGSize, inside bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}
