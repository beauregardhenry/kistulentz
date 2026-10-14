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

    // MARK: - recentWeeks (the heatmap's week grid)

    private func gregorian(in timeZone: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        return calendar
    }

    /// A specific moment on a calendar day (not snapped to midnight) -- used as `today`.
    private func moment(_ year: Int, _ month: Int, _ day: Int, hour: Int, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    /// Midnight at the start of the given calendar day -- what `recentWeeks` should produce.
    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        calendar.startOfDay(for: try moment(year, month, day, hour: 12, in: calendar))
    }

    func testRecentWeeksBuildsSundayToSaturdayColumnsOfSevenDays() throws {
        let calendar = try gregorian()
        // 2026-10-14 is a Wednesday.
        let today = try moment(2026, 10, 14, hour: 15, in: calendar)
        let weeks = WritingActivityStore.recentWeeks(weeksShown: 16, today: today, calendar: calendar)

        XCTAssertEqual(weeks.count, 16)
        for week in weeks {
            XCTAssertEqual(week.count, 7)
            XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(week.first)), 1, "each column starts on Sunday")
            XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(week.last)), 7, "each column ends on Saturday")
        }
    }

    func testRecentWeeksFinalColumnIsTheCurrentWeekWhereverTodayFallsInIt() throws {
        let calendar = try gregorian()
        // Oct 10, 2026 is a Saturday, Oct 11 a Sunday, Oct 14 a Wednesday.
        let cases: [(today: Int, label: String)] = [(10, "Saturday"), (11, "Sunday"), (14, "Wednesday")]
        let expectedWeekStart = [10: 4, 11: 11, 14: 11]

        for (todayDay, label) in cases {
            let today = try moment(2026, 10, todayDay, hour: 15, in: calendar)
            let finalColumn = try XCTUnwrap(
                WritingActivityStore.recentWeeks(weeksShown: 4, today: today, calendar: calendar).last
            )
            let start = try XCTUnwrap(expectedWeekStart[todayDay])
            XCTAssertEqual(finalColumn.first, try day(2026, 10, start, in: calendar), "week start when today is a \(label)")
            XCTAssertEqual(finalColumn.last, try day(2026, 10, start + 6, in: calendar), "week end when today is a \(label)")
            XCTAssertTrue(finalColumn.contains(try day(2026, 10, todayDay, in: calendar)), "today is in the last column on a \(label)")
        }
    }

    func testRecentWeeksIsOneUninterruptedRunOfConsecutiveMidnightsAcrossDaylightSavingChanges() throws {
        // Chicago springs forward 2026-03-08 and falls back 2025-11-02; both land inside 16 weeks
        // ending Tuesday 2026-03-10. A grid that stepped by 24-hour intervals instead of calendar
        // days would drift off midnight, then skip or repeat a day.
        let calendar = try gregorian(in: "America/Chicago")
        let today = try moment(2026, 3, 10, hour: 15, in: calendar)
        let flat = WritingActivityStore.recentWeeks(weeksShown: 16, today: today, calendar: calendar).flatMap { $0 }

        XCTAssertEqual(flat.count, 16 * 7)
        XCTAssertEqual(Set(flat).count, flat.count, "no day is repeated")
        for date in flat {
            XCTAssertEqual(calendar.startOfDay(for: date), date, "every cell is a local midnight")
        }
        for (earlier, later) in zip(flat, flat.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: earlier, to: later).day, 1)
        }
    }

    func testRecentWeeksCrossesAYearBoundaryWithoutGaps() throws {
        let calendar = try gregorian()
        // Jan 3, 2026 is a Saturday, so the final column is Dec 28, 2025 through Jan 3, 2026.
        let today = try moment(2026, 1, 3, hour: 9, in: calendar)
        let weeks = WritingActivityStore.recentWeeks(weeksShown: 2, today: today, calendar: calendar)

        XCTAssertEqual(weeks.first?.first, try day(2025, 12, 21, in: calendar))
        XCTAssertEqual(weeks.last?.first, try day(2025, 12, 28, in: calendar))
        XCTAssertEqual(weeks.last?.last, try day(2026, 1, 3, in: calendar))
    }

    func testRecentWeeksIgnoresTheTimeOfDayAndTheCalendarsFirstWeekday() throws {
        var mondayFirst = try gregorian()
        mondayFirst.firstWeekday = 2
        let justAfterMidnight = try moment(2026, 10, 14, hour: 0, in: mondayFirst)
        let lateEvening = try moment(2026, 10, 14, hour: 23, in: mondayFirst)

        let morning = WritingActivityStore.recentWeeks(weeksShown: 3, today: justAfterMidnight, calendar: mondayFirst)
        let evening = WritingActivityStore.recentWeeks(weeksShown: 3, today: lateEvening, calendar: mondayFirst)

        XCTAssertEqual(morning, evening)
        // The grid is deliberately Sunday-first (like GitHub's) even for a Monday-first locale.
        XCTAssertEqual(mondayFirst.component(.weekday, from: try XCTUnwrap(morning.last?.first)), 1)
    }

    func testRecentWeeksWithNoWeeksRequestedIsEmpty() throws {
        let calendar = try gregorian()
        XCTAssertTrue(WritingActivityStore.recentWeeks(weeksShown: 0, today: Date(), calendar: calendar).isEmpty)
        XCTAssertEqual(WritingActivityStore.recentWeeks(weeksShown: 1, today: Date(), calendar: calendar).count, 1)
    }
}
