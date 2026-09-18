import XCTest
@testable import Kistulentz

/// Tests for `WritingGrowthStore` (#91) -- the cross-project accept/decline tally, independent of
/// `StyleLearningStore`'s per-project decision log. Covers the store's aggregation logic directly;
/// the toolbar menu item and `WritingGrowthView` that read it back aren't covered here, matching
/// this suite's existing precedent of not driving SwiftUI view bodies directly (see
/// `EditorPreferencesTests.swift`'s header comment).
final class WritingGrowthStoreTests: XCTestCase {
    @MainActor
    private func makeStore(
        suiteName: String,
        date: @escaping () -> Date = { WritingGrowthStoreTests.fixedDate() }
    ) throws -> (store: WritingGrowthStore, defaults: UserDefaults) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (WritingGrowthStore(defaults: defaults, storageKey: "test.\(suiteName)", currentDate: date), defaults)
    }

    private static func fixedDate(monthOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3 + monthOffset
        components.day = 15
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @MainActor
    func testStartsEmpty() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(store.months.isEmpty)
    }

    @MainActor
    func testRecordingCreatesTheCurrentMonthWithTheRightTally() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record(category: .adverb, action: .accepted)

        XCTAssertEqual(store.months.count, 1)
        let month = try XCTUnwrap(store.months.first)
        XCTAssertEqual(month.key, "2026-03")
        XCTAssertEqual(month.tallies[.adverb], WritingGrowthTally(accepted: 1, declined: 0))
    }

    @MainActor
    func testRecordingAccumulatesAcrossMultipleDecisionsInTheSameMonth() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record(category: .adverb, action: .accepted)
        store.record(category: .adverb, action: .accepted)
        store.record(category: .adverb, action: .declined)
        store.record(category: .passiveVoice, action: .declined)

        let month = try XCTUnwrap(store.months.first)
        XCTAssertEqual(month.tallies[.adverb], WritingGrowthTally(accepted: 2, declined: 1))
        XCTAssertEqual(month.tallies[.passiveVoice], WritingGrowthTally(accepted: 0, declined: 1))
    }

    @MainActor
    func testDifferentMonthsAreTrackedSeparatelyAndSortedOldestFirst() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        var currentMonthOffset = 0
        let (store, defaults) = try makeStore(
            suiteName: suite,
            date: { WritingGrowthStoreTests.fixedDate(monthOffset: currentMonthOffset) }
        )
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record(category: .adverb, action: .accepted)
        currentMonthOffset = 1
        store.record(category: .adverb, action: .declined)
        currentMonthOffset = -1
        store.record(category: .adverb, action: .declined)

        XCTAssertEqual(store.months.map(\.key), ["2026-02", "2026-03", "2026-04"])
    }

    @MainActor
    func testHistoryPersistsAcrossReopen() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.record(category: .passiveVoice, action: .accepted)

        let reopened = WritingGrowthStore(defaults: defaults, storageKey: "test.\(suite)") { Self.fixedDate() }
        XCTAssertEqual(reopened.months.first?.tallies[.passiveVoice], WritingGrowthTally(accepted: 1, declined: 0))
    }

    @MainActor
    func testClearRemovesHistoryImmediatelyAndOnDisk() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.record(category: .adverb, action: .accepted)

        store.clear()

        XCTAssertTrue(store.months.isEmpty)
        let reopened = WritingGrowthStore(defaults: defaults, storageKey: "test.\(suite)") { Self.fixedDate() }
        XCTAssertTrue(reopened.months.isEmpty)
    }

    /// A raw category string this build doesn't recognize -- as if written by a future version --
    /// is dropped from the resolved trend rather than crashing the load.
    @MainActor
    func testUnrecognizedCategoryKeysAreDroppedWithoutCrashing() throws {
        let suite = "WritingGrowthStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storageKey = "test.\(suite)"
        let rawJSON = """
        {"months":{"2026-03":{"futureCategoryFromANewerVersion":{"accepted":3,"declined":1},"adverb":{"accepted":2,"declined":0}}}}
        """
        defaults.set(Data(rawJSON.utf8), forKey: storageKey)

        let store = WritingGrowthStore(defaults: defaults, storageKey: storageKey) { Self.fixedDate() }

        let month = try XCTUnwrap(store.months.first)
        XCTAssertEqual(month.tallies.count, 1)
        XCTAssertEqual(month.tallies[.adverb], WritingGrowthTally(accepted: 2, declined: 0))
    }
}
