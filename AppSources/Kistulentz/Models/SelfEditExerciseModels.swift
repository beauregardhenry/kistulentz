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
        var accepted: [IssueCategory: Int] = [:]
        var declined: [IssueCategory: Int] = [:]
        for month in growth {
            for (category, tally) in month.tallies {
                accepted[category, default: 0] += tally.accepted
                declined[category, default: 0] += tally.declined
            }
        }
        return Dictionary(uniqueKeysWithValues: IssueCategory.allCases.map { category in
            let acceptedCount = accepted[category] ?? 0
            let declinedCount = declined[category] ?? 0
            let total = acceptedCount + declinedCount
            let declineRate = total > 0 ? Double(declinedCount) / Double(total) : 0
            return (category, baselineWeight + declineRate)
        })
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
