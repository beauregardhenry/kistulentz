import Foundation
import XCTest
@testable import Kistulentz

/// Covers `ResearchLibraryStore` itself -- the in-memory guards, citation-key assignment, and
/// dedup/merge orchestration that sit in front of the well-tested `ResearchLibraryDisk` and
/// `ResearchExchange` layers. Every call passes `remember: false` so these tests never touch the
/// developer's real `UserDefaults.standard` "Kistulentz.researchLibraryLocation" entry.
@MainActor
final class ResearchLibraryStoreTests: XCTestCase {
    func testAddSourceDefaultsBlankTitleAndAssignsAUniqueCitationKeyOnCollision() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }

        let firstID = try store.addSource(ResearchSource(
            title: "  ",
            creators: [ResearchCreator(familyName: "Henry")],
            issuedYear: 2026
        ))
        let first = try XCTUnwrap(store.sources.first { $0.id == firstID })
        XCTAssertEqual(first.title, "Untitled Source", "a blank title falls back to a default rather than saving empty")
        XCTAssertFalse(first.citeKey.isEmpty)

        let secondID = try store.addSource(ResearchSource(
            title: "Harbor Methods",
            creators: [ResearchCreator(familyName: "Henry")],
            issuedYear: 2026
        ))
        let thirdID = try store.addSource(ResearchSource(
            title: "Harbor Methods",
            creators: [ResearchCreator(familyName: "Henry")],
            issuedYear: 2026
        ))
        let second = try XCTUnwrap(store.sources.first { $0.id == secondID })
        let third = try XCTUnwrap(store.sources.first { $0.id == thirdID })
        XCTAssertEqual(second.citeKey, "henry2026harbor")
        XCTAssertEqual(third.citeKey, "henry2026harbor2", "a colliding auto-generated key must be disambiguated")
    }

    func testAddSourceRejectsAnExplicitlyInvalidCitationKey() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }

        XCTAssertThrowsError(try store.addSource(ResearchSource(citeKey: "bad key!", title: "Alpha"))) { error in
            XCTAssertEqual(error as? ResearchLibraryError, .invalidCitationKey)
        }
        XCTAssertTrue(store.sources.isEmpty, "a rejected source must not be added")
    }

    func testUpdateSourceRejectsACitationKeyAlreadyUsedByAnotherSource() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }

        _ = try store.addSource(ResearchSource(citeKey: "alpha1", title: "Alpha"))
        let secondID = try store.addSource(ResearchSource(citeKey: "beta1", title: "Beta"))

        var second = try XCTUnwrap(store.sources.first { $0.id == secondID })
        second.citeKey = "alpha1"
        XCTAssertThrowsError(try store.updateSource(second)) { error in
            guard case .duplicateCitationKey("alpha1") = error as? ResearchLibraryError else {
                return XCTFail("expected duplicateCitationKey(\"alpha1\"), got \(error)")
            }
        }
        XCTAssertEqual(store.sources.first { $0.id == secondID }?.citeKey, "beta1", "a rejected update must not be applied")
    }

    func testUpdateSourceOnAnUnknownIDThrowsMissingSource() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }

        XCTAssertThrowsError(try store.updateSource(ResearchSource(citeKey: "ghost1", title: "Ghost"))) { error in
            XCTAssertEqual(error as? ResearchLibraryError, .missingSource)
        }
    }

    func testRemoveSourceDeletesItsManagedAttachmentsFromDisk() async throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sourceID = try store.addSource(ResearchSource(citeKey: "src1", title: "Source"))

        let outside = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let original = outside.appendingPathComponent("evidence.txt")
        try "The harbor record is readable.".write(to: original, atomically: true, encoding: .utf8)
        await store.addAttachment(from: original, sourceID: sourceID, storage: .managedCopy)

        let attachment = try XCTUnwrap(store.sources.first { $0.id == sourceID }?.attachments.first)
        let managedURL = try XCTUnwrap(store.attachmentURL(attachment))
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))

        try store.removeSource(sourceID)

        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path), "removing a source must also remove its managed attachment files")
    }

    func testRemoveSourceOnAnUnknownIDThrowsMissingSource() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }

        XCTAssertThrowsError(try store.removeSource(UUID())) { error in
            XCTAssertEqual(error as? ResearchLibraryError, .missingSource)
        }
    }

    func testAddAttachmentIndexesLocalTextAndRemoveAttachmentDeletesTheManagedCopy() async throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sourceID = try store.addSource(ResearchSource(citeKey: "src1", title: "Source"))

        let outside = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let original = outside.appendingPathComponent("evidence.txt")
        try "The harbor record is readable.".write(to: original, atomically: true, encoding: .utf8)

        await store.addAttachment(from: original, sourceID: sourceID, storage: .managedCopy)

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.indexingAttachmentIDs.isEmpty, "indexing bookkeeping must clear once extraction finishes")
        let attachment = try XCTUnwrap(store.sources.first { $0.id == sourceID }?.attachments.first)
        XCTAssertEqual(attachment.extractionStatus, .extracted)
        let managedURL = try XCTUnwrap(store.attachmentURL(attachment))
        XCTAssertEqual(try String(contentsOf: managedURL, encoding: .utf8), "The harbor record is readable.")

        try store.removeAttachment(attachment.id, sourceID: sourceID)

        XCTAssertTrue(store.sources.first { $0.id == sourceID }?.attachments.isEmpty ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
    }

    func testRemoveAttachmentOnAnUnknownAttachmentThrowsMissingSource() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sourceID = try store.addSource(ResearchSource(citeKey: "src1", title: "Source"))

        XCTAssertThrowsError(try store.removeAttachment(UUID(), sourceID: sourceID)) { error in
            XCTAssertEqual(error as? ResearchLibraryError, .missingSource)
        }
    }

    func testFilteredSourcesSortsByCreatorThenTitleAndFiltersBySearchText() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }

        _ = try store.addSource(ResearchSource(citeKey: "b1", title: "Second Book", creators: [ResearchCreator(familyName: "Zed")]))
        _ = try store.addSource(ResearchSource(citeKey: "a1", title: "First Book", creators: [ResearchCreator(familyName: "Adams")]))

        XCTAssertEqual(store.filteredSources.map(\.title), ["First Book", "Second Book"])

        store.searchText = "second"
        XCTAssertEqual(store.filteredSources.map(\.title), ["Second Book"])

        store.searchText = "nomatch"
        XCTAssertTrue(store.filteredSources.isEmpty)
    }

    func testLookupDOIAssignsACitationKeyThatAvoidsExistingOnes() async throws {
        let lookup = ResearchMetadataLookupService { request in
            let body: [String: Any] = ["message": [
                "title": ["Harbor Methods"], "author": [["given": "Beau", "family": "Henry"]],
                "published-print": ["date-parts": [[2026, 8]]], "type": "book"
            ]]
            let data = try JSONSerialization.data(withJSONObject: body)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let (store, parent) = try openedStore(metadataLookup: lookup)
        defer { try? FileManager.default.removeItem(at: parent) }
        _ = try store.addSource(ResearchSource(
            citeKey: "henry2026harbor", title: "Harbor Methods",
            creators: [ResearchCreator(familyName: "Henry")], issuedYear: 2026
        ))

        let looked = try await store.lookupDOI("10.1234/harbor")

        XCTAssertEqual(looked.citeKey, "henry2026harbor2", "the looked-up source's key must avoid the existing one")
        XCTAssertFalse(store.isLookingUpMetadata)
    }

    func testExportRoutesFormatStringsToTheMatchingExporter() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sourceID = try store.addSource(ResearchSource(citeKey: "src1", type: .book, title: "Exportable", DOI: "10.1234/exportable"))
        let source = try XCTUnwrap(store.sources.first { $0.id == sourceID })
        let outputDir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let risURL = outputDir.appendingPathComponent("out.ris")
        try store.export([source], format: "RIS", to: risURL)
        XCTAssertEqual(try ResearchExchange.importSources(from: risURL).first?.DOI, "10.1234/exportable")

        let bibURL = outputDir.appendingPathComponent("out.bib")
        try store.export([source], format: "bibtex", to: bibURL)
        XCTAssertEqual(try ResearchExchange.importSources(from: bibURL).first?.type, .book)

        let jsonURL = outputDir.appendingPathComponent("out.json")
        try store.export([source], format: "anything-unrecognized", to: jsonURL)
        XCTAssertEqual(try ResearchExchange.importSources(from: jsonURL).first?.DOI, "10.1234/exportable", "an unrecognized format falls back to CSL-JSON")
    }

    func testImportSourcesMergesMatchingDOIsAndAddsGenuinelyNewSources() throws {
        let (store, parent) = try openedStore()
        defer { try? FileManager.default.removeItem(at: parent) }
        let existingID = try store.addSource(ResearchSource(
            citeKey: "henry2026harbor", title: "Harbor Methods",
            creators: [ResearchCreator(familyName: "Henry")], issuedYear: 2026,
            DOI: "10.1234/harbor", abstract: ""
        ))

        let importDir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: importDir) }
        let importURL = importDir.appendingPathComponent("import.json")
        try ResearchExchange.exportCSLJSON([
            ResearchSource(
                title: "Harbor Methods", creators: [ResearchCreator(familyName: "Henry")],
                issuedYear: 2026, DOI: "10.1234/HARBOR", abstract: "Reprint abstract"
            ),
            ResearchSource(title: "A Different Work", creators: [ResearchCreator(familyName: "Ng")], issuedYear: 2019)
        ], to: importURL)

        let added = try store.importSources(from: importURL)

        XCTAssertEqual(added, 1, "only the genuinely new source counts toward the added total")
        XCTAssertEqual(store.sources.count, 2)
        let merged = try XCTUnwrap(store.sources.first { $0.id == existingID })
        XCTAssertEqual(merged.citeKey, "henry2026harbor", "merging must not disturb the existing citation key")
        XCTAssertEqual(merged.abstract, "Reprint abstract", "an empty field on the existing source is filled in from the import")
        let newSource = try XCTUnwrap(store.sources.first { $0.title == "A Different Work" })
        XCTAssertFalse(newSource.citeKey.isEmpty, "a brand-new import without a citation key still gets one assigned")
    }

    // MARK: - Helpers

    private func openedStore(
        metadataLookup: ResearchMetadataLookupService = ResearchMetadataLookupService()
    ) throws -> (store: ResearchLibraryStore, parent: URL) {
        let parent = temporaryDirectory()
        let store = ResearchLibraryStore(metadataLookup: metadataLookup)
        try store.open(at: parent.appendingPathComponent("Library", isDirectory: true), remember: false)
        return (store, parent)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ResearchLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
