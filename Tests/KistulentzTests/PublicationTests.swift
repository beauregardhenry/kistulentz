import AppKit
import XCTest
@testable import Kistulentz

final class PublicationTests: XCTestCase {
    func testPublicationArchiveKeepsBuiltInsAndProtectsEditedMatter() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Book", kind: .fiction)
        try PublicationDisk.prepare(at: root, projectName: "Book", projectKind: .fiction)
        var archive = try PublicationDisk.load(at: root)

        XCTAssertEqual(Set(archive.profiles.map(\.kind)), Set([.fictionBook, .nonfictionBook, .agentSubmission, .accessibleEPUB]))
        XCTAssertEqual(archive.metadata.title, "Book")
        let copyrightIndex = try XCTUnwrap(archive.matter.firstIndex { $0.kind == .copyright })
        archive.matter[copyrightIndex].markdown = "# Copyright\n\nMy carefully edited notice.\n"
        let regenerated = PublicationMatterGenerator.regenerating(archive.matter, metadata: archive.metadata)

        XCTAssertEqual(regenerated[copyrightIndex].markdown, "# Copyright\n\nMy carefully edited notice.\n")
        archive.matter = regenerated
        try PublicationDisk.save(archive, at: root)
        XCTAssertEqual(try PublicationDisk.load(at: root), archive)
    }

    func testExportPlanRespectsOutlineAndPreflightBlocksMissingAssetsAndCitations() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Included\n\nEvidence [@known].\n\n![Map](missing.png)\n".write(to: root.appendingPathComponent("Included.md"), atomically: true, encoding: .utf8)
        try "# Excluded\n\nSecret.\n".write(to: root.appendingPathComponent("Excluded.md"), atomically: true, encoding: .utf8)
        let included = OutlineNode(title: "Included", kind: .chapter, relativePath: "Included.md")
        var excluded = OutlineNode(title: "Excluded", kind: .chapter, relativePath: "Excluded.md")
        excluded.metadata.includedInExport = false
        var archive = PublicationArchive(projectName: "Book", projectKind: .nonfiction)
        archive.metadata.authors = ["Author"]
        var profile = archive.profiles[0]
        profile.includeCover = false
        let plan = PublicationPlanBuilder.build(
            projectName: "Book",
            root: root,
            outline: [included, excluded],
            archive: archive,
            bibliography: ProjectBibliographyArchive(),
            librarySources: [],
            profile: profile,
            format: .epub
        )

        XCTAssertEqual(plan.manuscriptItems.map(\.title), ["Included"])
        XCTAssertEqual(plan.items.first(where: { $0.title == "Excluded" })?.exclusionReason, "Excluded in Project Organization.")
        let report = PublicationPreflight.run(plan: plan, root: root)
        XCTAssertTrue(report.errors.contains { $0.title.contains("Unresolved citation") })
        XCTAssertTrue(report.errors.contains { $0.title == "Image is missing" })
    }

    func testAllPublicationFormatsContainExpectedStructureImagesAndNotes() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let imageURL = root.appendingPathComponent("harbor.png")
        try makePNG(at: imageURL)
        let manuscript = """
        # The Harbor

        The light held steady [@doe2024, p. 7].

        ![A square harbor map](harbor.png "Harbor map")

        ## Next Tide

        The boats returned.
        """
        try manuscript.write(to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8)
        let node = OutlineNode(title: "The Harbor", kind: .chapter, relativePath: "Chapter.md")
        let creator = ResearchCreator(givenName: "Jane", familyName: "Doe")
        let source = ResearchSource(citeKey: "doe2024", title: "Harbor Evidence", creators: [creator], issuedYear: 2024, publisher: "Tide Press")
        var bibliography = ProjectBibliographyArchive()
        bibliography.sourceIDs = [source.id]
        var archive = PublicationArchive(projectName: "Harbor Book", projectKind: .fiction)
        archive.metadata.authors = ["Beau Henry"]
        archive.metadata.description = "A local publication test."
        var profile = archive.profiles.first(where: { $0.kind == .fictionBook })!
        profile.includeCover = false
        profile.includeBibliography = true
        profile.citationMode = .footnotes

        for format in PublicationExportFormat.allCases {
            let plan = PublicationPlanBuilder.build(
                projectName: "Harbor Book",
                root: root,
                outline: [node],
                archive: archive,
                bibliography: bibliography,
                librarySources: [source],
                profile: profile,
                format: format
            )
            let report = PublicationPreflight.run(plan: plan, root: root)
            XCTAssertTrue(report.canExport, "\(format.title): \(report.errors)")
            let result = try PublicationExporter.export(plan: plan, root: root, outputDirectory: output, allowingWarnings: true)
            XCTAssertGreaterThan(result.byteCount, 100)
            XCTAssertEqual(result.sha256.count, 64)

            switch format {
            case .epub:
                let entries = try unzipList(result.outputURL)
                XCTAssertTrue(entries.contains("mimetype"))
                XCTAssertTrue(entries.contains("EPUB/package.opf"))
                XCTAssertTrue(entries.contains("EPUB/nav.xhtml"))
                XCTAssertTrue(entries.contains { $0.contains("EPUB/images/harbor-") })
                let package = try unzipText(result.outputURL, path: "EPUB/package.opf")
                XCTAssertTrue(package.contains("version=\"3.0\""))
                XCTAssertTrue(package.contains("schema:accessMode"))
                XCTAssertFalse(package.contains("dcterms:conformsTo"))
                let chapter = try unzipText(result.outputURL, path: "EPUB/text/section-005.xhtml")
                XCTAssertTrue(chapter.contains("epub:type=\"footnote\""))
                XCTAssertTrue(chapter.contains("A square harbor map"))
                for path in entries where path.hasSuffix(".xml") || path.hasSuffix(".opf") || path.hasSuffix(".xhtml") {
                    assertValidXML(try unzipText(result.outputURL, path: path), path: path)
                }
            case .docx:
                let entries = try unzipList(result.outputURL)
                XCTAssertTrue(entries.contains("word/document.xml"))
                XCTAssertTrue(entries.contains("word/footnotes.xml"))
                XCTAssertTrue(entries.contains { $0.hasPrefix("word/media/harbor-") })
                let document = try unzipText(result.outputURL, path: "word/document.xml")
                XCTAssertTrue(document.contains("w:footnoteReference"))
                XCTAssertTrue(document.contains("The Harbor"))
                for path in entries where path.hasSuffix(".xml") || path.hasSuffix(".rels") {
                    assertValidXML(try unzipText(result.outputURL, path: path), path: path)
                }
            case .printPDF, .readerPDF:
                let data = try Data(contentsOf: result.outputURL)
                XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
            }
        }
    }

    @MainActor
    func testStorePersistsPublicationHistoryWithoutChangingMarkdown() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "History Book", kind: .nonfiction)
        let original = try WritingProjectDisk.readChapter("Draft.md", at: root)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        var archive = store.publicationArchive
        archive.metadata.authors = ["Beau Henry"]
        store.updatePublicationArchive(archive)
        let profile = try XCTUnwrap(archive.profiles.first)
        let result = PublicationExportResult(
            outputURL: parent.appendingPathComponent("History Book.epub"),
            sha256: String(repeating: "a", count: 64),
            byteCount: 125,
            preflight: PublicationPreflightReport(findings: [])
        )
        let plan = try store.publicationPlan(sources: [], profileID: profile.id, format: .epub)
        store.recordPublicationExport(result, plan: plan)
        store.closeProject()

        let reopened = WritingProjectStore()
        try reopened.openProject(at: root)
        XCTAssertEqual(reopened.publicationArchive.history.first?.sha256, String(repeating: "a", count: 64))
        XCTAssertEqual(try WritingProjectDisk.readChapter("Draft.md", at: root), original)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kistulentz-Publication-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePNG(at url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func unzipList(_ archive: URL) throws -> [String] {
        try run("/usr/bin/unzip", arguments: ["-Z1", archive.path]).components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    private func unzipText(_ archive: URL, path: String) throws -> String {
        let literalPattern = path.replacingOccurrences(of: "[", with: "[[]")
        return try run("/usr/bin/unzip", arguments: ["-p", archive.path, literalPattern])
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func assertValidXML(_ text: String, path: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let data = text.data(using: .utf8) else {
            XCTFail("\(path) is not UTF-8", file: file, line: line)
            return
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        XCTAssertTrue(parser.parse(), "\(path): \(parser.parserError?.localizedDescription ?? "invalid XML")", file: file, line: line)
    }
}
