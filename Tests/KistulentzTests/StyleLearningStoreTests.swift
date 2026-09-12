import Foundation
import XCTest
@testable import Kistulentz

/// Covers `StyleLearningStore` itself -- the published `styleText`/`styleDecisions` reload
/// sequencing on top of the already-tested `ProjectStyleManager` disk layer (see
/// `ProjectStyleLearningTests` and `WritingProjectTests`).
@MainActor
final class StyleLearningStoreTests: XCTestCase {
    func testSaveStyleUpdatesPublishedTextAndPersistsToDisk() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }

        let style = store.styleLearningStore.styleText + "\n## House rule\n\nSpell out numbers under twenty.\n"
        store.styleLearningStore.saveStyle(style)

        XCTAssertEqual(store.styleLearningStore.styleText, style)
        XCTAssertEqual(try ProjectStyleManager.loadStyle(at: root), style)
    }

    func testRecordStyleDecisionReloadsStyleTextAndDecisionsFromDisk() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let text = "She moved quickly toward the door."
        let issue = WritingIssue(
            category: .adverb,
            range: (text as NSString).range(of: "quickly"),
            excerpt: "quickly",
            message: "Use a stronger verb.",
            replacement: "hurried"
        )

        store.styleLearningStore.recordStyleDecision(action: .declined, issue: issue)

        XCTAssertEqual(store.styleLearningStore.styleDecisions.count, 1)
        XCTAssertEqual(store.styleLearningStore.styleDecisions.first?.action, .declined)
        XCTAssertTrue(store.styleLearningStore.styleText.contains("Keep `quickly` instead of `hurried`"))
        XCTAssertEqual(try ProjectStyleManager.loadDecisions(at: root).count, 1)
    }

    func testClearLearnedStylePreferencesRemovesDecisionsButKeepsManualRules() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let manualStyle = try ProjectStyleManager.loadStyle(at: root) + "\n## Manual rule\n\nAlways capitalize the Tide.\n"
        try ProjectStyleManager.saveStyle(manualStyle, at: root)

        let text = "She moved quickly toward the Tide."
        let issue = WritingIssue(
            category: .adverb,
            range: (text as NSString).range(of: "quickly"),
            excerpt: "quickly",
            message: "Use a stronger verb.",
            replacement: "hurried"
        )
        store.styleLearningStore.recordStyleDecision(action: .declined, issue: issue)
        XCTAssertFalse(store.styleLearningStore.styleDecisions.isEmpty)

        store.styleLearningStore.clearLearnedStylePreferences()

        XCTAssertTrue(store.styleLearningStore.styleDecisions.isEmpty)
        XCTAssertTrue(
            store.styleLearningStore.styleText.contains("Always capitalize the Tide."),
            "clearing learned preferences must not touch manually written rules"
        )
    }

    func testResetClearsPublishedStateWithoutTouchingDisk() throws {
        let (store, root, parent) = try openedProject()
        defer { try? FileManager.default.removeItem(at: parent) }
        let onDiskBefore = try ProjectStyleManager.loadStyle(at: root)

        store.styleLearningStore.reset()

        XCTAssertEqual(store.styleLearningStore.styleText, "")
        XCTAssertTrue(store.styleLearningStore.styleDecisions.isEmpty)
        XCTAssertEqual(try ProjectStyleManager.loadStyle(at: root), onDiskBefore, "reset() must be in-memory only")
    }

    // MARK: - Helpers

    private func openedProject() throws -> (store: WritingProjectStore, root: URL, parent: URL) {
        let parent = temporaryDirectory()
        let root = try WritingProjectDisk.createProject(in: parent, name: "Style", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        return (store, root, parent)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-StyleLearningStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
