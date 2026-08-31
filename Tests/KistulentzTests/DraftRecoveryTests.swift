import XCTest
@testable import Kistulentz

final class DraftRecoveryTests: XCTestCase {
    @MainActor
    func testAbnormalSessionDraftIsOfferedWithoutChangingOriginal() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Chapter.md")
        try "# Chapter\n\nSaved text.\n".write(to: original, atomically: true, encoding: .utf8)
        let entry = DraftRecoveryEntry(
            id: UUID(),
            sessionID: UUID(),
            title: "Chapter.md",
            originalFilePath: original.path,
            projectRootPath: nil,
            recoveredText: "# Chapter\n\nRecovered text.\n"
        )
        try DraftRecoveryDisk.save(entry, in: root)

        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())

        XCTAssertEqual(manager.pendingEntries.map(\.id), [entry.id])
        XCTAssertEqual(manager.pendingEntries.first?.recoveredText, entry.recoveredText)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "# Chapter\n\nSaved text.\n")
    }

    @MainActor
    func testAlreadySavedRecoveryIsRemovedAutomatically() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Draft.md")
        let text = "# Draft\n\nAlready saved.\n"
        try text.write(to: original, atomically: true, encoding: .utf8)
        let entry = DraftRecoveryEntry(
            id: UUID(),
            sessionID: UUID(),
            title: "Draft.md",
            originalFilePath: original.path,
            projectRootPath: nil,
            recoveredText: text
        )
        try DraftRecoveryDisk.save(entry, in: root)

        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())

        XCTAssertTrue(manager.pendingEntries.isEmpty)
        XCTAssertTrue(DraftRecoveryDisk.loadAll(from: root).isEmpty)
    }

    @MainActor
    func testCleanShutdownRemovesOnlyCurrentSessionJournals() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldEntry = DraftRecoveryEntry(
            id: UUID(),
            sessionID: UUID(),
            title: "Older Draft.md",
            originalFilePath: nil,
            projectRootPath: nil,
            recoveredText: "Older unsaved work"
        )
        try DraftRecoveryDisk.save(oldEntry, in: root)
        let currentSession = UUID()
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: currentSession)
        let savedURL = root.appendingPathComponent("Current Draft.md")
        try "Current saved work".write(to: savedURL, atomically: true, encoding: .utf8)
        manager.record(
            id: UUID(),
            title: "Current Draft.md",
            fileURL: savedURL,
            projectRootURL: nil,
            text: "Current saved work"
        )

        manager.endSession()

        let remaining = DraftRecoveryDisk.loadAll(from: root)
        XCTAssertEqual(remaining.map(\.id), [oldEntry.id])
    }

    @MainActor
    func testCleanShutdownKeepsCurrentSessionJournalWhenSaveDidNotSucceed() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Current Draft.md")
        try "Last saved text".write(to: original, atomically: true, encoding: .utf8)
        let entryID = UUID()
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())
        manager.record(
            id: entryID,
            title: "Current Draft.md",
            fileURL: original,
            projectRootURL: nil,
            text: "Unsaved recovered text"
        )

        manager.endSession()

        let remaining = DraftRecoveryDisk.loadAll(from: root)
        XCTAssertEqual(remaining.map(\.id), [entryID])
        XCTAssertEqual(remaining.first?.recoveredText, "Unsaved recovered text")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "Last saved text")
    }

    func testSavingRecoveredCopyDoesNotReplaceOriginal() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Original.md")
        let copy = root.appendingPathComponent("Recovered.md")
        try "Original".write(to: original, atomically: true, encoding: .utf8)
        let entry = DraftRecoveryEntry(
            id: UUID(),
            sessionID: UUID(),
            title: "Original.md",
            originalFilePath: original.path,
            projectRootPath: nil,
            recoveredText: "Recovered"
        )

        try DraftRecoveryDisk.writeRecoveredText(entry, to: copy)

        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "Original")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "Recovered")
    }

    @MainActor
    func testOnboardingChoicePersists() throws {
        let suite = "Kistulentz-Onboarding-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.hasCompletedOnboarding)

        settings.completeOnboarding()

        XCTAssertTrue(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }

    @MainActor
    func testEnglishPackPromptChoicePersists() throws {
        let suite = "Kistulentz-English-Pack-Prompt-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.hasAcknowledgedEnglishPackPrompt)

        settings.acknowledgeEnglishPackPrompt()

        XCTAssertTrue(AppSettings(defaults: defaults).hasAcknowledgedEnglishPackPrompt)
    }

    @MainActor
    func testEnglishPackPromptCanOnlyBeClaimedByOneWindowPerLaunch() throws {
        let suite = "Kistulentz-English-Pack-Claim-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.claimEnglishPackPrompt())
        XCTAssertFalse(settings.claimEnglishPackPrompt())
        XCTAssertFalse(settings.hasAcknowledgedEnglishPackPrompt)
    }

    func testFictionAndNonfictionSamplesAreSeparateEditableProjects() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fiction = try SampleProjectBuilder.create(in: root, kind: .fiction)
        let secondFiction = try SampleProjectBuilder.create(in: root, kind: .fiction)
        let nonfiction = try SampleProjectBuilder.create(in: root, kind: .nonfiction)
        let fictionManifest = try WritingProjectDisk.loadManifest(at: fiction)
        let nonfictionManifest = try WritingProjectDisk.loadManifest(at: nonfiction)

        XCTAssertNotEqual(fiction, secondFiction)
        XCTAssertEqual(fictionManifest.kind, .fiction)
        XCTAssertEqual(nonfictionManifest.kind, .nonfiction)
        XCTAssertEqual(fictionManifest.chapterOrder.count, 2)
        XCTAssertEqual(nonfictionManifest.chapterOrder.count, 2)
        XCTAssertTrue(try WritingProjectDisk.readChapter("Chapter 1.md", at: fiction).contains("Signal House"))
        XCTAssertTrue(try WritingProjectDisk.readChapter("Draft.md", at: nonfiction).contains("Clear Systems"))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-Recovery-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
