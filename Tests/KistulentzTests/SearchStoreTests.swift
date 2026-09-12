import Foundation
import XCTest
@testable import Kistulentz

/// Covers `SearchStore`'s own logic: the debounce/cancellation pipeline and the `reset()`
/// asymmetry it deliberately preserved from the pre-decomposition `WritingProjectStore`. The
/// underlying `WritingProjectDisk.search` is already covered by `WritingProjectTests`.
@MainActor
final class SearchStoreTests: XCTestCase {
    func testResetClearsResultsButLeavesIsSearchingUntouched() {
        let store = SearchStore()
        store.searchResults = [
            ProjectSearchResult(chapterPath: "A.md", chapterTitle: "A", line: 1, preview: "x", range: NSRange(location: 0, length: 1))
        ]
        store.isSearching = true

        store.reset()

        XCTAssertTrue(store.searchResults.isEmpty)
        XCTAssertTrue(store.isSearching, "reset() intentionally leaves isSearching alone, matching the pre-decomposition store's behavior")
    }

    func testBlankQueryClearsResultsWithoutStartingASearch() throws {
        let (store, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        store.searchStore.searchResults = [
            ProjectSearchResult(chapterPath: "A.md", chapterTitle: "A", line: 1, preview: "x", range: NSRange(location: 0, length: 1))
        ]

        store.searchStore.search("   ")

        XCTAssertTrue(store.searchStore.searchResults.isEmpty)
        XCTAssertFalse(store.searchStore.isSearching)
    }

    func testSearchWithNoOpenProjectClearsResultsWithoutCrashing() {
        let store = SearchStore()
        store.search("harbor")
        XCTAssertTrue(store.searchResults.isEmpty)
        XCTAssertFalse(store.isSearching)
    }

    func testSearchPopulatesResultsForTheOpenProjectAfterTheDebounce() async throws {
        let (store, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        store.updateText("# Chapter 1\n\nThe quiet harbor waited.\n")
        store.saveNow()

        store.searchStore.search("harbor")
        XCTAssertTrue(store.searchStore.isSearching, "isSearching should flip on immediately, before the debounce elapses")

        while store.searchStore.isSearching { await Task.yield() }

        XCTAssertEqual(store.searchStore.searchResults.first?.chapterPath, "Chapter 1.md")
    }

    func testStartingANewSearchCancelsThePreviousDebouncedTask() async throws {
        let (store, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        store.updateText("# Chapter 1\n\nThe quiet harbor waited.\n")
        store.saveNow()

        store.searchStore.search("harbor")
        XCTAssertTrue(store.searchStore.isSearching)

        // A blank query resolves synchronously and should cancel the in-flight "harbor" search.
        store.searchStore.search("")
        XCTAssertFalse(store.searchStore.isSearching)
        XCTAssertTrue(store.searchStore.searchResults.isEmpty)

        // Long enough for the cancelled task's debounce (180ms) and disk read to have completed
        // if cancellation had failed to take effect.
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(store.searchStore.isSearching)
        XCTAssertTrue(store.searchStore.searchResults.isEmpty, "a cancelled search must not resurrect stale results afterward")
    }

    // MARK: - Helpers

    private func openedProject() throws -> (store: WritingProjectStore, parent: URL) {
        let parent = temporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Search", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        return (store, parent)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-SearchStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
