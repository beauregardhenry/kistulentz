import Foundation
import XCTest
@testable import Kistulentz

final class WritingProjectBibleTests: XCTestCase {
    @MainActor
    func testBibleUpdatePersistsSnapshotsAndSupportsUndoRedo() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(
            in: parent,
            name: "Bible Transaction",
            kind: .fiction
        )
        let store = WritingProjectStore()
        let undoManager = UndoManager()
        try store.openProject(at: root)
        store.attachUndoManager(undoManager)
        let original = store.bibleText
        let updated = original + "\nThe harbor bell rings at midnight.\n"

        store.applyBibleUpdate(
            updated,
            reason: "Before automatic Bible update",
            summary: "Tracked the harbor bell.",
            forceSnapshot: true
        )

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.bibleText, updated)
        XCTAssertEqual(try ManuscriptProjectDisk.loadBible(at: root), updated)
        XCTAssertEqual(store.lastBibleUpdate?.previousText, original)
        XCTAssertEqual(store.lastBibleUpdate?.updatedText, updated)
        let snapshot = try XCTUnwrap(store.snapshots.first {
            $0.chapterPath == ManuscriptProjectDisk.bibleFileName
        })
        XCTAssertEqual(try WritingProjectDisk.snapshotContent(snapshot, at: root), original)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertEqual(store.bibleText, original)
        XCTAssertEqual(try ManuscriptProjectDisk.loadBible(at: root), original)
        XCTAssertTrue(undoManager.canRedo)
        XCTAssertEqual(store.lastBibleUpdate?.summary, "Restored the previous Bible text with Undo.")

        undoManager.redo()
        XCTAssertEqual(store.bibleText, updated)
        XCTAssertEqual(try ManuscriptProjectDisk.loadBible(at: root), updated)
    }

    @MainActor
    func testFailedBibleWriteRollsBackMemoryAndDoesNotRegisterSuccess() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(
            in: parent,
            name: "Bible Write Failure",
            kind: .nonfiction
        )
        let store = WritingProjectStore()
        let undoManager = UndoManager()
        try store.openProject(at: root)
        store.attachUndoManager(undoManager)
        let original = store.bibleText
        let bibleURL = ManuscriptProjectDisk.bibleURL(at: root)
        try FileManager.default.removeItem(at: bibleURL)
        try FileManager.default.createDirectory(at: bibleURL, withIntermediateDirectories: false)

        store.applyBibleUpdate(
            original + "\nThis update cannot be written.\n",
            reason: "Before failed update",
            summary: "This must not be reported as saved.",
            forceSnapshot: false
        )

        XCTAssertEqual(store.bibleText, original)
        XCTAssertNil(store.lastBibleUpdate)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertNotNil(store.errorMessage)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: bibleURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testClosedAndUnchangedBibleEditsDoNotCreateStateOrUndo() throws {
        let store = WritingProjectStore()
        let undoManager = UndoManager()
        store.attachUndoManager(undoManager)

        store.updateBibleText("Ignored while closed")
        store.applyBibleUpdate(
            "",
            reason: "No change",
            summary: "No change",
            forceSnapshot: true
        )

        XCTAssertEqual(store.bibleText, "")
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertNil(store.lastBibleUpdate)
        XCTAssertFalse(undoManager.canUndo)
    }

    /// `updateBibleText` on an open project is the live-typing entry point that routes through
    /// `ManuscriptEditCoordinator`'s `.bibleEditing` trigger -- distinct from `applyBibleUpdate`,
    /// which every other Bible test in this file uses and which deliberately bypasses the
    /// coordinator. No test exercised `.bibleEditing` at all: not the once-per-session baseline
    /// snapshot, and not the debounced disk save.
    @MainActor
    func testEditingTheBibleWhileOpenSnapshotsOnceThenSavesAfterTheDebounce() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = try WritingProjectDisk.createProject(in: root, name: "BibleLive", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: projectRoot)
        let original = store.bibleText

        store.updateBibleText(original + "\nFirst edit.\n")

        XCTAssertTrue(
            store.snapshots.contains { $0.chapterPath == ManuscriptProjectDisk.bibleFileName },
            "the first edit in a session must snapshot the pre-edit Bible text"
        )
        let snapshotCountAfterFirstEdit = store.snapshots.count

        store.updateBibleText(original + "\nFirst edit.\nSecond edit.\n")

        XCTAssertEqual(
            store.snapshots.count, snapshotCountAfterFirstEdit,
            "a second edit in the same session must not snapshot again"
        )

        try await waitUntil {
            (try? ManuscriptProjectDisk.loadBible(at: projectRoot)) == store.bibleText
        }
        XCTAssertEqual(try ManuscriptProjectDisk.loadBible(at: projectRoot), store.bibleText)
    }

    @MainActor
    func testBibleChangeSummaryUsesAccurateSingularAndPluralLanguage() {
        let store = WritingProjectStore()

        XCTAssertEqual(
            store.bibleChangeSummary(old: "one", new: "one\ntwo"),
            "Added 1 locally tracked Bible line."
        )
        XCTAssertEqual(
            store.bibleChangeSummary(old: "one\ntwo", new: "three\nfour"),
            "Updated the local Bible: 2 added and 2 removed lines."
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Bible-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { throw WaitTimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct WaitTimedOut: Error {}
