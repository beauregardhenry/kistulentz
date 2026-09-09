import Foundation
import XCTest
@testable import Kistulentz

final class ResearchAndRevisionTests: XCTestCase {
    func testPandocCitationIncludesOptionalLocator() {
        let source = sampleSource()
        XCTAssertEqual(CitationFormatter.markdownCitation(for: source), "[@henry2026harbor]")
        XCTAssertEqual(CitationFormatter.markdownCitation(for: source, locator: "p. 31"), "[@henry2026harbor, p. 31]")
    }

    func testEveryBuiltInBibliographyStyleProducesAnEntry() {
        for style in BibliographyStyle.allCases {
            let entry = CitationFormatter.entry(sampleSource(), style: style)
            XCTAssertTrue(entry.contains("Harbor Methods"), "Missing title for \(style)")
            XCTAssertTrue(entry.contains("Henry"), "Missing creator for \(style)")
        }
    }

    func testBibTeXRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.bib")
        try ResearchExchange.exportBibTeX([sampleSource()], to: url)
        let sources = try ResearchExchange.importSources(from: url)
        XCTAssertEqual(sources.first?.citeKey, "henry2026harbor")
        XCTAssertEqual(sources.first?.title, "Harbor Methods")
        XCTAssertEqual(sources.first?.authors.first?.familyName, "Henry")
    }

    func testRISRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.ris")
        try ResearchExchange.exportRIS([sampleSource()], to: url)
        let source = try XCTUnwrap(ResearchExchange.importSources(from: url).first)
        XCTAssertEqual(source.DOI, "10.1234/harbor")
        XCTAssertEqual(source.issuedYear, 2026)
    }

    func testCSLJSONRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json")
        try ResearchExchange.exportCSLJSON([sampleSource()], to: url)
        let source = try XCTUnwrap(ResearchExchange.importSources(from: url).first)
        XCTAssertEqual(source.type, .book)
        XCTAssertEqual(source.ISBN, "9780000000002")
    }

    func testDuplicateDetectionAndSafeMergePreferIdentifiers() {
        let existing = sampleSource()
        var incoming = ResearchSource(title: "Different title", DOI: "https://doi.org/10.1234/HARBOR", abstract: "Added abstract")
        let duplicate = ResearchExchange.duplicate(of: incoming, in: [existing])
        XCTAssertEqual(duplicate?.id, existing.id)
        incoming.id = existing.id
        let merged = ResearchExchange.merged(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.title, existing.title)
        XCTAssertEqual(merged.abstract, "Added abstract")
    }

    func testResearchLibraryDiskWritesVisibleMarkdownKnowledgeBase() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [sampleSource()]), to: root)
        let markdown = try String(contentsOf: root.appendingPathComponent(ResearchLibraryDisk.knowledgeBaseFileName), encoding: .utf8)
        XCTAssertTrue(markdown.contains("[@henry2026harbor] Harbor Methods"))
        XCTAssertEqual(try ResearchLibraryDisk.load(from: root).sources.count, 1)
    }

    func testResearchLibraryDiskDoesNotCommitIndexWhenGeneratedMarkdownCannotBeWritten() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = ResearchSource(citeKey: "persisted", title: "Persisted Source")
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [original]), to: root)
        let knowledgeBase = root.appendingPathComponent(ResearchLibraryDisk.knowledgeBaseFileName)
        try FileManager.default.removeItem(at: knowledgeBase)
        try FileManager.default.createDirectory(at: knowledgeBase, withIntermediateDirectories: false)

        let replacement = ResearchSource(citeKey: "uncommitted", title: "Uncommitted Source")
        XCTAssertThrowsError(
            try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [replacement]), to: root)
        )

        XCTAssertEqual(try ResearchLibraryDisk.load(from: root).sources.map(\.id), [original.id])
    }

    func testManagedAttachmentIsCopiedAndLinkedAttachmentIsNot() throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let original = outside.appendingPathComponent("notes.txt")
        try "local evidence".write(to: original, atomically: true, encoding: .utf8)
        let managed = try ResearchLibraryDisk.addAttachment(from: original, to: UUID(), storage: .managedCopy, at: root)
        let linked = try ResearchLibraryDisk.addAttachment(from: original, to: UUID(), storage: .linkedOriginal, at: root)
        XCTAssertNotNil(managed.storedRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ResearchLibraryDisk.attachmentURL(managed, at: root).path))
        XCTAssertNil(linked.storedRelativePath)
        XCTAssertEqual(ResearchLibraryDisk.attachmentURL(linked, at: root), original.standardizedFileURL)
    }

    func testPlainTextAttachmentExtractsLocally() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("evidence.txt")
        try "The harbor record is readable.".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ResearchTextExtractor.extract(from: url, kind: .text), "The harbor record is readable.")
    }

    @MainActor
    func testResearchStoreDoesNotDeleteSourceOrManagedAttachmentWhenIndexSaveFails() throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        let suiteName = "ResearchStoreFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let original = outside.appendingPathComponent("evidence.txt")
        try "Evidence".write(to: original, atomically: true, encoding: .utf8)
        var source = sampleSource()
        let attachment = try ResearchLibraryDisk.addAttachment(
            from: original,
            to: source.id,
            storage: .managedCopy,
            at: root
        )
        source.attachments = [attachment]
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [source]), to: root)
        let managedURL = ResearchLibraryDisk.attachmentURL(attachment, at: root)

        var persistence = ResearchLibraryPersistence.live
        var deletionWasAttempted = false
        persistence.save = { _, _ in throw ExpectedResearchStoreError.writeFailed }
        persistence.removeManagedAttachment = { _, _ in deletionWasAttempted = true }
        let store = ResearchLibraryStore(persistence: persistence, defaults: defaults)
        try store.open(at: root)

        XCTAssertThrowsError(try store.removeSource(source.id))
        XCTAssertEqual(store.sources.map(\.id), [source.id])
        XCTAssertEqual(store.sources.first?.attachments.map(\.id), [attachment.id])
        let onDisk = try ResearchLibraryDisk.load(from: root)
        XCTAssertEqual(onDisk.sources.map(\.id), [source.id])
        XCTAssertEqual(onDisk.sources.first?.attachments.map(\.id), [attachment.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertFalse(deletionWasAttempted)
    }

    @MainActor
    func testResearchStorePersistsRemovalBeforeDeletingManagedAttachment() throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        let suiteName = "ResearchStoreRemoval.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let original = outside.appendingPathComponent("evidence.txt")
        try "Evidence".write(to: original, atomically: true, encoding: .utf8)
        var source = sampleSource()
        let attachment = try ResearchLibraryDisk.addAttachment(
            from: original,
            to: source.id,
            storage: .managedCopy,
            at: root
        )
        source.attachments = [attachment]
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [source]), to: root)

        var persistence = ResearchLibraryPersistence.live
        let liveRemoval = persistence.removeManagedAttachment
        var deletionObservedPersistedRemoval = false
        persistence.removeManagedAttachment = { attachment, root in
            deletionObservedPersistedRemoval = try ResearchLibraryDisk.load(from: root).sources.isEmpty
            try liveRemoval(attachment, root)
        }
        let store = ResearchLibraryStore(persistence: persistence, defaults: defaults)
        try store.open(at: root)

        try store.removeSource(source.id)

        XCTAssertTrue(deletionObservedPersistedRemoval)
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(try ResearchLibraryDisk.load(from: root).sources.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ResearchLibraryDisk.attachmentURL(attachment, at: root).path
        ))
    }

    @MainActor
    func testResearchStoreRollsBackManagedCopyWhenAttachmentIndexSaveFails() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        let suiteName = "ResearchStoreAttachmentRollback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let original = outside.appendingPathComponent("evidence.txt")
        try "Evidence".write(to: original, atomically: true, encoding: .utf8)
        let source = sampleSource()
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [source]), to: root)

        var persistence = ResearchLibraryPersistence.live
        let liveSave = persistence.save
        var shouldFail = false
        var copiedURL: URL?
        let liveAdd = persistence.addAttachment
        persistence.addAttachment = { url, id, storage, root in
            let attachment = try liveAdd(url, id, storage, root)
            copiedURL = ResearchLibraryDisk.attachmentURL(attachment, at: root)
            return attachment
        }
        persistence.save = { archive, root in
            if shouldFail { throw ExpectedResearchStoreError.writeFailed }
            try liveSave(archive, root)
        }
        let store = ResearchLibraryStore(persistence: persistence, defaults: defaults)
        try store.open(at: root)
        shouldFail = true

        await store.addAttachment(from: original, sourceID: source.id, storage: .managedCopy)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.sources.first?.attachments, [])
        XCTAssertFalse(copiedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? true)
        XCTAssertEqual(try ResearchLibraryDisk.load(from: root).sources.first?.attachments, [])
    }

    @MainActor
    func testCancellingResearchAttachmentIndexingLeavesARecoverableUnindexedAttachment() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        let suiteName = "ResearchStoreAttachmentCancel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let original = outside.appendingPathComponent("evidence.txt")
        try "Evidence".write(to: original, atomically: true, encoding: .utf8)
        let source = sampleSource()
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [source]), to: root)

        var persistence = ResearchLibraryPersistence.live
        persistence.extractText = { _, _ in
            try await Task.sleep(for: .seconds(5))
            return "Never committed"
        }
        let store = ResearchLibraryStore(persistence: persistence, defaults: defaults)
        try store.open(at: root)

        let task = Task {
            await store.addAttachment(from: original, sourceID: source.id, storage: .managedCopy)
        }
        var attempts = 0
        while store.indexingAttachmentIDs.isEmpty, attempts < 100 {
            try await Task.sleep(for: .milliseconds(5))
            attempts += 1
        }
        XCTAssertEqual(store.indexingAttachmentIDs.count, 1)

        task.cancel()
        await task.value

        XCTAssertTrue(store.indexingAttachmentIDs.isEmpty)
        XCTAssertNil(store.errorMessage)
        let attachment = try XCTUnwrap(store.sources.first?.attachments.first)
        XCTAssertEqual(attachment.extractionStatus, .notStarted)
        XCTAssertNil(attachment.extractedTextRelativePath)
        let onDiskAttachment = try XCTUnwrap(
            ResearchLibraryDisk.load(from: root).sources.first?.attachments.first
        )
        XCTAssertEqual(onDiskAttachment.id, attachment.id)
        XCTAssertEqual(onDiskAttachment.extractionStatus, .notStarted)
        XCTAssertNil(onDiskAttachment.extractedTextRelativePath)
    }

    @MainActor
    func testResearchStoreRemembersLibraryAndPersistsAddAndUpdate() throws {
        let root = temporaryDirectory()
        let suiteName = "ResearchStoreRemember.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        try ResearchLibraryDisk.save(ResearchLibraryArchive(), to: root)
        let store = ResearchLibraryStore(defaults: defaults)
        try store.open(at: root)

        var draft = ResearchSource(title: "   ")
        draft.creators = [ResearchCreator(givenName: "Ada", familyName: "Lovelace")]
        draft.issuedYear = 1843
        let id = try store.addSource(draft)

        var added = try XCTUnwrap(store.sources.first { $0.id == id })
        XCTAssertEqual(added.title, "Untitled Source")
        XCTAssertFalse(added.citeKey.isEmpty)
        added.title = "Notes on the Analytical Engine"
        added.citeKey = "Lovelace 1843 Notes!"
        try store.updateSource(added)
        XCTAssertEqual(store.sources.first?.citeKey, "Lovelace1843Notes")

        let reopened = ResearchLibraryStore(defaults: defaults)
        XCTAssertEqual(reopened.rootURL, root.standardizedFileURL)
        XCTAssertEqual(reopened.sources.first?.title, "Notes on the Analytical Engine")
        XCTAssertEqual(try ResearchLibraryDisk.load(from: root).sources, reopened.sources)
    }

    @MainActor
    func testResearchStoreRejectsMissingLocationAndDuplicateCitationKeysWithoutMutation() throws {
        let suiteName = "ResearchStoreValidation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ResearchLibraryStore(defaults: defaults)

        XCTAssertThrowsError(try store.addSource(sampleSource()))

        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [sampleSource()]), to: root)
        try store.open(at: root)
        let before = store.sources
        var duplicate = ResearchSource(citeKey: "HENRY2026HARBOR", title: "Duplicate")
        duplicate.id = UUID()
        XCTAssertThrowsError(try store.addSource(duplicate))
        XCTAssertEqual(store.sources, before)
        XCTAssertEqual(try ResearchLibraryDisk.load(from: root).sources, before)
    }

    @MainActor
    func testResearchStoreSearchesMetadataAndLocallyIndexedAttachmentText() throws {
        let root = temporaryDirectory()
        let suiteName = "ResearchStoreSearch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let attachment = ResearchAttachment(
            displayName: "notes.txt", kind: .text, storage: .linkedOriginal,
            originalPath: "/tmp/notes.txt", extractedTextRelativePath: "Indexes/notes.txt",
            extractionStatus: .extracted
        )
        var harbor = sampleSource()
        harbor.attachments = [attachment]
        let astronomy = ResearchSource(
            citeKey: "herschel1846", title: "Astronomical Observations",
            creators: [ResearchCreator(givenName: "Caroline", familyName: "Herschel")]
        )
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [harbor, astronomy]), to: root)
        var persistence = ResearchLibraryPersistence.live
        persistence.loadExtractedText = { attachment, _ in
            attachment.id == harbor.attachments[0].id ? "A concealed lighthouse observation." : nil
        }
        let store = ResearchLibraryStore(persistence: persistence, defaults: defaults)
        try store.open(at: root)

        XCTAssertEqual(store.filteredSources.map(\.id), [harbor.id, astronomy.id])
        store.searchText = "herschel"
        XCTAssertEqual(store.filteredSources.map(\.id), [astronomy.id])
        store.searchText = "lighthouse"
        XCTAssertEqual(store.filteredSources.map(\.id), [harbor.id])
        store.searchText = "not present"
        XCTAssertTrue(store.filteredSources.isEmpty)
    }

    @MainActor
    func testResearchStoreImportsMergesAndExportsEverySupportedFormat() throws {
        let root = temporaryDirectory()
        let exchange = temporaryDirectory()
        let suiteName = "ResearchStoreExchange.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exchange)
        }
        let existing = sampleSource()
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [existing]), to: root)
        let incomingURL = exchange.appendingPathComponent("incoming.json")
        var duplicate = existing
        duplicate.abstract = "Merged abstract"
        let newSource = ResearchSource(citeKey: existing.citeKey, title: "A New Source")
        try ResearchExchange.exportCSLJSON([duplicate, newSource], to: incomingURL)
        let store = ResearchLibraryStore(defaults: defaults)
        try store.open(at: root)

        XCTAssertEqual(try store.importSources(from: incomingURL), 1)
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(store.sources.first { $0.id == existing.id }?.abstract, "Merged abstract")
        XCTAssertEqual(Set(store.sources.map(\.citeKey)).count, 2)

        for (format, name) in [("bibtex", "export.bib"), ("ris", "export.ris"), ("json", "export.json")] {
            let url = exchange.appendingPathComponent(name)
            try store.export(store.sources, format: format, to: url)
            XCTAssertEqual(try ResearchExchange.importSources(from: url).count, 2, format)
        }
    }

    @MainActor
    func testResearchAttachmentHappyPathIndexesPersistsAndRemovesAllManagedFiles() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        let suiteName = "ResearchStoreAttachmentSuccess.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let source = sampleSource()
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [source]), to: root)
        let original = outside.appendingPathComponent("evidence.txt")
        try "Locally indexed evidence.".write(to: original, atomically: true, encoding: .utf8)
        let store = ResearchLibraryStore(defaults: defaults)
        try store.open(at: root)

        await store.addAttachment(from: original, sourceID: source.id, storage: .managedCopy)

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.indexingAttachmentIDs.isEmpty)
        let attachment = try XCTUnwrap(store.sources.first?.attachments.first)
        XCTAssertEqual(attachment.extractionStatus, .extracted)
        XCTAssertNotNil(attachment.extractedTextRelativePath)
        let managedURL = try XCTUnwrap(store.attachmentURL(attachment))
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertEqual(ResearchLibraryDisk.loadExtractedText(for: attachment, at: root), "Locally indexed evidence.")
        let persisted = try XCTUnwrap(ResearchLibraryDisk.load(from: root).sources.first?.attachments.first)
        XCTAssertEqual(persisted.id, attachment.id)
        XCTAssertEqual(persisted.extractionStatus, attachment.extractionStatus)
        XCTAssertEqual(persisted.extractedTextRelativePath, attachment.extractedTextRelativePath)
        XCTAssertEqual(persisted.extractionMessage, attachment.extractionMessage)

        try store.removeAttachment(attachment.id, sourceID: source.id)
        XCTAssertTrue(store.sources.first?.attachments.isEmpty == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertNil(ResearchLibraryDisk.loadExtractedText(for: attachment, at: root))
    }

    @MainActor
    func testResearchAttachmentExtractionFailureRemainsVisibleAndRecoverable() async throws {
        let root = temporaryDirectory()
        let outside = temporaryDirectory()
        let suiteName = "ResearchStoreAttachmentExtractionFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let source = sampleSource()
        try ResearchLibraryDisk.save(ResearchLibraryArchive(sources: [source]), to: root)
        let original = outside.appendingPathComponent("opaque.bin")
        try Data([0, 1, 2]).write(to: original)
        var persistence = ResearchLibraryPersistence.live
        persistence.extractText = { _, _ in throw ExpectedResearchStoreError.extractionFailed }
        let store = ResearchLibraryStore(persistence: persistence, defaults: defaults)
        try store.open(at: root)

        await store.addAttachment(from: original, sourceID: source.id, storage: .linkedOriginal)

        XCTAssertNil(store.errorMessage)
        let attachment = try XCTUnwrap(store.sources.first?.attachments.first)
        XCTAssertEqual(attachment.extractionStatus, .noReadableText)
        XCTAssertFalse(attachment.extractionMessage.isEmpty)
        XCTAssertNil(attachment.extractedTextRelativePath)
        let persisted = try XCTUnwrap(ResearchLibraryDisk.load(from: root).sources.first?.attachments.first)
        XCTAssertEqual(persisted.id, attachment.id)
        XCTAssertEqual(persisted.extractionStatus, attachment.extractionStatus)
        XCTAssertEqual(persisted.extractionMessage, attachment.extractionMessage)
        XCTAssertEqual(store.attachmentURL(attachment), original.standardizedFileURL)
    }

    func testDOIMetadataLookupMapsCrossrefRecord() async throws {
        let service = ResearchMetadataLookupService { request in
            XCTAssertTrue(request.url?.absoluteString.contains("api.crossref.org/works/10.1234%2Fharbor") == true)
            let body: [String: Any] = ["message": [
                "title": ["Harbor Methods"], "author": [["given": "Beau", "family": "Henry"]],
                "published-print": ["date-parts": [[2026, 8]]], "publisher": "Example Press",
                "type": "book", "DOI": "10.1234/harbor", "ISBN": ["9780000000002"]
            ]]
            let data = try JSONSerialization.data(withJSONObject: body)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let source = try await service.lookupDOI("https://doi.org/10.1234/HARBOR")
        XCTAssertEqual(source.title, "Harbor Methods")
        XCTAssertEqual(source.authors.first?.displayName, "Beau Henry")
        XCTAssertEqual(source.issuedYear, 2026)
    }

    func testISBNMetadataLookupMapsOpenLibraryRecord() async throws {
        let service = ResearchMetadataLookupService { request in
            XCTAssertTrue(request.url?.absoluteString.contains("openlibrary.org/search.json") == true)
            let body: [String: Any] = ["docs": [[
                "key": "/works/OL1W", "title": "Harbor Methods", "author_name": ["Beau Henry"],
                "first_publish_year": 2026, "publisher": ["Example Press"], "isbn": ["9780000000002"]
            ]]]
            let data = try JSONSerialization.data(withJSONObject: body)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let source = try await service.lookupISBN("978-0-00000-000-2")
        XCTAssertEqual(source.URLString, "https://openlibrary.org/works/OL1W")
        XCTAssertEqual(source.primaryCreatorName, "Beau Henry")
    }

    func testProjectResearchNotesAreVisibleButNotAChapter() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Research", kind: .nonfiction)
        let manifest = try WritingProjectDisk.loadManifest(at: root)
        let chapters = try WritingProjectDisk.loadChapters(at: root, manifest: manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ProjectResearchDisk.notesURL(at: root).path))
        XCTAssertFalse(chapters.contains { $0.relativePath == ProjectResearchDisk.notesFileName })
    }

    func testProjectBibliographyPersistsStyleQuotationsAndClaimLinks() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try WritingProjectDisk.prepareExistingProject(at: root, name: "Research", kind: .nonfiction)
        let sourceID = UUID()
        let archive = ProjectBibliographyArchive(
            sourceIDs: [sourceID],
            style: .apa,
            quotations: [ProjectResearchQuotation(sourceID: sourceID, text: "Evidence", locator: "p. 9")],
            claimLinks: [ProjectClaimSourceLink(sourceID: sourceID, chapterPath: "Draft.md", claimExcerpt: "A claim")]
        )
        try ProjectResearchDisk.save(archive, at: root)
        let reopened = try ProjectResearchDisk.load(at: root)
        XCTAssertEqual(reopened.sourceIDs, archive.sourceIDs)
        XCTAssertEqual(reopened.style, .apa)
        XCTAssertEqual(reopened.quotations.first?.text, "Evidence")
        XCTAssertEqual(reopened.claimLinks.first?.claimExcerpt, "A claim")
    }

    func testLocalRevisionScanClassifiesMissingCitationKeyAsConfirmedProblem() {
        let document = ManuscriptDocument(relativePath: "Draft.md", title: "Draft", text: "The record supports this claim [@missing, p. 4].")
        let findings = SystemicRevisionAnalyzer.analyze(
            projectName: "Draft", kind: .nonfiction, documents: [document], manuscript: nil,
            bibliography: ProjectBibliographyArchive(), sources: [], targetGrade: 8
        )
        let finding = findings.first { $0.title.contains("Citation key") }
        XCTAssertEqual(finding?.classification, .confirmedProblem)
        XCTAssertEqual(finding?.revisionPass, .argumentAndEvidence)
    }

    func testRevisionScanReconciliationPreservesUserStatus() throws {
        let document = ManuscriptDocument(relativePath: "Draft.md", title: "Draft", text: "We utilize several tools.")
        let local = SystemicRevisionAnalyzer.analyze(
            projectName: "Draft", kind: .nonfiction, documents: [document], manuscript: nil,
            bibliography: ProjectBibliographyArchive(), sources: [], targetGrade: 8
        )
        var prior = SystemicRevisionArchive(findings: local)
        prior.findings[0].status = .dismissed
        let refreshed = SystemicRevisionAnalyzer.reconcile(local, with: prior)
        XCTAssertEqual(refreshed.findings.first(where: { $0.signature == local[0].signature })?.status, .dismissed)
    }

    func testChangePlannerFlagsStaleDuplicateAndOverlappingPassages() {
        let stale = RevisionChange(chapterPath: "Draft.md", originalText: "missing", replacementText: "new", explanation: "")
        let duplicate = RevisionChange(chapterPath: "Draft.md", originalText: "repeat", replacementText: "once", explanation: "")
        let overlapA = RevisionChange(chapterPath: "Other.md", originalText: "abc", replacementText: "ABC", explanation: "")
        let overlapB = RevisionChange(chapterPath: "Other.md", originalText: "bcd", replacementText: "BCD", explanation: "")
        let set = RevisionChangeSet(title: "Test", summary: "", changes: [stale, duplicate, overlapA, overlapB])
        let checked = RevisionChangePlanner.validate(set, documents: ["Draft.md": "repeat and repeat", "Other.md": "abcdef"])
        XCTAssertNotNil(checked.changes[0].conflict)
        XCTAssertNotNil(checked.changes[1].conflict)
        XCTAssertNil(checked.changes[2].conflict)
        XCTAssertNotNil(checked.changes[3].conflict)
    }

    func testPlannerAppliesMultipleFilesFromExactText() throws {
        let set = RevisionChangeSet(title: "Test", summary: "", changes: [
            RevisionChange(chapterPath: "One.md", originalText: "utilize", replacementText: "use", explanation: ""),
            RevisionChange(chapterPath: "Two.md", originalText: "commence", replacementText: "start", explanation: "")
        ])
        let result = try RevisionChangePlanner.applying(set, to: ["One.md": "We utilize tools.", "Two.md": "We commence now."])
        XCTAssertEqual(result["One.md"], "We use tools.")
        XCTAssertEqual(result["Two.md"], "We start now.")
    }

    @MainActor
    func testStoreAppliesMultiFileRevisionWithSnapshotsAndOneUndo() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Revision", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nWe utilize ropes.\n")
        store.saveNow()
        store.createChapter(named: "Chapter 2")
        store.updateText("# Chapter 2\n\nWe commence walking.\n")
        store.saveNow()
        let undo = UndoManager()
        store.attachUndoManager(undo)
        let set = RevisionChangeSet(title: "Test", summary: "", changes: [
            RevisionChange(chapterPath: "Chapter 1.md", originalText: "utilize", replacementText: "use", explanation: ""),
            RevisionChange(chapterPath: "Chapter 2.md", originalText: "commence", replacementText: "start", explanation: "")
        ])

        store.applyRevisionChangeSet(set)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("use ropes"))
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 2.md", at: root).contains("start walking"))
        XCTAssertTrue(store.snapshots.contains { $0.chapterPath == "Chapter 1.md" })
        XCTAssertTrue(store.snapshots.contains { $0.chapterPath == "Chapter 2.md" })
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("utilize ropes"))
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 2.md", at: root).contains("commence walking"))
    }

    func testSystemicAIRequestIsExplicitAndDoesNotClaimToApplyChanges() {
        let request = AIRequestPreview(
            purpose: .systemicRevision(kind: .fiction, passes: [.continuity, .pacing]),
            provider: .ollama, model: "local", primaryLabel: "Manuscript", primaryText: "<manuscript>Text</manuscript>",
            styleGuide: nil, includesStyleGuide: false, referenceContext: nil, includesReferenceContext: false,
            sourceRange: nil, sourceText: nil
        )
        XCTAssertTrue(request.instructions.contains("do not claim it has been applied"))
        XCTAssertTrue(request.instructions.lowercased().contains("continuity"))
        XCTAssertEqual(request.purpose.actionTitle, "Deepen Revision Findings")
    }

    private func sampleSource() -> ResearchSource {
        ResearchSource(
            citeKey: "henry2026harbor",
            type: .book,
            title: "Harbor Methods",
            creators: [ResearchCreator(givenName: "Beau", familyName: "Henry")],
            issuedYear: 2026,
            publisher: "Example Press",
            DOI: "10.1234/harbor",
            ISBN: "9780000000002"
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Research-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum ExpectedResearchStoreError: Error {
    case writeFailed
    case extractionFailed
}
