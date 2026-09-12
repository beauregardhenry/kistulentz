import Foundation
import XCTest
@testable import Kistulentz

/// Covers `BetaReadersStore`'s own logic: trimming/blank guards on add, built-in-reader
/// protection on update/remove, and the `documents(for:selection:)` scope switch.
@MainActor
final class BetaReadersStoreTests: XCTestCase {
    func testAddCustomBetaReaderTrimsAndRejectsABlankNameOrFocus() throws {
        let store = BetaReadersStore()

        store.addCustomBetaReader(name: "  ", focus: "Pacing", audience: .general)
        XCTAssertTrue(store.customBetaReaders.isEmpty, "a blank name must not create a reader")

        store.addCustomBetaReader(name: "Jordan", focus: "   ", audience: .general)
        XCTAssertTrue(store.customBetaReaders.isEmpty, "a blank focus must not create a reader")

        store.addCustomBetaReader(name: "  Jordan  ", focus: "  Pacing and tension  ", audience: .fiction)
        let reader = try XCTUnwrap(store.customBetaReaders.first)
        XCTAssertEqual(reader.name, "Jordan")
        XCTAssertEqual(reader.focus, "Pacing and tension")
        XCTAssertEqual(reader.isBuiltIn, false)
    }

    func testUpdateAndRemoveRefuseToTouchABuiltInReader() {
        let store = BetaReadersStore()
        let builtIn = BetaReaderProfile(name: "General Reader", focus: "Overall engagement", audience: .general, isBuiltIn: true)

        var renamed = builtIn
        renamed.name = "Renamed"
        store.updateCustomBetaReader(renamed)
        XCTAssertTrue(store.customBetaReaders.isEmpty)

        store.removeCustomBetaReader(builtIn)
        XCTAssertTrue(store.customBetaReaders.isEmpty)
    }

    func testUpdateAndRemoveWorkOnAGenuineCustomReader() throws {
        let store = BetaReadersStore()
        store.addCustomBetaReader(name: "Jordan", focus: "Pacing", audience: .general)
        var reader = try XCTUnwrap(store.customBetaReaders.first)

        reader.focus = "Pacing and dialogue"
        store.updateCustomBetaReader(reader)
        XCTAssertEqual(store.customBetaReaders.first?.focus, "Pacing and dialogue")

        store.removeCustomBetaReader(reader)
        XCTAssertTrue(store.customBetaReaders.isEmpty)
    }

    func testDocumentsForSelectionRequiresNonBlankText() throws {
        let store = BetaReadersStore()

        XCTAssertThrowsError(try store.documents(for: .selection, selection: "   ")) { error in
            guard let aiError = error as? WritingAIError, case .emptySelection = aiError else {
                return XCTFail("expected emptySelection, got \(error)")
            }
        }
        XCTAssertThrowsError(try store.documents(for: .selection, selection: nil)) { error in
            guard let aiError = error as? WritingAIError, case .emptySelection = aiError else {
                return XCTFail("expected emptySelection, got \(error)")
            }
        }

        let documents = try store.documents(for: .selection, selection: "A passage.")
        XCTAssertEqual(documents.first?.text, "A passage.")
        XCTAssertEqual(documents.first?.title, "Selection")
    }

    func testDocumentsForChapterAndManuscriptDelegateToTheOpenProject() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Beta", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nDraft text.\n")
        store.saveNow()

        let chapterDocuments = try store.betaReadersStore.documents(for: .chapter, selection: nil)
        XCTAssertEqual(chapterDocuments.first?.relativePath, "Chapter 1.md")
        XCTAssertTrue(chapterDocuments.first?.text.contains("Draft text.") ?? false)

        let manuscriptDocuments = try store.betaReadersStore.documents(for: .manuscript, selection: nil)
        XCTAssertEqual(manuscriptDocuments.count, 1)
    }

    func testCustomBetaReadersPersistAcrossReopeningTheProject() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "BetaPersist", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        store.betaReadersStore.addCustomBetaReader(name: "Jordan", focus: "Pacing", audience: .general)

        let reopened = WritingProjectStore()
        try reopened.openProject(at: root)
        XCTAssertEqual(reopened.betaReadersStore.customBetaReaders.map(\.name), ["Jordan"])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-BetaReadersStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
