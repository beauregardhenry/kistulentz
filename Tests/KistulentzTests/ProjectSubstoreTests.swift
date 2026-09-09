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
