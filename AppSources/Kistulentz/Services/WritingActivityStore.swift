import Foundation

/// One calendar day's writing activity: net words added, plus enough of a running quality sample
/// (`issuesObserved` over `wordsObserved`) to compute that day's findings-per-1,000-words density.
struct DailyWritingActivity: Codable, Equatable {
    var wordsWritten = 0
    var issuesObserved = 0
    var wordsObserved = 0
}

/// A day's craft-quality bucket, ranked against the writer's *own* history rather than a fixed
/// threshold -- see `WritingActivityStore.heatLevel(for:)`. Ordered worst (`q1`) to best (`q4`);
/// `none` covers both "nothing recorded" and "not enough history yet to rank fairly."
enum WritingHeatLevel: Equatable, Hashable, CaseIterable {
    case none
    case q1
    case q2
    case q3
    case q4
}

/// Cross-project, day-granular writing activity: how many words were added and how clean they
/// were, independent of any single project's lifecycle -- the same app-wide, UserDefaults-backed
/// shape `WritingGrowthStore` already uses, but bucketed by calendar day instead of month, since a
/// heatmap and a streak both need day resolution that store doesn't have.
///
/// Deliberately a sibling store, not an extension of `WritingGrowthStore`: that store answers "am I
/// applying feedback" (accept/decline decisions); this one answers "did I write today, and how
/// clean was it" (raw activity + live analysis findings). Different questions, different inputs.
///
/// Two independent signals are recorded, matching the intent that showing up (the streak) and
/// craft quality (the heatmap's color) should never be conflated into one number that could reward
/// padding over careful editing:
/// - `recordSave` credits *net new* words for a chapter on each debounced save, floored at zero so
///   a revision pass that nets fewer words (cutting bloat) never subtracts from the day's progress.
/// - `recordQualitySample` accumulates issue/word counts from the live readability+destink pass
///   that already runs on every edit, so `heatLevel(for:)` can rank a day's finding density against
///   every other day the writer has ever had -- not a hardcoded "good" number, since what counts as
///   clean prose genuinely differs by genre and by how far into a first draft a passage still is.
@MainActor
final class WritingActivityStore: ObservableObject {
    private struct Archive: Codable {
        /// Day key ("yyyy-MM-dd") -> that day's activity.
        var days: [String: DailyWritingActivity] = [:]
    }

    /// A day needs at least this many *other* scored days in its history before quartile ranking
    /// means anything -- with only one or two data points, "worst quartile" and "best quartile"
    /// are the same day wearing different labels.
    private static let minimumHistoryForQuartiles = 4

    @Published private(set) var days: [String: DailyWritingActivity] = [:]

    private let defaults: UserDefaults
    private let storageKey: String
    private let currentDate: () -> Date

