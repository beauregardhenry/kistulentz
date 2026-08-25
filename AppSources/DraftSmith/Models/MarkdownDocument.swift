import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDocument] }

    var text: String

    init(text: String = MarkdownDocument.starterText) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if let decoded = String(data: data, encoding: .utf8) {
            text = decoded
        } else if let decoded = String(data: data, encoding: .isoLatin1) {
            text = decoded
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    private static let starterText = """
    # A clearer first draft

    Good writing makes its point without making the reader work for it. Kistuletz highlights long sentences, passive voice, adverbs, and phrases that could be simpler.

    Write or paste Markdown here. Set a target reading grade, then ask OpenAI or Claude for a polished revision when you are ready.
    """
}
