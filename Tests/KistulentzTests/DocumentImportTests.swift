import AppKit
import XCTest
@testable import Kistulentz

final class DocumentImportTests: XCTestCase {
    func testMarkdownDocumentUTF8RoundTripPreservesUnicodeAndMarkdownExactly() throws {
        let original = "# Tide 🌊\n\n**Café** — [harbor](https://example.com).\n"

        let encoded = try MarkdownDocument.encode(original)
        let decoded = try MarkdownDocument.decode(encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(encoded, Data(original.utf8))
    }

    func testMarkdownDocumentReadsLegacyLatin1WithoutReplacementCharacters() throws {
        let bytes = Data([0x43, 0x61, 0x66, 0xE9, 0x0A])

        XCTAssertEqual(try MarkdownDocument.decode(bytes), "Café\n")
    }

    func testNewMarkdownDocumentProvidesAnEditableLocalFirstStartingDraft() {
        let document = MarkdownDocument()

        XCTAssertTrue(document.text.contains("# A clearer first draft"))
        XCTAssertTrue(document.text.contains("Local Polish"))
        XCTAssertFalse(document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testStaticMacOSSavedDocumentsImportWithoutChangingTheirBytes() throws {
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RealImports", isDirectory: true)
        let names = [
            "macOS-Saved.docx",
            "macOS-Saved.rtf",
            "macOS-Saved.rtfd",
            "macOS-Saved.html",
            "macOS-Saved.odt",
            "Fixture-Source.txt"
        ]

        for name in names {
            let source = fixtureRoot.appendingPathComponent(name)
            let before = try fixtureFingerprint(source)
            let draft = try DocumentImportService.load(from: source)
            let markdown = draft.renderedMarkdown(decisions: [:])

            XCTAssertTrue(markdown.contains("Real Application Fixture"), name)
            XCTAssertTrue(markdown.contains("document services"), name)
            XCTAssertEqual(try fixtureFingerprint(source), before, name)
        }
    }

    func testPlainTextCanBeEditedDirectlyAndImportedAsASafeMarkdownCopy() throws {
        XCTAssertTrue(MarkdownDocument.readableContentTypes.contains(.plainText))
        XCTAssertTrue(MarkdownDocument.writableContentTypes.contains(.plainText))
        XCTAssertEqual(DocumentImportFormat.format(for: URL(fileURLWithPath: "/tmp/draft.text")), .plainText)

        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Draft.txt")
        let output = root.appendingPathComponent("Draft.md")
        try "A plain-text draft.".write(to: source, atomically: true, encoding: .utf8)

        let draft = try DocumentImportService.load(from: source)
        let result = try DocumentImportService.save(draft, decisions: [:], to: output)

        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "A plain-text draft.")
        XCTAssertEqual(try String(contentsOf: result.markdownURL, encoding: .utf8), "A plain-text draft.\n")
        XCTAssertNil(result.assetFolderURL)
    }

    func testHTMLImportPreservesStructureAndNeverDownloadsRemoteImages() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("local.png"))
        let source = root.appendingPathComponent("Article.html")
        try """
        <html><head><title>Article</title><link rel="stylesheet" href="https://example.com/style.css"></head>
        <body>
        <h1>Article Title</h1>
        <p><strong>Bold</strong> and <em>italic</em> with <a href="https://example.com">a link</a>.</p>
        <ul><li>First item</li><li>Second item</li></ul>
        <img src="local.png" alt="Local diagram">
        <img src="https://example.com/tracker.png" alt="Remote tracker">
        <script>fetch('https://example.com/private')</script>
        </body></html>
        """.write(to: source, atomically: true, encoding: .utf8)

        let draft = try DocumentImportService.load(from: source)
        let markdown = draft.renderedMarkdown(decisions: [:])

        XCTAssertTrue(markdown.contains("# Article Title"))
        XCTAssertTrue(markdown.contains("**Bold**"))
        XCTAssertTrue(markdown.contains("*italic*"))
        XCTAssertTrue(markdown.contains("[a link](<https://example.com/>)"))
        XCTAssertTrue(markdown.contains("- First item"))
        XCTAssertTrue(markdown.contains("![Local diagram]"))
        XCTAssertTrue(markdown.contains("Remote tracker"))
        XCTAssertFalse(markdown.contains("fetch("))
        XCTAssertEqual(draft.assets.count, 1)
        XCTAssertTrue(draft.notices.contains { $0.title == "Remote images were not downloaded" })
    }