    /// Last word count seen for a given chapter this session (keyed by `"<project root>#<chapter
    /// path>"`, formed by callers), never persisted. A fresh session -- including a relaunch --
    /// re-seeds this from whatever's first reported, which is exactly what makes `recordSave`'s
    /// zero-delta-on-first-sight behavior correct: it means "no credit for words written before
    /// this session started," not "no credit for a chapter Kistulentz hasn't seen yet."
    private var lastKnownWordCounts: [String: Int] = [:]

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.beauhenry.kistulentz.writingActivity.v1",
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.currentDate = currentDate
        days = Self.loadArchive(defaults: defaults, storageKey: storageKey).days
    }

    /// Credits the positive difference between `wordCount` and the last word count seen for
    /// `chapterKey` in this session to today. A same-or-smaller count (an edit, a deletion, or the
    /// very first save this session establishing a baseline) credits nothing -- it never goes
    /// negative, so careful revision can't make a day's progress look worse.
    func recordSave(chapterKey: String, wordCount: Int) {
        let baseline = lastKnownWordCounts[chapterKey] ?? wordCount
        lastKnownWordCounts[chapterKey] = wordCount
        let delta = max(wordCount - baseline, 0)
        guard delta > 0 else { return }
        mutateToday { $0.wordsWritten += delta }
    }

    /// Accumulates one live-analysis sample's issue and word counts into today's running total.
    /// Cumulative sums (rather than averaging each sample's density) so a near-empty sample --
    /// right after opening a short chapter, say -- can't skew the day's overall density on its own.
    func recordQualitySample(issueCount: Int, wordCount: Int) {
        guard wordCount > 0 else { return }
        mutateToday {
            $0.issuesObserved += issueCount
            $0.wordsObserved += wordCount
        }
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        days = [:]
        lastKnownWordCounts = [:]
    }

    private func mutateToday(_ mutate: (inout DailyWritingActivity) -> Void) {
        var archive = Self.loadArchive(defaults: defaults, storageKey: storageKey)
        let key = Self.dayKey(for: currentDate())
        var day = archive.days[key] ?? DailyWritingActivity()
        mutate(&day)
        archive.days[key] = day
        save(archive)
    }

    private func save(_ archive: Archive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: storageKey)
        days = archive.days
    }

    private static func loadArchive(defaults: UserDefaults, storageKey: String) -> Archive {
        guard let data = defaults.data(forKey: storageKey),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else {
            return Archive()
        }
        return archive
    }

    /// Shared "yyyy-MM-dd" formatter, reused (not reconstructed) by every day-key call -- `dayKey`
    /// is on the hot path for rendering the heatmap (once per visible day-square), and DateFormatter
    /// construction is expensive enough to be worth caching. Safe to mutate `.timeZone` in place
    /// since this type is `@MainActor`-isolated, so there's never concurrent access.
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String {
        dayKeyFormatter.timeZone = timeZone
        return dayKeyFormatter.string(from: date)
    }

    // MARK: - Today

    var today: DailyWritingActivity {
        days[Self.dayKey(for: currentDate())] ?? DailyWritingActivity()
    }

    // MARK: - Streak

    var currentStreak: Int { Self.streak(days: days, asOf: currentDate()) }
    var longestStreak: Int { Self.longestStreak(days: days) }

    /// Consecutive calendar days, walking backward from `date`, with a recorded entry. If `date`
    /// itself has nothing recorded yet, starts from the day before instead -- a still-empty "today"
    /// shouldn't zero out a streak that's otherwise unbroken through yesterday.
    static func streak(days: [String: DailyWritingActivity], asOf date: Date) -> Int {
        let calendar = Calendar.current
        var cursor = date
        if days[dayKey(for: cursor)] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days[dayKey(for: cursor)] != nil {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func longestStreak(days: [String: DailyWritingActivity]) -> Int {
        let calendar = Calendar.current
        dayKeyFormatter.timeZone = .current
        let dates = days.keys.compactMap(dayKeyFormatter.date(from:)).sorted()
        guard !dates.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for index in 1..<dates.count {
            if let expectedGap = calendar.dateComponents([.day], from: dates[index - 1], to: dates[index]).day,
               expectedGap == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
    }

    // MARK: - Heat level (self-relative quartiles)

    func density(for date: Date) -> Double? {
        density(of: days[Self.dayKey(for: date)])
    }

    private func density(of day: DailyWritingActivity?) -> Double? {
        guard let day, day.wordsObserved > 0 else { return nil }
        return Double(day.issuesObserved) / Double(day.wordsObserved) * 1_000
    }

    /// Ranks `date`'s density against every other scored day using ordinary quartile boundaries
    /// (linear-interpolated from the sorted distribution), not a raw "how many days are cleaner
    /// than this one" count -- the latter degenerates when several days tie (e.g. everyone at zero
    /// findings would otherwise all collapse into the worst bucket instead of the best one).
    func heatLevel(for date: Date) -> WritingHeatLevel {
        guard let value = density(for: date) else { return .none }
        let allDensities = days.values.compactMap(density(of:)).sorted()
        guard allDensities.count >= Self.minimumHistoryForQuartiles else { return .none }
        let q1 = Self.percentile(allDensities, 0.25)
        let q2 = Self.percentile(allDensities, 0.50)
        let q3 = Self.percentile(allDensities, 0.75)
        // Lower density is better craft, so the lowest-density quartile is the *best* bucket.
        switch value {
        case ...q1: return .q4
        case ...q2: return .q3
        case ...q3: return .q2
        default: return .q1
        }
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = fraction * Double(sorted.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let weight = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * weight
    }
}
