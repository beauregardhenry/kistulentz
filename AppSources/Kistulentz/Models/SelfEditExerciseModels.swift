import Foundation

/// One flagged passage offered as a self-editing exercise: attempt a fix on it yourself before
/// Kistulentz reveals its own suggestion for comparison.
struct SelfEditExercise: Identifiable, Equatable {
    let issue: WritingIssue
    var id: UUID { issue.id }
}

/// A fixed, session-scoped set of exercises, snapshotted once when the writer asks for them so the
/// set doesn't reshuffle out from under them while they're working through it.
struct SelfEditExercisePresentation: Identifiable {
    let id = UUID()
    let exercises: [SelfEditExercise]
    /// Categories this set leans toward because the writer declines them most -- already narrowed
    /// to ones that actually appear in `exercises`, so the note never names something absent.
    let focusCategories: [IssueCategory]

    init(exercises: [SelfEditExercise], focusCategories: [IssueCategory] = []) {
        self.exercises = exercises
        self.focusCategories = focusCategories.filter { focus in
            exercises.contains { $0.issue.category == focus }
        }
    }

    /// One line telling the writer why this set leans the way it does, or nil when it doesn't.
    var focusNote: String? {
        guard !focusCategories.isEmpty else { return nil }
        let names = focusCategories.map(\.title)
        let list = names.count == 2 ? "\(names[0]) and \(names[1])" : names.joined(separator: ", ")
        return "Leaning toward \(list) -- the suggestions you decline most often."
    }
}

/// Draws a small set of self-edit exercises from the current document's own already-flagged
/// issues -- never invented or fetched (issue #92's central acceptance criterion). Only categories
/// with a `practicePrompt` (a craft judgment worth practicing, not an objective correction) are
/// eligible: see `IssueCategory.practicePrompt` for why spelling, grammar, continuity, and AI
/// suggestions are excluded there, and for the same reason here.
///
/// Sampling is adaptive, not uniform: `weights(from:)` turns `WritingGrowthStore`'s cross-project
/// accept/decline history into a per-category bias, so practice leans toward categories the
/// writer keeps declining rather than whatever a given document happens to flag most. A writer
/// with no growth history yet -- or a category neither store has ever recorded a decision for --
/// gets plain uniform sampling by construction; see `weights(from:)` and `baselineWeight`.
enum SelfEditExerciseSampler {
    static let defaultCount = 5

    /// The sampling weight for a category with no recorded decisions (accepted or declined) at
    /// all, or when `weights` is left empty entirely -- every eligible category lands here, which
    /// is what makes sampling reduce to plain uniform selection until there's real growth history
    /// to weight against (the cold-start case `weights(from:)`'s own doc comment describes).
    static let baselineWeight = 0.2

    /// Turns cross-project growth history (`WritingGrowthStore.months`) into a per-category
    /// sampling weight for `sample(from:count:weights:using:)`: the higher a category's recorded
    /// decline rate, the more its own flagged passages are favored for practice, on the theory
    /// that a suggestion the writer keeps declining is closer to an unresolved habit than one
    /// they've already absorbed. A category with zero recorded decisions -- including every
    /// category, on a fresh install with no growth history yet -- gets exactly `baselineWeight`,
    /// the same floor every other category is guaranteed at minimum, so a strong category is never
    /// fully excluded and a brand-new writer sees plain uniform sampling by construction.
    static func weights(from growth: [WritingGrowthMonth]) -> [IssueCategory: Double] {
        let (accepted, declined) = decisionTotals(from: growth)
        return Dictionary(uniqueKeysWithValues: IssueCategory.allCases.map { category in
            let acceptedCount = accepted[category] ?? 0
            let declinedCount = declined[category] ?? 0
            let total = acceptedCount + declinedCount
            let declineRate = total > 0 ? Double(declinedCount) / Double(total) : 0
            return (category, baselineWeight + declineRate)
        })
    }

    /// Total accepted and declined decisions per category across every recorded month.
    private static func decisionTotals(
        from growth: [WritingGrowthMonth]
    ) -> (accepted: [IssueCategory: Int], declined: [IssueCategory: Int]) {
        var accepted: [IssueCategory: Int] = [:]
        var declined: [IssueCategory: Int] = [:]
        for month in growth {
            for (category, tally) in month.tallies {
                accepted[category, default: 0] += tally.accepted
                declined[category, default: 0] += tally.declined
            }
        }
        return (accepted, declined)
    }

    /// A category needs at least this many recorded decisions before it is named as a practice focus.
    static let focusMinimumDecisions = 3

    /// ...and the writer must decline at least this share of them.
    static let focusMinimumDeclineRate = 0.5

    /// The categories practice is leaning toward, for telling the writer *why* these exercises
    /// were chosen: the practiceable categories they decline most often, highest decline rate first
    /// (ties broken by more declines, then name, so the order never wobbles). Deliberately
    /// stricter than `weights(from:)`, which biases sampling from the very first decision: naming
    /// a focus on one or two data points would be claiming a pattern that isn't there yet.
    static func focusCategories(from growth: [WritingGrowthMonth], limit: Int = 2) -> [IssueCategory] {
        let (accepted, declined) = decisionTotals(from: growth)
        return IssueCategory.allCases
            .filter { $0.practicePrompt != nil }
            .compactMap { category -> (category: IssueCategory, rate: Double, declined: Int)? in
                let declinedCount = declined[category] ?? 0
                let total = (accepted[category] ?? 0) + declinedCount
                guard total >= focusMinimumDecisions else { return nil }
                let rate = Double(declinedCount) / Double(total)
                guard rate >= focusMinimumDeclineRate else { return nil }
                return (category, rate, declinedCount)
            }
            .sorted {
                if $0.rate != $1.rate { return $0.rate > $1.rate }
                if $0.declined != $1.declined { return $0.declined > $1.declined }
                return $0.category.rawValue < $1.category.rawValue
            }
            .prefix(limit)
            .map(\.category)
    }

    /// Weighted sampling without replacement (the Efraimidis-Spirakis exponential-key method):
    /// each candidate draws a uniform key raised to `1 / weight`, and the highest keys win. With
    /// equal weights for every category -- an empty `weights` dictionary, since a missing category
    /// falls back to `baselineWeight` for all of them alike -- this is mathematically identical to
    /// a plain uniform shuffle, since raising every key to the same power preserves their relative
    /// order; the two behaviors aren't separate code paths here, one is just a special case of the
    /// other.
    static func sample(
        from issues: [WritingIssue],
        count: Int = defaultCount,
        weights: [IssueCategory: Double] = [:],
        using generator: inout some RandomNumberGenerator
    ) -> [SelfEditExercise] {
        issues
            .filter { $0.category.practicePrompt != nil }
            .map { issue -> (issue: WritingIssue, key: Double) in
                let weight = weights[issue.category] ?? baselineWeight
                let u = Double.random(in: 0..<1, using: &generator)
                return (issue, pow(u, 1.0 / weight))
            }
            .sorted { $0.key > $1.key }
            .prefix(count)
            .map { SelfEditExercise(issue: $0.issue) }
    }

    static func sample(
        from issues: [WritingIssue],
        count: Int = defaultCount,
        weights: [IssueCategory: Double] = [:]
    ) -> [SelfEditExercise] {
        var generator = SystemRandomNumberGenerator()
        return sample(from: issues, count: count, weights: weights, using: &generator)
    }
}
