import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDocument, .plainText] }

    var text: String

    init(text: String = MarkdownDocument.starterText) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(text))
    }

    /// Kept separate from SwiftUI's configuration types so document encoding can be
    /// regression-tested without presenting a document window.
    static func decode(_ data: Data) throws -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        if let decoded = String(data: data, encoding: .isoLatin1) {
            return decoded
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    static func encode(_ text: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    private static let starterText = """
    # A clearer first draft

    Good writing makes its point without making the reader work for it. Kistulentz highlights long sentences, passive voice, adverbs, and phrases that could be simpler.

    Write or paste Markdown here. Set a target reading grade, then use Local Polish for private built-in corrections. Connect Ollama, OpenAI, or Anthropic only when you want generative rewriting.
    """
}
