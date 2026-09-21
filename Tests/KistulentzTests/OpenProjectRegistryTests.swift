import XCTest
@testable import Kistulentz

@MainActor
final class OpenProjectRegistryTests: XCTestCase {
    func testFlushAllSavesPendingChapterBibleAndOutlineEditsForARegisteredStore() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Flush Test", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        store.updateText("# Chapter 1\n\nEdited just before quit.\n")
        store.updateBibleText("Updated bible notes.")
        store.outlineNodes = [OutlineNode(title: "New scene", kind: .scene)]

        OpenProjectRegistry.shared.flushAll()

        XCTAssertFalse(store.hasUnsavedChapterChanges)
        let savedChapter = try String(
            contentsOf: root.appendingPathComponent("Chapter 1.md"),
            encoding: .utf8
        )
        XCTAssertEqual(savedChapter, "# Chapter 1\n\nEdited just before quit.\n")
        let savedBible = try ManuscriptProjectDisk.loadBible(at: root)
        XCTAssertEqual(savedBible, "Updated bible notes.")
        let savedOutline = try ProjectOutlineDisk.load(at: root)
        XCTAssertEqual(savedOutline.nodes.map(\.title), ["New scene"])
    }

    func testFlushAllIsANoOpForAStoreWithoutAnOpenProject() {
        let store = WritingProjectStore()

        OpenProjectRegistry.shared.flushAll()

        XCTAssertFalse(store.isOpen)
        XCTAssertFalse(store.hasUnsavedChapterChanges)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-OpenProjectRegistry-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
