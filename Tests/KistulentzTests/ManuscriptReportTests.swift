import XCTest
@testable import Kistulentz

/// `WritingProjectStore+ManuscriptReport.swift`'s AI-facing entry points --
/// `applyAIReport`, `applyAIBible`, and `manuscriptAIContext` -- had no direct unit
/// coverage before this file. `applyAIReport` in particular had a real bug: it mutated
/// `manuscriptCache.aiReportMarkdown` in memory *before* saving the cache to disk, and
/// never reverted that mutation if the save itself failed. The next successful local
/// analysis (`applyLocalManuscriptAnalysis`) reads and re-persists that same field, so a
/// failed "Deepen with AI" request would silently get saved anyway on the next edit --
/// despite the user having been told it failed.
final class ManuscriptReportTests: XCTestCase {
    @MainActor
    func testApplyAIReportComposesAndPersistsTheDeepenedReportAndCache() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "AI Report", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        store.applyAIReport(
            AIManuscriptMarkdownResponse(
                summary: "Tightens the throughline in chapter two.",
                markdown: "Cut the aside about the ferry schedule; it stalls the argument."
            ),
            provider: .ollama,
            model: "local-model"
        )

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.manuscriptReportText.contains("AI-Deepened Editorial Notes"))
        XCTAssertTrue(store.manuscriptReportText.contains("Ollama (Local)"))
        XCTAssertTrue(store.manuscriptReportText.contains("local-model"))
        XCTAssertTrue(store.manuscriptReportText.contains("Tightens the throughline in chapter two."))
        XCTAssertTrue(store.manuscriptReportText.contains("Cut the aside about the ferry schedule"))
        XCTAssertEqual(try ManuscriptProjectDisk.loadReport(at: root), store.manuscriptReportText)
        XCTAssertEqual(store.manuscriptCache.aiReportMarkdown, try ManuscriptProjectDisk.loadCache(at: root).aiReportMarkdown)
        XCTAssertTrue(try XCTUnwrap(store.manuscriptCache.aiReportMarkdown).contains("Cut the aside about the ferry schedule"))
    }

    @MainActor
    func testApplyAIReportRevertsTheCacheMutationWhenSavingTheCacheFails() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "AI Report Failure", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        // A first, successful application establishes a real cache file on disk and a
        // known-good in-memory value to check the rollback against.
        store.applyAIReport(
            AIManuscriptMarkdownResponse(summary: "First pass.", markdown: "Keep the opening as-is."),
            provider: .ollama,
            model: "local-model"
        )
        XCTAssertNil(store.errorMessage)
        let previousAIReportMarkdown = try XCTUnwrap(store.manuscriptCache.aiReportMarkdown)

        let cacheURL = root.appendingPathComponent(".kistulentz/manuscript-cache.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: cacheURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: cacheURL.path) }

        store.applyAIReport(
            AIManuscriptMarkdownResponse(summary: "Second pass.", markdown: "Cut the entire second act."),
            provider: .anthropic,
            model: "claude"
        )

        XCTAssertNotNil(store.errorMessage)
        // Before the fix, this stayed at the second (unsaved) markdown even though the
        // cache save that was supposed to persist it had just failed.
        XCTAssertEqual(store.manuscriptCache.aiReportMarkdown, previousAIReportMarkdown)
        XCTAssertFalse(store.manuscriptReportText.contains("Cut the entire second act."))
        XCTAssertEqual(try ManuscriptProjectDisk.loadCache(at: root).aiReportMarkdown, previousAIReportMarkdown)
    }

    @MainActor
    func testApplyAIBibleAddsTheDeepenedNotesToTheBible() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "AI Bible", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        store.applyAIBible(
            AIManuscriptMarkdownResponse(
                summary: "Notes on Mara's motivation.",
                markdown: "Mara's distrust of authority stems from the harbor incident."
            ),
            provider: .openAI,
            model: "gpt"
        )

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.bibleText.contains("AI-Deepened Bible Notes"))
        XCTAssertTrue(store.bibleText.contains("Mara's distrust of authority stems from the harbor incident."))
        XCTAssertEqual(try ManuscriptProjectDisk.loadBible(at: root), store.bibleText)
    }

    @MainActor
    func testManuscriptAIContextIncludesDocumentsReportAndBible() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "AI Context", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nA claim that needs a source.\n")
        store.bibleText = "The project argues for stricter oversight."

        let context = try store.manuscriptAIContext()

        XCTAssertTrue(context.contains("A claim that needs a source."))
        XCTAssertTrue(context.contains("The project argues for stricter oversight."))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ManuscriptReport-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
