import Foundation

/// One month's accepted/declined counts for a single issue category.
struct WritingGrowthTally: Codable, Equatable {
    var accepted = 0
    var declined = 0
}

/// One recorded calendar month's tallies, keyed by category, for the trend view to iterate.
struct WritingGrowthMonth: Identifiable, Equatable {
    var id: String { key }
    /// "yyyy-MM", sortable as a plain string.
    let key: String
    let tallies: [IssueCategory: WritingGrowthTally]
}

/// Cross-project growth history: how many suggestions of each category the author has accepted
/// vs. declined, bucketed by calendar month, independent of any single project's lifecycle. Where
/// `StyleLearningStore`'s decision log only suppresses repeat flags *within the open project* --
/// and forgets everything once that project closes -- this store answers a different question,
/// "am I actually getting better at this over time," by rolling every accept/decline decision
/// (`EditorWorkspace+EditingActions.swift`'s `apply`, `decline`, and `applyAll`) up into one
/// persistent, app-wide history that survives closing, or even deleting, any individual project.
///
/// Persisted as one small JSON blob in `UserDefaults`, the same storage `DismissedSuggestionStore`
/// already uses for a similarly shaped "decisions accumulated over the app's whole lifetime"
/// concern -- a handful of categories times a few dozen months at most, never large enough to need
/// its own file on disk.
@MainActor
final class WritingGrowthStore: ObservableObject {
    private struct Archive: Codable {
        /// Month key ("yyyy-MM") -> category raw value -> tally. Raw `String` keys, not
        /// `IssueCategory` directly, so the JSON stays a plain nested object instead of the
        /// array-of-pairs encoding Swift falls back to for a non-`String`/`Int` dictionary key.
        var months: [String: [String: WritingGrowthTally]] = [:]
    }

    @Published private(set) var months: [WritingGrowthMonth] = []

    private let defaults: UserDefaults
    private let storageKey: String
    private let currentDate: () -> Date

    /// `currentDate` is injectable so tests can control which month a recording lands in without
    /// waiting for a real calendar month boundary.
    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.beauhenry.kistulentz.writingGrowth.v1",
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.currentDate = currentDate
        months = Self.resolve(Self.loadArchive(defaults: defaults, storageKey: storageKey))
    }

    func record(category: IssueCategory, action: StyleDecisionAction) {
        var archive = Self.loadArchive(defaults: defaults, storageKey: storageKey)
        let monthKey = Self.monthKey(for: currentDate())
        var monthTallies = archive.months[monthKey] ?? [:]
        var tally = monthTallies[category.rawValue] ?? WritingGrowthTally()
        switch action {
        case .accepted: tally.accepted += 1
        case .declined: tally.declined += 1
        }
        monthTallies[category.rawValue] = tally
        archive.months[monthKey] = monthTallies
        save(archive)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        months = []
    }

    private func save(_ archive: Archive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: storageKey)
        months = Self.resolve(archive)
    }

    private static func loadArchive(defaults: UserDefaults, storageKey: String) -> Archive {
        guard let data = defaults.data(forKey: storageKey),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else {
            return Archive()
        }
        return archive
    }

    /// Raw category keys this build doesn't recognize -- from a future version's new category,
    /// read by an older build -- are silently dropped from the resolved trend rather than
    /// crashing or showing a raw string in the UI. Sorted oldest first, matching how a trend
    /// reads left to right.
    private static func resolve(_ archive: Archive) -> [WritingGrowthMonth] {
        archive.months.keys.sorted().map { key in
            let tallies = archive.months[key] ?? [:]
            let resolved = Dictionary(uniqueKeysWithValues: tallies.compactMap { rawCategory, tally in
                IssueCategory(rawValue: rawCategory).map { ($0, tally) }
            })
            return WritingGrowthMonth(key: key, tallies: resolved)
        }
    }

    private static func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
