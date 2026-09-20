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

    /// With a large enough weight gap, the heavily-weighted category should win a clear majority
    /// of single-item draws across many independent seeds -- the property that makes practice
    /// actually adaptive rather than a coincidence of one lucky sample.
    func testSampleFavorsACategoryWithAMuchHigherWeight() {
        let weak = issue(category: .adverb)
        let strong = issue(category: .passiveVoice)
        let weights: [IssueCategory: Double] = [.adverb: 5.0, .passiveVoice: 0.1]
        let trials = 200
        var weakPicks = 0

        for seed in 1...trials {
            var generator = SeededGenerator(state: UInt64(seed))
            let sample = SelfEditExerciseSampler.sample(
                from: [weak, strong],
                count: 1,
                weights: weights,
                using: &generator
            )
            if sample.first?.issue.category == .adverb {
                weakPicks += 1
            }
        }

        XCTAssertGreaterThan(weakPicks, trials * 3 / 4)
    }

    /// Equal weights for every category -- including an empty `weights` dictionary, since a
    /// missing category falls back to the same baseline weight as every other -- must reduce to
    /// plain uniform sampling: the cold-start guarantee `weights(from:)` depends on.
    func testSampleWithEqualWeightsMatchesUnweightedSampling() {
        let pool = (0..<20).map { index in issue(category: .adverb, excerpt: "word\(index)") }
        let equalWeights: [IssueCategory: Double] = [.adverb: SelfEditExerciseSampler.baselineWeight]

        var unweightedGenerator = SeededGenerator(state: 7)
        let unweightedSample = SelfEditExerciseSampler.sample(from: pool, count: 5, using: &unweightedGenerator)

        var weightedGenerator = SeededGenerator(state: 7)
        let weightedSample = SelfEditExerciseSampler.sample(
            from: pool,
            count: 5,
            weights: equalWeights,
            using: &weightedGenerator
        )

        XCTAssertEqual(unweightedSample, weightedSample)
    }
}

/// Tests for `SelfEditExerciseSampler.weights(from:)` -- turning cross-project growth history
/// into per-category sampling weights, so practice is biased toward categories the writer keeps
/// declining rather than sampled uniformly at random.
final class SelfEditExerciseWeightsTests: XCTestCase {
    private func month(key: String = "2026-01", tallies: [IssueCategory: WritingGrowthTally]) -> WritingGrowthMonth {
        WritingGrowthMonth(key: key, tallies: tallies)
    }

    func testEveryCategoryGetsTheBaselineWeightWithNoGrowthHistoryAtAll() {
        let weights = SelfEditExerciseSampler.weights(from: [])

        for category in IssueCategory.allCases {
            XCTAssertEqual(weights[category], SelfEditExerciseSampler.baselineWeight)
        }
    }

    func testACategoryWithNoRecordedDecisionsGetsTheBaselineWeight() {
        let growth = [month(tallies: [.adverb: WritingGrowthTally(accepted: 3, declined: 0)])]

        let weights = SelfEditExerciseSampler.weights(from: growth)

        XCTAssertEqual(weights[.passiveVoice], SelfEditExerciseSampler.baselineWeight)
    }

    func testACategoryThatIsAlwaysAcceptedStaysAtTheBaselineWeight() {
        let growth = [month(tallies: [.adverb: WritingGrowthTally(accepted: 10, declined: 0)])]

        let weights = SelfEditExerciseSampler.weights(from: growth)

        XCTAssertEqual(weights[.adverb], SelfEditExerciseSampler.baselineWeight)
    }

    func testACategoryThatIsAlwaysDeclinedGetsTheMaximumWeight() {
        let growth = [month(tallies: [.adverb: WritingGrowthTally(accepted: 0, declined: 10)])]

        let weights = SelfEditExerciseSampler.weights(from: growth)

        XCTAssertEqual(weights[.adverb], SelfEditExerciseSampler.baselineWeight + 1.0)
    }

    func testAMixedDeclineRateLandsBetweenTheBaselineAndTheMaximum() {
        let growth = [month(tallies: [.adverb: WritingGrowthTally(accepted: 3, declined: 1)])]

        let weights = SelfEditExerciseSampler.weights(from: growth)

        XCTAssertEqual(weights[.adverb], SelfEditExerciseSampler.baselineWeight + 0.25)
    }

    func testDecisionsAcrossMultipleMonthsAreCombinedForTheSameCategory() {
        let growth = [
            month(key: "2026-01", tallies: [.adverb: WritingGrowthTally(accepted: 0, declined: 1)]),
            month(key: "2026-02", tallies: [.adverb: WritingGrowthTally(accepted: 0, declined: 1)])
        ]

        let weights = SelfEditExerciseSampler.weights(from: growth)

        XCTAssertEqual(weights[.adverb], SelfEditExerciseSampler.baselineWeight + 1.0)
    }

    func testCategoriesAreWeightedIndependentlyOfEachOther() {
        let growth = [month(tallies: [
            .adverb: WritingGrowthTally(accepted: 0, declined: 5),
            .passiveVoice: WritingGrowthTally(accepted: 5, declined: 0)
        ])]

        let weights = SelfEditExerciseSampler.weights(from: growth)

        XCTAssertEqual(weights[.adverb], SelfEditExerciseSampler.baselineWeight + 1.0)
        XCTAssertEqual(weights[.passiveVoice], SelfEditExerciseSampler.baselineWeight)
    }
}