    func testHTMLImportStripsExecutableLinksEventsAndEscapingLocalImages() throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outside.appendingPathComponent("private.png"))
        let source = root.appendingPathComponent("Unsafe.html")
        try """
        <html><body onload="sendSecrets()">
        <h1>Safe text</h1>
        <a href="javascript:sendSecrets()" onclick="sendSecrets()">unsafe action</a>
        <a href="https://example.com/essay">safe essay</a>
        <img src="../\(outside.lastPathComponent)/private.png" alt="private file">
        <img src="file:///etc/passwd" alt="system file">
        </body></html>
        """.write(to: source, atomically: true, encoding: .utf8)

        let draft = try DocumentImportService.load(from: source)
        let markdown = draft.renderedMarkdown(decisions: [:])

        XCTAssertTrue(markdown.contains("unsafe action"))
        XCTAssertFalse(markdown.lowercased().contains("javascript:"))
        XCTAssertFalse(markdown.contains("sendSecrets"))
        XCTAssertTrue(markdown.contains("https://example.com/essay"))
        XCTAssertTrue(markdown.contains("private file"))
        XCTAssertTrue(markdown.contains("system file"))
        XCTAssertTrue(draft.assets.isEmpty)
    }

    func testRTFAndRTFDImportAsMarkdownCopies() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rtf = #"{\rtf1\ansi This is \b bold\b0  and \i italic\i0 .}"#
        let rtfURL = root.appendingPathComponent("Draft.rtf")
        try Data(rtf.utf8).write(to: rtfURL)

        let rtfdURL = root.appendingPathComponent("Package.rtfd", isDirectory: true)
        try FileManager.default.createDirectory(at: rtfdURL, withIntermediateDirectories: true)
        try Data(rtf.utf8).write(to: rtfdURL.appendingPathComponent("TXT.rtf"))

        let rtfDraft = try DocumentImportService.load(from: rtfURL)
        let rtfdDraft = try DocumentImportService.load(from: rtfdURL)

        XCTAssertTrue(rtfDraft.renderedMarkdown(decisions: [:]).contains("**bold**"))
        XCTAssertTrue(rtfDraft.renderedMarkdown(decisions: [:]).contains("*italic*"))
        XCTAssertTrue(rtfdDraft.renderedMarkdown(decisions: [:]).contains("This is"))
        XCTAssertEqual(rtfdDraft.format, .rtfd)
    }

    func testODTImportPreservesHeadingsAndParagraphs() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeODT(in: root)

        let draft = try DocumentImportService.load(from: source)
        let markdown = draft.renderedMarkdown(decisions: [:])

        XCTAssertEqual(draft.format, .odt)
        XCTAssertTrue(markdown.contains("ODT Title"))
        XCTAssertTrue(markdown.contains("An OpenDocument paragraph."))
    }

    func testDOCXImportPreservesStructureAssetsNotesAndTrackedChanges() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeDOCX(in: root)
        let originalData = try Data(contentsOf: source)

        let draft = try DocumentImportService.load(from: source)
        XCTAssertEqual(draft.format, .docx)
        XCTAssertEqual(draft.reviewCards.count, 2)
        XCTAssertEqual(Set(draft.reviewCards.map(\.kind)), Set([.insertion, .deletion]))
        XCTAssertEqual(draft.assets.count, 1)
        XCTAssertTrue(draft.templateMarkdown.contains("# Imported Heading"))
        XCTAssertTrue(draft.templateMarkdown.contains("**bold**"))
        XCTAssertTrue(draft.templateMarkdown.contains("*italic*"))
        XCTAssertTrue(draft.templateMarkdown.contains("[website](<https://example.com>)"))
        XCTAssertTrue(draft.templateMarkdown.contains("- List item"))
        XCTAssertTrue(draft.templateMarkdown.contains("| Column A | Column B |"))
        XCTAssertTrue(draft.templateMarkdown.contains("[^1]: A footnote."))
        XCTAssertTrue(draft.templateMarkdown.contains("Comment by Editor: Check this sentence."))

        let accept = Dictionary(uniqueKeysWithValues: draft.reviewCards.map { ($0.id, DocumentTrackedChangeDecision.accept) })
        let reject = Dictionary(uniqueKeysWithValues: draft.reviewCards.map { ($0.id, DocumentTrackedChangeDecision.reject) })
        let accepted = draft.renderedMarkdown(decisions: accept)
        let rejected = draft.renderedMarkdown(decisions: reject)
        XCTAssertTrue(accepted.contains("new text"))
        XCTAssertFalse(accepted.contains("old text"))
        XCTAssertFalse(rejected.contains("new text"))
        XCTAssertTrue(rejected.contains("old text"))

        XCTAssertThrowsError(try DocumentImportService.save(
            draft,
            decisions: [draft.reviewCards[0].id: .accept],
            to: root.appendingPathComponent("Incomplete.md")
        )) { error in
            XCTAssertEqual(error as? DocumentImportError, .unresolvedTrackedChanges)
        }

        let output = root.appendingPathComponent("Converted.md")
        let saved = try DocumentImportService.save(draft, decisions: accept, to: output)
        let savedMarkdown = try String(contentsOf: saved.markdownURL, encoding: .utf8)
        let assetFolder = try XCTUnwrap(saved.assetFolderURL)
        XCTAssertTrue(savedMarkdown.contains("Converted-assets/image1.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetFolder.appendingPathComponent("image1.png").path))
        XCTAssertEqual(try Data(contentsOf: source), originalData)
    }

    func testImporterRejectsUnsupportedFilesAndNeverOverwritesTheSource() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let unsupported = root.appendingPathComponent("Draft.pdf")
        try Data("%PDF".utf8).write(to: unsupported)
        XCTAssertThrowsError(try DocumentImportService.load(from: unsupported))

        let source = root.appendingPathComponent("Draft.txt")
        try "Source".write(to: source, atomically: true, encoding: .utf8)
        let draft = try DocumentImportService.load(from: source)
        XCTAssertThrowsError(try DocumentImportService.save(draft, decisions: [:], to: source)) { error in
            XCTAssertEqual(error as? DocumentImportError, .sourceWouldBeOverwritten)
        }
    }

    func testDOCXRejectsOversizedArchiveBeforeExtraction() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Oversized.docx")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 250_000_001)
        try handle.close()

        XCTAssertThrowsError(try DocumentImportService.load(from: source)) { error in
            XCTAssertEqual(error as? DocumentImportError, .documentTooLarge)
        }
    }

    func testDOCXRejectsArchiveEntryThatEscapesItsPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        let word = package.appendingPathComponent("xx/word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)
        try "<document/>".write(
            to: word.appendingPathComponent("document.xml"),
            atomically: true,
            encoding: .utf8
        )
        let source = root.appendingPathComponent("Traversal.docx")
        try runZip(arguments: ["-Xqr", source.path, "xx"], in: package)

        // Keep the ZIP directory records valid while replacing a same-length safe
        // prefix with a parent traversal in both the local and central headers.
        var archive = try Data(contentsOf: source)
        let safePrefix = Data("xx/".utf8)
        let unsafePrefix = Data("../".utf8)
        var searchStart = archive.startIndex
        var replacementCount = 0
        while let range = archive.range(of: safePrefix, in: searchStart..<archive.endIndex) {
            archive.replaceSubrange(range, with: unsafePrefix)
            searchStart = range.lowerBound + unsafePrefix.count
            replacementCount += 1
        }
        XCTAssertGreaterThan(replacementCount, 0)
        try archive.write(to: source, options: .atomic)

        XCTAssertThrowsError(try DocumentImportService.load(from: source)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unsafeArchive)
        }
    }

    func testDOCXRejectsMalformedDocumentXMLWithoutWritingAnything() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("malformed-package", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)
        try "<w:document><w:body>".write(
            to: word.appendingPathComponent("document.xml"),
            atomically: true,
            encoding: .utf8
        )
        let source = root.appendingPathComponent("Malformed.docx")
        try runZip(arguments: ["-Xqr", source.path, "word"], in: package)

        XCTAssertThrowsError(try DocumentImportService.load(from: source)) { error in
            XCTAssertEqual(error as? DocumentImportError, .unreadableDocument)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), [
            "Malformed.docx", "malformed-package"
        ])
    }

    func testMalformedODTRTFAndRTFDPackagesFailWithoutCreatingMarkdown() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let odtPackage = root.appendingPathComponent("bad-odt", isDirectory: true)
        try FileManager.default.createDirectory(at: odtPackage, withIntermediateDirectories: true)
        try "application/vnd.oasis.opendocument.text".write(
            to: odtPackage.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8
        )
        let odt = root.appendingPathComponent("Malformed.odt")
        try runZip(arguments: ["-Xqr", odt.path, "mimetype"], in: odtPackage)

        let rtf = root.appendingPathComponent("Malformed.rtf")
        try Data([0x00, 0x01, 0x02, 0x03, 0x04]).write(to: rtf)

        let rtfd = root.appendingPathComponent("Malformed.rtfd", isDirectory: true)
        try FileManager.default.createDirectory(at: rtfd, withIntermediateDirectories: true)
        try "not rtf".write(to: rtfd.appendingPathComponent("unexpected.txt"), atomically: true, encoding: .utf8)

        for source in [odt, rtf, rtfd] {
            XCTAssertThrowsError(try DocumentImportService.load(from: source), source.lastPathComponent)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Malformed.md").path))
    }

    func testAssetNamesAreSanitizedAndDeduplicatedCaseInsensitively() {
        let assets = [
            DocumentImportAsset(suggestedFilename: "../Résumé.PNG", altText: "One", data: Data([1])),
            DocumentImportAsset(suggestedFilename: "résumé.png", altText: "Two", data: Data([2])),
            DocumentImportAsset(suggestedFilename: "RESUME.PNG", altText: "Three", data: Data([3])),
            DocumentImportAsset(suggestedFilename: "..", altText: "Four", data: Data([4]))
        ]

        let unique = DocumentImportService.uniqueAssets(assets)
        let names = unique.map(\.suggestedFilename)

        XCTAssertEqual(Set(names.map { $0.lowercased() }).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.contains("/") && !$0.contains("..") })
        XCTAssertEqual(unique.map(\.data), assets.map(\.data))
    }

    func testFailedMarkdownWriteCleansUpCopiedImportAssets() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.html")
        try "<p>Draft</p>".write(to: source, atomically: true, encoding: .utf8)
        let draft = DocumentImportDraft(
            sourceURL: source,
            format: .html,
            templateMarkdown: "Draft\n",
            assets: [DocumentImportAsset(suggestedFilename: "image.png", altText: "Image", data: Data([1, 2, 3]))]
        )
        let output = root.appendingPathComponent("Blocked.md", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        XCTAssertThrowsError(try DocumentImportService.save(draft, decisions: [:], to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Blocked-assets").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeDOCX(in root: URL) throws -> URL {
        let package = root.appendingPathComponent("docx-package", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        let rels = word.appendingPathComponent("_rels", isDirectory: true)
        let media = word.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: rels, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Imported Heading</w:t></w:r></w:p>
            <w:p>
              <w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r><w:r><w:t xml:space="preserve"> and </w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>italic</w:t></w:r><w:r><w:t xml:space="preserve"> with </w:t></w:r>
              <w:hyperlink r:id="rId2"><w:r><w:t>website</w:t></w:r></w:hyperlink><w:r><w:t>. </w:t></w:r>
              <w:ins w:author="Author" w:date="2026-08-29T12:00:00Z"><w:r><w:t>new text</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> </w:t></w:r>
              <w:del w:author="Editor" w:date="2026-08-28T12:00:00Z"><w:r><w:delText>old text</w:delText></w:r></w:del>
              <w:r><w:footnoteReference w:id="1"/><w:commentReference w:id="0"/></w:r>
            </w:p>
            <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>List item</w:t></w:r></w:p>
            <w:p><w:r><w:drawing><wp:docPr id="1" name="image1.png" descr="Imported diagram"/><a:blip r:embed="rId1"/></w:drawing></w:r></w:p>
            <w:tbl>
              <w:tr><w:tc><w:p><w:r><w:t>Column A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Column B</w:t></w:r></w:p></w:tc></w:tr>
              <w:tr><w:tc><w:p><w:r><w:t>Value A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Value B</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
          </w:body>
        </w:document>
        """.write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com" TargetMode="External"/>
        </Relationships>
        """.write(to: rels.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
        </w:numbering>
        """.write(to: word.appendingPathComponent("numbering.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:footnote w:id="1"><w:p><w:r><w:t>A footnote.</w:t></w:r></w:p></w:footnote>
        </w:footnotes>
        """.write(to: word.appendingPathComponent("footnotes.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:comment w:id="0" w:author="Editor"><w:p><w:r><w:t>Check this sentence.</w:t></w:r></w:p></w:comment>
        </w:comments>
        """.write(to: word.appendingPathComponent("comments.xml"), atomically: true, encoding: .utf8)

        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: media.appendingPathComponent("image1.png"))
        let output = root.appendingPathComponent("Tracked.docx")
        try PublicationArchiveUtility.zip(directory: package, to: output)
        return output
    }

    private func makeODT(in root: URL) throws -> URL {
        let package = root.appendingPathComponent("odt-package", isDirectory: true)
        let meta = package.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        try "application/vnd.oasis.opendocument.text".write(
            to: package.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8
        )
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
          <office:body><office:text>
            <text:h text:outline-level="1">ODT Title</text:h>
            <text:p>An OpenDocument paragraph.</text:p>
          </office:text></office:body>
        </office:document-content>
        """.write(to: package.appendingPathComponent("content.xml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
          <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
          <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """.write(to: meta.appendingPathComponent("manifest.xml"), atomically: true, encoding: .utf8)

        let output = root.appendingPathComponent("Draft.odt")
        try runZip(arguments: ["-X0", output.path, "mimetype"], in: package)
        try runZip(arguments: ["-Xr9", output.path, "content.xml", "META-INF"], in: package)
        return output
    }

    private func runZip(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func fixtureFingerprint(_ url: URL) throws -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let children = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
            return try children.map { child in
                let data = try Data(contentsOf: url.appendingPathComponent(child))
                return "\(child):\(data.count):\(data.hashValue)"
            }.joined(separator: "|")
        }
        let data = try Data(contentsOf: url)
        return "\(data.count):\(data.hashValue)"
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-DocumentImportTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
