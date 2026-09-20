import XCTest
@testable import Kistulentz

/// A fixed-seed generator so sampling tests are reproducible instead of depending on the real
/// system RNG -- the tests care that `sample` behaves correctly given whatever order `shuffled`
/// produces, not that any particular order comes out.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// Tests for `SelfEditExerciseSampler` (#92) -- the sampling logic behind Self-Edit Exercises.
/// Issue #92's central acceptance criterion is that exercises are drawn only from issues already
/// flagged in the current project, never invented or fetched, so most of these tests check that
/// every sampled exercise's issue traces back to the input pool.
final class SelfEditExerciseSamplerTests: XCTestCase {
    private func issue(
        category: IssueCategory,
        excerpt: String = "excerpt",
        replacement: String? = nil
    ) -> WritingIssue {
        WritingIssue(
            category: category,
            range: NSRange(location: 0, length: excerpt.count),
            excerpt: excerpt,
            message: "message",
            replacement: replacement
        )
    }

    func testSampleNeverInventsAnIssueOutsideTheProvidedPool() {
        let pool = [
            issue(category: .adverb),
            issue(category: .passiveVoice),
            issue(category: .complexPhrase, replacement: "simpler")
        ]
        var generator = SeededGenerator(state: 1)

        let sample = SelfEditExerciseSampler.sample(from: pool, count: 5, using: &generator)

        let poolIDs = Set(pool.map(\.id))
        for exercise in sample {
            XCTAssertTrue(poolIDs.contains(exercise.issue.id))
        }
    }

    func testSampleExcludesCategoriesWithoutAPracticePrompt() {
        let pool = [
            issue(category: .spelling),
            issue(category: .grammar),
            issue(category: .continuity),
            issue(category: .aiSuggestion),
            issue(category: .adverb)
        ]
        var generator = SeededGenerator(state: 2)

        let sample = SelfEditExerciseSampler.sample(from: pool, count: 10, using: &generator)

        XCTAssertEqual(sample.map(\.issue.category), [.adverb])
    }

    func testSampleIsEmptyWhenThePoolHasNoPracticeWorthyIssues() {
        let pool = [issue(category: .spelling), issue(category: .grammar), issue(category: .continuity)]
        var generator = SeededGenerator(state: 3)

        let sample = SelfEditExerciseSampler.sample(from: pool, count: 5, using: &generator)

        XCTAssertTrue(sample.isEmpty)
    }

    func testSampleRespectsARequestedCountSmallerThanThePool() {
        let pool = (0..<10).map { _ in issue(category: .adverb) }
        var generator = SeededGenerator(state: 4)

        let sample = SelfEditExerciseSampler.sample(from: pool, count: 3, using: &generator)

        XCTAssertEqual(sample.count, 3)
    }

    func testSampleReturnsEveryEligibleIssueWhenThePoolIsSmallerThanTheRequestedCount() {
        let pool = [issue(category: .adverb), issue(category: .passiveVoice)]
        var generator = SeededGenerator(state: 5)

        let sample = SelfEditExerciseSampler.sample(from: pool, count: 5, using: &generator)

        XCTAssertEqual(sample.count, 2)
    }

    func testSampleIsReproducibleForTheSameSeed() {
        let pool = (0..<20).map { index in issue(category: .adverb, excerpt: "word\(index)") }

        var firstGenerator = SeededGenerator(state: 42)
        let firstSample = SelfEditExerciseSampler.sample(from: pool, count: 5, using: &firstGenerator)

        var secondGenerator = SeededGenerator(state: 42)
        let secondSample = SelfEditExerciseSampler.sample(from: pool, count: 5, using: &secondGenerator)

        XCTAssertEqual(firstSample, secondSample)
    }

    /// Declining or skipping an exercise must have no effect on the underlying flag (issue #92's
    /// acceptance criterion) -- sampling itself never mutates or filters the source array in place.
    func testSamplingDoesNotMutateTheSourcePool() {
        let pool = [issue(category: .adverb), issue(category: .passiveVoice), issue(category: .complexPhrase)]
        let poolCopy = pool
        var generator = SeededGenerator(state: 6)

        _ = SelfEditExerciseSampler.sample(from: pool, count: 2, using: &generator)

        XCTAssertEqual(pool, poolCopy)
    }
}
