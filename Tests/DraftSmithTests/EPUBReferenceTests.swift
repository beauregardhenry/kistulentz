import Foundation
import XCTest
@testable import DraftSmith

final class EPUBReferenceTests: XCTestCase {
    func testLoadsEPUBAndBuildsLocalProfile() throws {
        let url = try makeFixtureEPUB()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let reference = try EPUBProcessor.load(url: url)

        XCTAssertEqual(reference.title, "The Lantern Road")
        XCTAssertEqual(reference.author, "Beau Henry")
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

    private func makeFixtureEPUB() throws -> URL {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectory = testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("EPUBSource", isDirectory: true)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistuletz-EPUB-Test-\(UUID().uuidString)", isDirectory: true)
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
}
