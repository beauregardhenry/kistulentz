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

    @MainActor
    func testRecordSurfacesAnErrorOnceWhenTheSnapshotCannotBeSavedAndClearsItOnTheNextSuccess() async throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: root.path)

        manager.record(id: UUID(), title: "Draft.md", fileURL: nil, projectRootURL: nil, text: "Unsaved text")

        try await waitUntil { manager.errorMessage != nil }
        XCTAssertTrue(manager.errorMessage?.contains("Draft.md") ?? false)

        // A second failed attempt (the debounced-typing case) must not replace or duplicate the
        // message -- it should still read exactly the same.
        let firstMessage = manager.errorMessage
        manager.record(id: UUID(), title: "Draft.md", fileURL: nil, projectRootURL: nil, text: "More unsaved text")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(manager.errorMessage, firstMessage)

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: root.path)
        manager.record(id: UUID(), title: "Draft.md", fileURL: nil, projectRootURL: nil, text: "Saved once unlocked")

        try await waitUntil { manager.errorMessage == nil }
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
    func testCoordinatorDebouncesRapidEditsAndRecordsOnlyTheLatestText() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())
        let coordinator = DraftRecoveryCoordinator(manager: manager)
        coordinator.configure(title: "Draft.md", fileURL: nil, projectRootURL: nil, text: "Initial")

        coordinator.schedule(text: "First edit")
        coordinator.schedule(text: "Second edit")
        coordinator.schedule(text: "Latest edit")

        try await waitUntil { DraftRecoveryDisk.loadAll(from: root).first?.recoveredText == "Latest edit" }
        let entries = DraftRecoveryDisk.loadAll(from: root)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Draft.md")
    }

    @MainActor
    func testCoordinatorFlushesImmediatelyAndCloseRemovesItsJournal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())
        let coordinator = DraftRecoveryCoordinator(manager: manager)
        coordinator.configure(title: "Draft.md", fileURL: nil, projectRootURL: nil, text: "Initial")

        coordinator.schedule(text: "Unsaved")
        coordinator.flush()
        try await waitUntil { DraftRecoveryDisk.loadAll(from: root).count == 1 }

        coordinator.close()
        try await waitUntil { DraftRecoveryDisk.loadAll(from: root).isEmpty }
    }

    @MainActor
    func testSavingUntitledDraftRemovesTheObsoleteUntitledJournal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())
        let coordinator = DraftRecoveryCoordinator(manager: manager)
        coordinator.configure(title: "Untitled.md", fileURL: nil, projectRootURL: nil, text: "Initial")
        coordinator.schedule(text: "Saved text")
        coordinator.flush()
        try await waitUntil { DraftRecoveryDisk.loadAll(from: root).count == 1 }

        let savedURL = root.appendingPathComponent("Saved.md")
        try "Saved text".write(to: savedURL, atomically: true, encoding: .utf8)
        coordinator.configure(title: "Saved.md", fileURL: savedURL, projectRootURL: root, text: "Saved text")

        try await waitUntil { DraftRecoveryDisk.loadAll(from: root).isEmpty }
    }

    @MainActor
    func testManagerReloadResolveAndSessionRemovalKeepOtherDraftsIntact() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldSession = UUID()
        let first = DraftRecoveryEntry(
            id: UUID(), sessionID: oldSession, title: "One.md", originalFilePath: nil,
            projectRootPath: nil, recoveredText: "One"
        )
        let second = DraftRecoveryEntry(
            id: UUID(), sessionID: UUID(), title: "Two.md", originalFilePath: nil,
            projectRootPath: nil, recoveredText: "Two"
        )
        try DraftRecoveryDisk.save(first, in: root)
        try DraftRecoveryDisk.save(second, in: root)
        let manager = DraftRecoveryManager(directoryURL: root, sessionID: UUID())

        manager.resolve(first)
        try await waitUntil { DraftRecoveryDisk.loadAll(from: root).map(\.id) == [second.id] }
        XCTAssertEqual(manager.pendingEntries.map(\.id), [second.id])

        DraftRecoveryDisk.remove(sessionID: second.sessionID, from: root)
        manager.reloadPendingEntries()
        XCTAssertTrue(manager.pendingEntries.isEmpty)
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

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for draft recovery I/O.")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
