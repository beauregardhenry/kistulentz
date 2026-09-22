import XCTest
@testable import Kistulentz

/// Tests for `WritingActivityStore` -- the cross-project, day-granular writing-activity tally
/// (net words added, plus a running quality sample) that backs the calendar heatmap, streak, and
/// daily word target in `WritingGrowthView`. Mirrors `WritingGrowthStoreTests`' conventions
/// (isolated `UserDefaults` suite per test, injectable `currentDate`).
final class WritingActivityStoreTests: XCTestCase {
    @MainActor
    private func makeStore(
        suiteName: String,
        date: @escaping () -> Date = { WritingActivityStoreTests.fixedDate() }
    ) throws -> (store: WritingActivityStore, defaults: UserDefaults) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (WritingActivityStore(defaults: defaults, storageKey: "test.\(suiteName)", currentDate: date), defaults)
    }

    private static func fixedDate(dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15 + dayOffset
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - recordSave

    @MainActor
    func testStartsEmpty() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(store.days.isEmpty)
        XCTAssertEqual(store.today, DailyWritingActivity())
    }

    @MainActor
    func testFirstSaveOfAChapterThisSessionCreditsNothingButEstablishesABaseline() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "project#chapter-1", wordCount: 500)

        XCTAssertTrue(store.days.isEmpty, "no words should be credited for words written before this session started")
    }

    @MainActor
    func testASubsequentSaveWithMoreWordsCreditsThePositiveDelta() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "project#chapter-1", wordCount: 500)
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 620)

        XCTAssertEqual(store.today.wordsWritten, 120)
    }

    @MainActor
    func testASaveWithFewerWordsCreditsZeroRatherThanGoingNegative() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "project#chapter-1", wordCount: 500)
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 620)
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 580) // a revision pass cut 40 words

        XCTAssertEqual(store.today.wordsWritten, 120, "cutting bloat must never subtract from the day's progress")
    }

    @MainActor
    func testDifferentChaptersAreCreditedIndependentlyAndSummedForTheDay() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "project#chapter-1", wordCount: 100)
        store.recordSave(chapterKey: "project#chapter-2", wordCount: 50)
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 150)
        store.recordSave(chapterKey: "project#chapter-2", wordCount: 90)

        XCTAssertEqual(store.today.wordsWritten, 50 + 40)
    }

    // MARK: - recordQualitySample

    @MainActor
    func testQualitySamplesAccumulateCumulativelyAcrossTheDay() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordQualitySample(issueCount: 2, wordCount: 500)
        store.recordQualitySample(issueCount: 3, wordCount: 700)

        XCTAssertEqual(store.today.issuesObserved, 5)
        XCTAssertEqual(store.today.wordsObserved, 1_200)
    }

    @MainActor
    func testAZeroWordQualitySampleIsIgnored() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordQualitySample(issueCount: 0, wordCount: 0)

        XCTAssertTrue(store.days.isEmpty)
    }

    @MainActor
    func testDensityIsNilWithoutAQualitySampleAndComputedCorrectlyWithOne() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(store.density(for: Self.fixedDate()))

        store.recordQualitySample(issueCount: 4, wordCount: 2_000)

        XCTAssertEqual(store.density(for: Self.fixedDate()), 2.0)
    }

    // MARK: - Persistence

    @MainActor
    func testActivityPersistsAcrossReopen() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "project#chapter-1", wordCount: 100)
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 250)

        let reopened = WritingActivityStore(defaults: defaults, storageKey: "test.\(suite)") { Self.fixedDate() }
        XCTAssertEqual(reopened.today.wordsWritten, 150)
    }

    @MainActor
    func testClearRemovesActivityImmediatelyAndOnDisk() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 100)
        store.recordSave(chapterKey: "project#chapter-1", wordCount: 200)

        store.clear()

        XCTAssertTrue(store.days.isEmpty)
        let reopened = WritingActivityStore(defaults: defaults, storageKey: "test.\(suite)") { Self.fixedDate() }
        XCTAssertTrue(reopened.days.isEmpty)
    }

    // MARK: - Streak

    @MainActor
    func testStreakIsZeroWithNoHistory() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.currentStreak, 0)
        XCTAssertEqual(store.longestStreak, 0)
    }

    @MainActor
    func testStreakCountsConsecutiveDaysEndingToday() throws {
        var offset = -3
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "c", wordCount: 100) // day -3: establishes a baseline only, not asserted
        offset = -2
        store.recordSave(chapterKey: "c", wordCount: 150)
        offset = -1
        store.recordSave(chapterKey: "c", wordCount: 200)
        offset = 0
        store.recordSave(chapterKey: "c", wordCount: 300)

        XCTAssertEqual(store.currentStreak, 3)
    }

    @MainActor
    func testAGapBreaksTheStreak() throws {
        var offset = -3
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "c", wordCount: 100) // day -3
        offset = -1
        store.recordSave(chapterKey: "c", wordCount: 200) // day -1 (skips -2)
        offset = 0
        store.recordSave(chapterKey: "c", wordCount: 300) // day 0

        XCTAssertEqual(store.currentStreak, 2, "the gap at day -2 must stop the walk-back before reaching day -3")
    }

    @MainActor
    func testAnEmptyTodaySoFarFallsBackToYesterdayRatherThanZeroingTheStreak() throws {
        var offset = -3
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "c", wordCount: 100) // day -3: establishes a baseline only, not asserted
        offset = -2
        store.recordSave(chapterKey: "c", wordCount: 150)
        offset = -1
        store.recordSave(chapterKey: "c", wordCount: 200)
        offset = 0 // "today" -- nothing recorded here yet

        XCTAssertEqual(store.currentStreak, 2)
    }

    @MainActor
    func testLongestStreakCanExceedTheCurrentOne() throws {
        var offset = -6
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        store.recordSave(chapterKey: "c", wordCount: 100) // day -6: establishes a baseline only, not asserted
        for day in [-5, -4, -3, -2] { // a real 4-day streak that then breaks
            offset = day
            store.recordSave(chapterKey: "c", wordCount: 100 + (day + 6) * 10)
        }
        offset = 0 // today, alone, after a gap at day -1
        store.recordSave(chapterKey: "c", wordCount: 900)

        XCTAssertEqual(store.currentStreak, 1)
        XCTAssertEqual(store.longestStreak, 4)
    }

    // MARK: - Heat level

    @MainActor
    func testHeatLevelIsNoneWithoutAQualitySampleThatDay() throws {
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.heatLevel(for: Self.fixedDate()), .none)
    }

    @MainActor
    func testHeatLevelIsNoneUntilThereIsEnoughHistoryToRankFairly() throws {
        var offset = 0
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        for day in 0..<3 { // fewer than the minimum history threshold
            offset = day
            store.recordQualitySample(issueCount: day, wordCount: 1_000)
        }

        XCTAssertEqual(store.heatLevel(for: Self.fixedDate(dayOffset: 0)), .none)
    }

    @MainActor
    func testCleanestAndNoisiestDaysLandInTheBestAndWorstQuartilesOnceThereIsEnoughHistory() throws {
        var offset = 0
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        // Densities (issues per 1,000 words), day 0 the cleanest, day 4 the noisiest.
        let issueCounts = [0, 2, 5, 8, 20]
        for (day, issues) in issueCounts.enumerated() {
            offset = day
            store.recordQualitySample(issueCount: issues, wordCount: 1_000)
        }

        XCTAssertEqual(store.heatLevel(for: Self.fixedDate(dayOffset: 0)), .q4, "the cleanest day should be the best bucket")
        XCTAssertEqual(store.heatLevel(for: Self.fixedDate(dayOffset: 4)), .q1, "the noisiest day should be the worst bucket")
    }

    @MainActor
    func testIdenticalDensitiesAllLandInTheBestBucketRatherThanCollapsingToTheWorst() throws {
        var offset = 0
        let suite = "WritingActivityStoreTests.\(UUID().uuidString)"
        let (store, defaults) = try makeStore(suiteName: suite, date: { WritingActivityStoreTests.fixedDate(dayOffset: offset) })
        defer { defaults.removePersistentDomain(forName: suite) }

        for day in 0..<5 {
            offset = day
            store.recordQualitySample(issueCount: 0, wordCount: 1_000) // every day is equally clean
        }

        for day in 0..<5 {
            XCTAssertEqual(
                store.heatLevel(for: Self.fixedDate(dayOffset: day)), .q4,
                "day \(day) should be the best bucket, not the worst, when every day ties"
            )
        }
    }
}
