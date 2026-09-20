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
enum SelfEditExerciseSampler {
    static let defaultCount = 5

    static func sample(
        from issues: [WritingIssue],
        count: Int = defaultCount,
        using generator: inout some RandomNumberGenerator
    ) -> [SelfEditExercise] {
        issues
            .filter { $0.category.practicePrompt != nil }
            .shuffled(using: &generator)
            .prefix(count)
            .map(SelfEditExercise.init)
    }

    static func sample(from issues: [WritingIssue], count: Int = defaultCount) -> [SelfEditExercise] {
        var generator = SystemRandomNumberGenerator()
        return sample(from: issues, count: count, using: &generator)
    }
}
