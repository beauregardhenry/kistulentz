import CoreText
import XCTest
@testable import Kistulentz

final class ProjectSubstoreTests: XCTestCase {
    @MainActor
    func testResearchStoreCommitsBibliographyOnlyAfterPersistenceSucceeds() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceID = UUID()
        var persisted: ProjectBibliographyArchive?
        var errors: [Error] = []
        let store = ProjectResearchStore(
            projectRoot: { root },
            reportError: { errors.append($0) },
            saveBibliography: { archive, savedRoot in
                XCTAssertEqual(savedRoot, root)
                persisted = archive
            }
        )

        store.addResearchSource(sourceID)

        XCTAssertEqual(store.projectBibliography.sourceIDs, [sourceID])
        XCTAssertEqual(persisted, store.projectBibliography)
        XCTAssertTrue(errors.isEmpty)
    }

    @MainActor
    func testResearchStoreRollsBackBibliographyAndNotesWhenPersistenceFails() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceID = UUID()
        var errors: [Error] = []
        let store = ProjectResearchStore(
            projectRoot: { root },
            reportError: { errors.append($0) },
            saveBibliography: { _, _ in throw ExpectedPersistenceError.failed },
            saveNotes: { _, _ in throw ExpectedPersistenceError.failed }
        )
        store.replaceContents(
            bibliography: ProjectBibliographyArchive(),
            notesText: "Original notes"
        )

        store.addResearchSource(sourceID)
        store.updateResearchNotes("Unsaved notes")

        XCTAssertTrue(store.projectBibliography.sourceIDs.isEmpty)
        XCTAssertEqual(store.researchNotesText, "Original notes")
        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.allSatisfy {
            $0.localizedDescription == ExpectedPersistenceError.failed.localizedDescription
        })
    }

    @MainActor
    func testResearchStorePersistsEveryBibliographyEditAndCascadesSourceRemoval() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceID = UUID()
        var persisted: [ProjectBibliographyArchive] = []
        var savedNotes: [String] = []
        let store = ProjectResearchStore(
            projectRoot: { root },
            reportError: { XCTFail("Unexpected error: \($0)") },
            saveBibliography: { archive, _ in persisted.append(archive) },
            saveNotes: { value, _ in savedNotes.append(value) }
        )

        store.addResearchSource(sourceID)
        store.addResearchSource(sourceID)
        store.setBibliographyStyle(.chicagoNotes)
        store.addQuotation(sourceID: sourceID, text: "   ", locator: "p. 1", note: "Ignored")
        store.addQuotation(sourceID: sourceID, text: "  Evidence  ", locator: " p. 2 ", note: " note ")
        let firstQuotation = try XCTUnwrap(store.projectBibliography.quotations.first)
        store.removeQuotation(firstQuotation.id)
        store.addQuotation(sourceID: sourceID, text: "Evidence", locator: "p. 3", note: "")
        store.addClaimLink(sourceID: sourceID, chapterPath: "Chapter.md", excerpt: "  ", locator: "", note: "")
        store.addClaimLink(
            sourceID: sourceID,
            chapterPath: "Chapter.md",
            excerpt: "  Supported claim  ",
            locator: " p. 4 ",
            note: " context "
        )
        let firstClaim = try XCTUnwrap(store.projectBibliography.claimLinks.first)
        store.removeClaimLink(firstClaim.id)
        store.addClaimLink(
            sourceID: sourceID,
            chapterPath: "Chapter.md",
            excerpt: "Supported claim",
            locator: "p. 5",
            note: ""
        )
        store.updateResearchNotes("New research notes")
        store.updateResearchNotes("New research notes")

        XCTAssertEqual(store.projectBibliography.style, .chicagoNotes)
        XCTAssertEqual(store.projectBibliography.quotations.first?.text, "Evidence")
        XCTAssertEqual(store.projectBibliography.claimLinks.first?.claimExcerpt, "Supported claim")
        XCTAssertEqual(store.researchNotesText, "New research notes")
        XCTAssertEqual(savedNotes, ["New research notes"])
        XCTAssertEqual(persisted.last, store.projectBibliography)

        store.removeResearchSource(sourceID)

        XCTAssertTrue(store.projectBibliography.sourceIDs.isEmpty)
        XCTAssertTrue(store.projectBibliography.quotations.isEmpty)
        XCTAssertTrue(store.projectBibliography.claimLinks.isEmpty)
        XCTAssertEqual(persisted.last, store.projectBibliography)
    }

    @MainActor
    func testStyleLearningStoreLoadsSavesRecordsAndClearsProjectPreferences() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ProjectStyleManager.prepare(at: root, projectName: "Style Test", kind: .nonfiction)
        var errors: [Error] = []
        let store = StyleLearningStore(
            projectRoot: { root },
            reportError: { errors.append($0) }
        )

        try store.load(at: root)
        XCTAssertTrue(store.styleText.contains("Style Test"))

        store.saveStyle("Prefer direct sentences.")
        XCTAssertEqual(store.styleText, "Prefer direct sentences.")

        store.recordStyleDecision(
            action: .accepted,
            issue: WritingIssue(
                category: .complexPhrase,
                range: NSRange(location: 0, length: 7),
                excerpt: "utilize",
                message: "Use a simpler alternative.",
                replacement: "use"
            )
        )

        XCTAssertEqual(store.styleDecisions.count, 1)
        XCTAssertTrue(store.styleText.contains("Prefer `use` to `utilize`"))

        store.clearLearnedStylePreferences()

        XCTAssertTrue(store.styleDecisions.isEmpty)
        XCTAssertTrue(store.styleText.contains("No editing preferences have been learned yet."))
        XCTAssertTrue(errors.isEmpty)
    }

    @MainActor
    func testStyleLearningStoreWithoutAProjectDoesNotMutateOrReportAnError() {
        var errors: [Error] = []
        let store = StyleLearningStore(
            projectRoot: { nil },
            reportError: { errors.append($0) }
        )

        store.saveStyle("Unattached style")
        store.recordStyleDecision(
            action: .declined,
            issue: WritingIssue(
                category: .adverb,
                range: NSRange(location: 0, length: 7),
                excerpt: "quickly",
                message: "Consider a stronger verb."
            )
        )
        store.clearLearnedStylePreferences()

        XCTAssertEqual(store.styleText, "")
        XCTAssertTrue(store.styleDecisions.isEmpty)
        XCTAssertTrue(errors.isEmpty)
    }

    @MainActor
    func testBetaReaderStoreCommitsEditsOnlyAfterPersistenceSucceeds() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var persisted: [BetaReaderProfile] = []
        let store = BetaReadersStore(
            projectRoot: { root },
            currentChapter: { ("Chapter 1.md", "Chapter 1", "Chapter text") },
            manuscriptProvider: {
                [ManuscriptDocument(
                    relativePath: "Chapter 1.md",
                    title: "Chapter 1",
                    text: "Chapter text"
                )]
            },
            reportError: { XCTFail("Unexpected error: \($0)") },
            saveReaders: { readers, savedRoot in
                XCTAssertEqual(savedRoot, root)
                persisted = readers
            }
        )

        store.addCustomBetaReader(
            name: "  First Reader  ",
            focus: "  Character motivation  ",
            audience: .fiction
        )
        let reader = store.customBetaReaders[0]

        XCTAssertEqual(reader.name, "First Reader")
        XCTAssertEqual(reader.focus, "Character motivation")
        XCTAssertEqual(persisted, store.customBetaReaders)
        XCTAssertEqual(
            try store.documents(for: .selection, selection: "Selected text").first?.relativePath,
            "Chapter 1.md"
        )
        XCTAssertEqual(
            try store.documents(for: .chapter, selection: nil).first?.text,
            "Chapter text"
        )
        XCTAssertEqual(try store.documents(for: .manuscript, selection: nil).count, 1)
    }

    @MainActor
    func testBetaReaderStoreRollsBackAndProtectsBuiltInReaders() {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var errors: [Error] = []
        let store = BetaReadersStore(
            projectRoot: { root },
            currentChapter: { nil },
            manuscriptProvider: { [] },
            reportError: { errors.append($0) },
            saveReaders: { _, _ in throw ExpectedPersistenceError.failed }
        )

        store.addCustomBetaReader(name: "Reader", focus: "Pacing", audience: .general)
        store.updateCustomBetaReader(BetaReaderProfile.builtIns[0])
        store.removeCustomBetaReader(BetaReaderProfile.builtIns[0])

        XCTAssertTrue(store.customBetaReaders.isEmpty)
        XCTAssertEqual(errors.count, 1)
        XCTAssertThrowsError(try store.documents(for: .selection, selection: "  ")) {
            guard case WritingAIError.emptySelection = $0 else {
                return XCTFail("Expected an empty-selection error, received \($0).")
            }
        }
    }

    @MainActor
    func testPublicationStoreCommitsMetadataAndHistoryOnlyAfterPersistenceSucceeds() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = WritingProjectManifest(name: "Transactional", kind: .nonfiction)
        var persisted = PublicationArchive(projectName: manifest.name, projectKind: manifest.kind)
        var errors: [Error] = []
        var shouldFail = false
        var persistence = PublicationPersistence.live
        persistence.load = { _ in persisted }
        persistence.save = { archive, _ in
            if shouldFail { throw ExpectedPersistenceError.failed }
            persisted = archive
        }
        let store = PublicationStore(
            projectRoot: { root },
            projectManifest: { manifest },
            projectOutline: { [] },
            bibliography: { ProjectBibliographyArchive() },
            saveCurrentDocument: {},
            saveProjectOutline: {},
            reportError: { errors.append($0) },
            persistence: persistence
        )
        try store.load(at: root)

        var accepted = persisted
        accepted.metadata.subtitle = "Persisted subtitle"
        store.updatePublicationArchive(accepted)
        XCTAssertEqual(store.publicationArchive.metadata.subtitle, "Persisted subtitle")
        XCTAssertEqual(persisted.metadata.subtitle, "Persisted subtitle")

        shouldFail = true
        var rejected = accepted
        rejected.metadata.subtitle = "Must roll back"
        store.updatePublicationArchive(rejected)

        XCTAssertEqual(store.publicationArchive.metadata.subtitle, "Persisted subtitle")
        XCTAssertEqual(persisted.metadata.subtitle, "Persisted subtitle")
        XCTAssertEqual(errors.count, 1)
    }

    @MainActor
    func testUpdatePublicationArchiveBundlesACustomFontReferencedByTheSelectedProfile() throws {
        let root = temporaryDirectory()
        let appFontsRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: appFontsRoot)
        }
        let systemFontURL = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Chalkduster.ttf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: systemFontURL.path), "Fixture font is not present on this system.")
        let sourceCopy = appFontsRoot.appendingPathComponent("Chalkduster.ttf")
        try FileManager.default.copyItem(at: systemFontURL, to: sourceCopy)
        let appRecord = try CustomFontDisk.addFont(from: sourceCopy, at: appFontsRoot, scope: .process)

        let manifest = WritingProjectManifest(name: "Fonted", kind: .nonfiction)
        var persisted = PublicationArchive(projectName: manifest.name, projectKind: manifest.kind)
        var persistence = PublicationPersistence.live
        persistence.load = { _ in persisted }
        persistence.save = { archive, _ in persisted = archive }
        let store = PublicationStore(
            projectRoot: { root },
            projectManifest: { manifest },
            projectOutline: { [] },
            bibliography: { ProjectBibliographyArchive() },
            saveCurrentDocument: {},
            saveProjectOutline: {},
            reportError: { _ in },
            persistence: persistence
        )
        try store.load(at: root)
        store.availableCustomFonts = { [appRecord] }
        store.customFontFileURL = { CustomFontDisk.fileURL(for: $0, at: appFontsRoot) }

        var archive = store.publicationArchive
        archive.profiles[0].layout.bodyFontName = appRecord.familyName
        store.updatePublicationArchive(archive)

        let projectFontManifest = try CustomFontDisk.loadManifest(at: ProjectFontDisk.fontsRootURL(at: root))
        XCTAssertEqual(projectFontManifest.fonts.map(\.familyName), [appRecord.familyName])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KistulentzSubstoreTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum ExpectedPersistenceError: LocalizedError {
    case failed

    var errorDescription: String? { "Expected save failure." }
}
