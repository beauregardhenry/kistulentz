import Foundation
import XCTest
@testable import Kistulentz

final class EPUBReferenceTests: XCTestCase {
    func testLoadsEPUBAndBuildsLocalProfile() throws {
        let url = try makeFixtureEPUB()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let reference = try EPUBProcessor.load(url: url)

        XCTAssertEqual(reference.title, "The Lantern Road")
        XCTAssertEqual(reference.author, "Beau Henry")
        XCTAssertEqual(reference.subjects, ["Fantasy"])
        XCTAssertEqual(reference.chapters.count, 2)
        XCTAssertGreaterThan(reference.profile.wordCount, 50)
        XCTAssertFalse(reference.profile.voice.isEmpty)
        XCTAssertFalse(reference.profile.tempo.isEmpty)
        XCTAssertTrue(reference.chapters.map(\.text).joined().contains("Elara"))
    }

    func testSelectedExcerptsStayWithinLimitAndFavorRelevantText() throws {
        let url = try makeFixtureEPUB()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reference = try EPUBProcessor.load(url: url)

        let excerpts = reference.selectedExcerpts(
            relevantTo: "Elara raised the lantern beside the river.",
            maxCharacters: 2_000
        )

        XCTAssertLessThanOrEqual(excerpts.count, 2_000)
        XCTAssertTrue(excerpts.contains("Elara"))
        XCTAssertTrue(excerpts.contains("lantern"))
    }

    func testLocalComparisonWorksWithoutAnAIProvider() {
        let chapters = [
            ReferenceChapter(
                id: 0,
                title: "Reference",
                text: "Mara waited. She watched the road. \"Come inside,\" Mara said. She closed the gate."
            )
        ]
        let reference = EPUBReference(
            fileName: "reference.epub",
            title: "Reference",
            author: nil,
            chapters: chapters,
            profile: ReferenceProfileBuilder.build(chapters: chapters)
        )

        let result = ReferenceComparison.analyze(
            draft: "I had been waiting beside the road for a very long time before I finally decided to cross it alone.",
            against: reference
        )

        XCTAssertGreaterThanOrEqual(result.score, 0)
        XCTAssertLessThanOrEqual(result.score, 100)
        XCTAssertEqual(result.notes.count, 4)
        XCTAssertTrue(result.notes.contains { $0.title == "Narrative voice" })
    }

    func testEPUBRejectsArchivedSymbolicLinksBeforeExtraction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EPUB-Symlink-Test-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("package", isDirectory: true)
        let meta = package.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = root.appendingPathComponent("outside.xml")
        try "<container/>".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: meta.appendingPathComponent("container.xml"),
            withDestinationURL: outside
        )
        let output = root.appendingPathComponent("unsafe.epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = package
        process.arguments = ["-X", "-q", "-y", "-r", output.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        XCTAssertThrowsError(try EPUBProcessor.load(url: output)) { error in
            guard case EPUBError.unsafeArchive = error else {
                return XCTFail("Expected an unsafe archive error, got \(error)")
            }
        }
    }

    func testEPUBRejectsContainerAndManifestPathsThatEscapeTheArchive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EPUB-Path-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        let meta = package.appendingPathComponent("META-INF", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="../outside.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: meta.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)
        let epub = root.appendingPathComponent("escaping-container.epub")
        try zip(package, to: epub)

        XCTAssertThrowsError(try EPUBProcessor.load(url: epub)) { error in
            guard case EPUBError.unsafeArchive = error else {
                return XCTFail("Expected unsafeArchive, got \(error).")
            }
        }
    }

    func testEPUBRejectsRemoteAndMissingSpineContentWithoutLeakingTemporaryFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EPUB-Manifest-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        let meta = package.appendingPathComponent("META-INF", isDirectory: true)
        let book = package.appendingPathComponent("Book", isDirectory: true)
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="Book/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.write(to: meta.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Unsafe</dc:title></metadata>
          <manifest><item id="remote" href="https://example.com/chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
          <spine><itemref idref="remote"/></spine>
        </package>
        """.write(to: book.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
        let epub = root.appendingPathComponent("remote-spine.epub")
        try zip(package, to: epub)

        let temporaryBefore = try Set(FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("Kistulentz-EPUB-") })
        XCTAssertThrowsError(try EPUBProcessor.load(url: epub)) { error in
            guard case EPUBError.unsafeArchive = error else {
                return XCTFail("Expected unsafeArchive, got \(error).")
            }
        }
        let temporaryAfter = try Set(FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("Kistulentz-EPUB-") })
        XCTAssertEqual(temporaryAfter, temporaryBefore)
    }

    private func makeFixtureEPUB() throws -> URL {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("EPUBSource", isDirectory: true)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-EPUB-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let outputURL = temporaryDirectory.appendingPathComponent("fixture.epub")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = fixtureDirectory
        process.arguments = ["-X", "-q", "-r", outputURL.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return outputURL
    }

    private func zip(_ directory: URL, to output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-X", "-q", "-r", output.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
