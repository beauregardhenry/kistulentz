import AppKit
import PDFKit
import XCTest
@testable import Kistulentz

final class PublicationTests: XCTestCase {
    func testSubmissionPackageContainsPrivateReadinessReportsAndChecksums() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let fixture = try String(contentsOf: publicationFixture("Fiction-Sample.md"), encoding: .utf8)
        let secretSentence = "Mara reached the abandoned signal house before the storm closed the road."
        try fixture.write(
            to: root.appendingPathComponent("Opening.md"), atomically: true, encoding: .utf8
        )
        try makePNG(at: root.appendingPathComponent("cover.png"))
        let coverInfo = try XCTUnwrap(PublicationImageInspector.rasterInfo(at: root.appendingPathComponent("cover.png")))
        XCTAssertEqual(coverInfo.pixelWidth, 24)
        XCTAssertEqual(coverInfo.pixelHeight, 24)
        let node = OutlineNode(title: "Opening", kind: .chapter, relativePath: "Opening.md")
        var archive = PublicationArchive(projectName: "Readiness Book", projectKind: .fiction)
        archive.metadata.authors = ["Beau Henry"]
        archive.metadata.coverImageRelativePath = "cover.png"
        archive.metadata.coverAltText = "A blue square used as a test cover"
        var profile = try XCTUnwrap(archive.profiles.first(where: { $0.kind == .fictionBook }))
        profile.includeBibliography = false
        let plan = PublicationPlanBuilder.build(
            projectName: "Readiness Book",
            root: root,
            outline: [node],
            archive: archive,
            bibliography: ProjectBibliographyArchive(),
            librarySources: [],
            profile: profile,
            format: .epub,
            destinations: [.genericEPUB, .appleBooks]
        )

        let result = try PublicationExporter.export(
            plan: plan,
            root: root,
            outputDirectory: output,
            allowingWarnings: true
        )

        let package = try XCTUnwrap(result.packageURL)
        let names = try FileManager.default.contentsOfDirectory(atPath: package.path)
        XCTAssertTrue(names.contains(result.outputURL.lastPathComponent))
        XCTAssertTrue(names.contains("Submission Readiness Report.md"))
        XCTAssertTrue(names.contains("Submission Readiness Report.pdf"))
        XCTAssertTrue(names.contains("package-manifest.json"))
        XCTAssertTrue(names.contains("SHA256SUMS.txt"))
        XCTAssertTrue(names.contains { $0.hasSuffix("-ebook-cover.png") })

        let report = try String(contentsOf: try XCTUnwrap(result.reportMarkdownURL), encoding: .utf8)
        XCTAssertTrue(report.contains("Submission Readiness Report"))
        XCTAssertTrue(report.contains("External Validation Required"))
        XCTAssertTrue(report.contains("intentionally contains no manuscript prose or excerpts"))
        XCTAssertFalse(report.contains(secretSentence))
        let reportPDF = try Data(contentsOf: try XCTUnwrap(result.reportPDFURL))
        XCTAssertEqual(String(data: reportPDF.prefix(4), encoding: .ascii), "%PDF")
        let reportDocument = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(result.reportPDFURL)))
        XCTAssertTrue(reportDocument.string?.contains("Kistulentz Submission Readiness Report") == true)
        XCTAssertFalse(reportDocument.string?.contains(secretSentence) == true)

        let manifest = try String(contentsOf: package.appendingPathComponent("package-manifest.json"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("\"manuscriptTextIncluded\" : false"))
        XCTAssertFalse(manifest.contains(secretSentence))
        let checksums = try String(contentsOf: package.appendingPathComponent("SHA256SUMS.txt"), encoding: .utf8)
        XCTAssertTrue(checksums.contains(result.outputURL.lastPathComponent))
        XCTAssertTrue(checksums.contains("Submission Readiness Report.pdf"))
    }

    func testPrintBleedCreatesMediaTrimAndBleedBoxesWithoutChangingTrimSize() throws {
        let root = temporaryDirectory()
        let output = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        try String(contentsOf: publicationFixture("Nonfiction-Sample.md"), encoding: .utf8).write(
            to: root.appendingPathComponent("Chapter.md"), atomically: true, encoding: .utf8
        )
        let node = OutlineNode(title: "Chapter One", kind: .chapter, relativePath: "Chapter.md")
        var archive = PublicationArchive(projectName: "Bleed Book", projectKind: .nonfiction)
        archive.metadata.authors = ["Beau Henry"]
        var profile = try XCTUnwrap(archive.profiles.first(where: { $0.kind == .nonfictionBook }))
        profile.includeCover = false
        profile.includeBibliography = false
        profile.printBleed = .outside
        let plan = PublicationPlanBuilder.build(
            projectName: "Bleed Book",
            root: root,
            outline: [node],
            archive: archive,
            bibliography: ProjectBibliographyArchive(),
            librarySources: [],
            profile: profile,
            format: .printPDF,
            destinations: [.kdpPrint, .ingramSparkPrint]
        )

        let result = try PublicationExporter.export(plan: plan, root: root, outputDirectory: output, allowingWarnings: true)
        let document = try XCTUnwrap(PDFDocument(url: result.outputURL))
        let firstPage = try XCTUnwrap(document.page(at: 0))
        let media = firstPage.bounds(for: .mediaBox)
        let trim = firstPage.bounds(for: .trimBox)
        let bleed = firstPage.bounds(for: .bleedBox)
        XCTAssertEqual(trim.width, profile.layout.pageSize.widthPoints, accuracy: 0.5)
        XCTAssertEqual(trim.height, profile.layout.pageSize.heightPoints, accuracy: 0.5)
        XCTAssertEqual(media.width, trim.width + 9, accuracy: 0.5)
        XCTAssertEqual(media.height, trim.height + 18, accuracy: 0.5)
        XCTAssertEqual(bleed.width, media.width, accuracy: 0.5)
        XCTAssertEqual(bleed.height, media.height, accuracy: 0.5)
        XCTAssertTrue(result.preflight.findings.contains { $0.id == "print-page-count" })
    }

    func testOlderPublicationMetadataDefaultsNewDestinationAndBleedFields() throws {
        let archive = PublicationArchive(projectName: "Legacy", projectKind: .fiction)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(archive)) as? [String: Any])
        object.removeValue(forKey: "selectedDestinations")
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        for index in profiles.indices { profiles[index].removeValue(forKey: "printBleed") }
        object["profiles"] = profiles
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(PublicationArchive.self, from: legacyData)

        XCTAssertEqual(decoded.selectedDestinations, [.genericEPUB])
        XCTAssertTrue(decoded.profiles.allSatisfy { $0.printBleed == .none })
    }

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

    private func publicationFixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Publication")
            .appendingPathComponent(name)
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
