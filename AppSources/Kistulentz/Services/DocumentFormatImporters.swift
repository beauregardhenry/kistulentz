import AppKit
import Foundation

protocol DocumentFormatImporter {
    static func load(from url: URL) throws -> DocumentImportDraft
}

enum PlainTextDocumentImporter: DocumentFormatImporter {
    static func load(from url: URL) throws -> DocumentImportDraft {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = DocumentImportService.decodedText(data) else {
            throw DocumentImportError.unreadableDocument
        }
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
}

enum HTMLDocumentImporter: DocumentFormatImporter {
    static func load(from url: URL) throws -> DocumentImportDraft {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let source = DocumentImportService.decodedText(data) else {
            throw DocumentImportError.unreadableDocument
        }
        let sanitized = HTMLImportSanitizer.prepare(source, sourceURL: url)
        guard let cleanData = sanitized.html.data(using: .utf8) else {
            throw DocumentImportError.unreadableDocument
        }
        let attributed = try NSAttributedString(
            data: cleanData,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        )
        return RichDocumentImportDraftBuilder.make(
            sourceURL: url,
            format: .html,
            conversion: AttributedMarkdownImporter.convert(
                attributed,
                seededAssets: sanitized.assets,
                seededNotices: sanitized.notices
            ),
            layoutDetail: "CSS, page layout, forms, scripts, and interactive elements are not carried into Markdown."
        )
    }
}

enum AttributedDocumentImporter {
    static func load(
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
        return RichDocumentImportDraftBuilder.make(
            sourceURL: url,
            format: format,
            conversion: AttributedMarkdownImporter.convert(attributed),
            layoutDetail: "Page geometry, headers, footers, and exact typography are not carried into Markdown."
        )
    }
}

enum RichDocumentImportDraftBuilder {
    static func make(
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
            assets: DocumentImportService.uniqueAssets(conversion.assets),
            notices: DocumentImportService.uniqueNotices(notices)
        )
    }
}
