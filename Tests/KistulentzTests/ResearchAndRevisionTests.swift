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

    @MainActor
    func testAppliedRevisionCanBeUndoneAndRedoneRepeatedly() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Redo", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nWe utilize ropes.\n")
        store.saveNow()
        let undo = UndoManager()
        store.attachUndoManager(undo)
        let set = RevisionChangeSet(title: "Test", summary: "", changes: [
            RevisionChange(chapterPath: "Chapter 1.md", originalText: "utilize", replacementText: "use", explanation: "")
        ])

        store.applyRevisionChangeSet(set)
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("use ropes"))

        undo.undo()
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("utilize ropes"))
        XCTAssertTrue(undo.canRedo, "undoing an applied revision must register a redo action")

        undo.redo()
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("use ropes"))
        XCTAssertTrue(undo.canUndo, "redoing must in turn register another undo")

        undo.undo()
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("utilize ropes"))
    }

    @MainActor
    func testApplyRevisionChangeSetFailsAndTouchesNothingWhenPassageIsAmbiguous() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Conflict", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nWe utilize ropes and utilize knots.\n")
        store.saveNow()
        let before = try WritingProjectDisk.readChapter("Chapter 1.md", at: root)
        let snapshotCountBefore = store.snapshots.count
        let set = RevisionChangeSet(title: "Test", summary: "", changes: [
            RevisionChange(chapterPath: "Chapter 1.md", originalText: "utilize", replacementText: "use", explanation: "")
        ])

        let result = store.applyRevisionChangeSet(set)

        XCTAssertFalse(result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try WritingProjectDisk.readChapter("Chapter 1.md", at: root), before, "an ambiguous passage must leave the chapter untouched")
        XCTAssertEqual(store.snapshots.count, snapshotCountBefore, "no new snapshot should be created for a change that was never applied")
    }

    @MainActor
    func testApplyRevisionChangeSetFailsWhenTheSetContainsNoConcreteChanges() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "NoOp", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nWe utilize ropes.\n")
        store.saveNow()
        let before = try WritingProjectDisk.readChapter("Chapter 1.md", at: root)
        let snapshotCountBefore = store.snapshots.count
        let set = RevisionChangeSet(title: "Test", summary: "", changes: [
            RevisionChange(chapterPath: "Chapter 1.md", originalText: "utilize", replacementText: "utilize", explanation: "")
        ])

        let result = store.applyRevisionChangeSet(set)

        XCTAssertFalse(result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try WritingProjectDisk.readChapter("Chapter 1.md", at: root), before)
        XCTAssertEqual(store.snapshots.count, snapshotCountBefore)
    }

    @MainActor
    func testApplyRevisionChangeSetRollsBackAnEarlierWriteWhenALaterFileCannotBeWritten() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Rollback", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nWe utilize ropes.\n")
        store.saveNow()
        store.createChapter(named: "Chapter 2")
        store.updateText("# Chapter 2\n\nWe commence walking.\n")
        store.saveNow()

        // Make the second file's write fail after the first one has already landed, so the
        // catch block in `applyRevisionChangeSet` has to restore what it already wrote.
        let chapterTwoURL = root.appendingPathComponent("Chapter 2.md")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: chapterTwoURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: chapterTwoURL.path) }

        let set = RevisionChangeSet(title: "Test", summary: "", changes: [
            RevisionChange(chapterPath: "Chapter 1.md", originalText: "utilize", replacementText: "use", explanation: ""),
            RevisionChange(chapterPath: "Chapter 2.md", originalText: "commence", replacementText: "start", explanation: "")
        ])

        let result = store.applyRevisionChangeSet(set)

        XCTAssertFalse(result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(
            try WritingProjectDisk.readChapter("Chapter 1.md", at: root).contains("utilize ropes"),
            "the file that was already written must be rolled back once the second file's write fails"
        )
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 2.md", at: root).contains("commence walking"))
    }

    @MainActor
    func testAddAIRevisionFindingsMergesBySignaturePreservingIdentityAndStatus() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "AIFindings", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)

        let existing = SystemicRevisionFinding(
            signature: "sig-a", revisionPass: .continuity, classification: .probableProblem,
            status: .resolved, title: "Alpha", detail: "old detail", createdAt: Date(timeIntervalSince1970: 0)
        )
        store.revisionArchive.findings = [existing]

        let refreshedAlpha = SystemicRevisionFinding(
            signature: "sig-a", revisionPass: .continuity, classification: .probableProblem,
            status: .open, title: "Alpha", detail: "new detail from AI"
        )
        let brandNewBeta = SystemicRevisionFinding(
            signature: "sig-b", revisionPass: .argumentAndEvidence, classification: .confirmedProblem,
            title: "Beta", detail: "brand new"
        )

        store.addAIRevisionFindings([refreshedAlpha, brandNewBeta], summary: "AI pass complete")

        XCTAssertEqual(store.revisionArchive.findings.count, 2)
        let alpha = try XCTUnwrap(store.revisionArchive.findings.first { $0.signature == "sig-a" })
        XCTAssertEqual(alpha.id, existing.id, "a repeated signature keeps its original identity")
        XCTAssertEqual(alpha.status, .resolved, "a repeated signature keeps the user's prior status rather than resetting it")
        XCTAssertEqual(alpha.createdAt, existing.createdAt)
        XCTAssertEqual(alpha.detail, "new detail from AI", "the finding's content still refreshes from the new AI pass")
        XCTAssertEqual(store.revisionAISummary, "AI pass complete")
        XCTAssertEqual(
            store.revisionArchive.findings.map(\.signature), ["sig-b", "sig-a"],
            "confirmedProblem must sort ahead of probableProblem"
        )
    }

    @MainActor
    func testRevisionAIContextIncludesNotesAndOnlyProjectBibliographySources() throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Context", kind: .nonfiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Draft\n\nBody text with a claim.\n")
        store.saveNow()

        let included = sampleSource()
        let excluded = ResearchSource(citeKey: "other2020other", title: "Unrelated Work")
        store.researchStore.addResearchSource(included.id)
        store.researchStore.updateResearchNotes("Key background note.")

        let context = try store.revisionAIContext(sources: [included, excluded])

        XCTAssertTrue(context.contains("Key background note."))
        XCTAssertTrue(context.contains("Draft.md"))
        XCTAssertTrue(context.contains("Body text with a claim."))
        XCTAssertTrue(context.contains("Harbor Methods"))
        XCTAssertFalse(context.contains("Unrelated Work"), "a source not attached to this project must not leak into the bibliography context")
    }

    @MainActor
    func testProjectPolishInputsFailsWhenTheDraftCannotBeSaved() throws {
        // `projectPolishInputs()` calls `saveNow()` itself before checking `isDirty` -- a normal
        // pending edit gets flushed right there, so the only way `isDirty` survives that call
        // (and the guard actually fires) is a save that fails outright.
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Polish", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        store.updateText("# Chapter 1\n\nOriginal draft.\n")

        let chapterURL = root.appendingPathComponent("Chapter 1.md")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: chapterURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: chapterURL.path) }

        XCTAssertThrowsError(try store.projectPolishInputs()) { error in
            XCTAssertEqual(error as? SystemicRevisionError, .filesChanged)
        }
        XCTAssertTrue(store.isDirty, "a save that failed to land must leave the draft marked dirty")

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: chapterURL.path)
        store.saveNow()
        let (documents, decisions) = try store.projectPolishInputs()
        XCTAssertEqual(documents.count, 1)
        XCTAssertTrue(documents.first?.text.contains("Original draft.") ?? false)
        XCTAssertTrue(decisions.isEmpty)
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
