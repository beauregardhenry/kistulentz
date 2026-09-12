import Foundation
import XCTest
@testable import Kistulentz

/// Covers `ProjectResearchStore`'s own logic -- dedup, trimming, and cascading deletes -- on top
/// of the already-tested `ProjectResearchDisk` persistence layer (see `ResearchAndRevisionTests`).
@MainActor
final class ProjectResearchStoreTests: XCTestCase {
    func testAddResearchSourceIsIdempotentAndPersists() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sourceID = UUID()

        store.researchStore.addResearchSource(sourceID)
        store.researchStore.addResearchSource(sourceID)

        XCTAssertEqual(store.researchStore.projectBibliography.sourceIDs, [sourceID], "adding the same source twice must not duplicate it")

        let reopened = WritingProjectStore()
        try reopened.openProject(at: root)
        XCTAssertEqual(reopened.researchStore.projectBibliography.sourceIDs, [sourceID])
    }

    func testRemoveResearchSourceCascadesToItsQuotationsAndClaimLinks() throws {
        let (store, _, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let keptID = UUID()
        let removedID = UUID()
        store.researchStore.addResearchSource(keptID)
        store.researchStore.addResearchSource(removedID)
        store.researchStore.addQuotation(sourceID: keptID, text: "Kept quote", locator: "p.1", note: "")
        store.researchStore.addQuotation(sourceID: removedID, text: "Removed quote", locator: "p.2", note: "")
        store.researchStore.addClaimLink(sourceID: removedID, chapterPath: "Chapter 1.md", excerpt: "A claim", locator: "", note: "")

        store.researchStore.removeResearchSource(removedID)

        XCTAssertEqual(store.researchStore.projectBibliography.sourceIDs, [keptID])
        XCTAssertEqual(store.researchStore.projectBibliography.quotations.map(\.text), ["Kept quote"])
        XCTAssertTrue(store.researchStore.projectBibliography.claimLinks.isEmpty)
    }

    func testAddQuotationAndClaimLinkTrimWhitespaceAndIgnoreBlankText() throws {
        let (store, _, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sourceID = UUID()
        store.researchStore.addResearchSource(sourceID)

        store.researchStore.addQuotation(sourceID: sourceID, text: "   ", locator: "", note: "")
        XCTAssertTrue(store.researchStore.projectBibliography.quotations.isEmpty, "a blank quotation must not be recorded")

        store.researchStore.addQuotation(sourceID: sourceID, text: "  Evidence  ", locator: " p.9 ", note: " good ")
        let quotation = try XCTUnwrap(store.researchStore.projectBibliography.quotations.first)
        XCTAssertEqual(quotation.text, "Evidence")
        XCTAssertEqual(quotation.locator, "p.9")
        XCTAssertEqual(quotation.note, "good")

        store.researchStore.removeQuotation(quotation.id)
        XCTAssertTrue(store.researchStore.projectBibliography.quotations.isEmpty)

        store.researchStore.addClaimLink(sourceID: sourceID, chapterPath: "Chapter 1.md", excerpt: "   ", locator: "", note: "")
        XCTAssertTrue(store.researchStore.projectBibliography.claimLinks.isEmpty, "a blank claim excerpt must not be recorded")

        store.researchStore.addClaimLink(sourceID: sourceID, chapterPath: "Chapter 1.md", excerpt: "  A real claim  ", locator: "", note: "")
        let claim = try XCTUnwrap(store.researchStore.projectBibliography.claimLinks.first)
        XCTAssertEqual(claim.claimExcerpt, "A real claim")

        store.researchStore.removeClaimLink(claim.id)
        XCTAssertTrue(store.researchStore.projectBibliography.claimLinks.isEmpty)
    }

    func testSetBibliographyStylePersistsToDisk() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }

        store.researchStore.setBibliographyStyle(.apa)

        XCTAssertEqual(try ProjectResearchDisk.load(at: root).style, .apa)
    }

    func testUpdateResearchNotesSkipsWritingWhenTheValueIsUnchanged() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let notesURL = ProjectResearchDisk.notesURL(at: root)
        let before = try Data(contentsOf: notesURL)

        store.researchStore.updateResearchNotes(store.researchStore.researchNotesText)
        XCTAssertEqual(try Data(contentsOf: notesURL), before, "writing back the identical value must not touch the file")

        store.researchStore.updateResearchNotes("New notes.")
        XCTAssertEqual(store.researchStore.researchNotesText, "New notes.")
        XCTAssertEqual(try String(contentsOf: notesURL, encoding: .utf8), "New notes.")
    }

    func testProjectSourcesFiltersTheLibraryByBibliographyMembership() throws {
        let (store, _, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let libraryRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        let library = ResearchLibraryStore()
        try library.open(at: libraryRoot, remember: false)
        let keptID = try library.addSource(ResearchSource(citeKey: "kept1", title: "Kept"))
        _ = try library.addSource(ResearchSource(citeKey: "other1", title: "Other"))

        store.researchStore.addResearchSource(keptID)

        XCTAssertEqual(store.researchStore.projectSources(in: library).map(\.title), ["Kept"])
    }

    func testResetClearsBibliographyAndNotes() throws {
        let (store, _, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        store.researchStore.addResearchSource(UUID())
        store.researchStore.updateResearchNotes("Some notes.")

        store.researchStore.reset()

        XCTAssertTrue(store.researchStore.projectBibliography.sourceIDs.isEmpty)
        XCTAssertEqual(store.researchStore.researchNotesText, "")
    }

    // MARK: - Helpers

    private func openedProject() throws -> (store: WritingProjectStore, root: URL, parent: URL) {
        let parent = temporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Research", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        return (store, root, parent)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ProjectResearchStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
