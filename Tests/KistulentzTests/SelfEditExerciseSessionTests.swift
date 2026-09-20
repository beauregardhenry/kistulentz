import XCTest
@testable import Kistulentz

/// Tests for `SelfEditExerciseSession` (#92) -- the navigation and per-exercise attempt/reveal
/// state behind `SelfEditExerciseView`, extracted from the view itself specifically so this logic
/// is reachable from a fast unit test instead of only a UI test.
@MainActor
final class SelfEditExerciseSessionTests: XCTestCase {
    private func exercise(excerpt: String = "excerpt") -> SelfEditExercise {
        SelfEditExercise(issue: WritingIssue(
            category: .adverb,
            range: NSRange(location: 0, length: excerpt.count),
            excerpt: excerpt,
            message: "message"
        ))
    }

    func testCurrentIsNilWhenThereAreNoExercises() {
        let session = SelfEditExerciseSession(exercises: [])

        XCTAssertNil(session.current)
    }

    func testCurrentStartsAtTheFirstExercise() {
        let first = exercise(excerpt: "first")
        let second = exercise(excerpt: "second")
        let session = SelfEditExerciseSession(exercises: [first, second])

        XCTAssertEqual(session.current, first)
    }

    func testGoToNextAdvancesToTheNextExercise() {
        let first = exercise(excerpt: "first")
        let second = exercise(excerpt: "second")
        let session = SelfEditExerciseSession(exercises: [first, second])

        session.goToNext()

        XCTAssertEqual(session.current, second)
        XCTAssertEqual(session.index, 1)
    }

    func testGoToNextDoesNothingAtTheLastExercise() {
        let session = SelfEditExerciseSession(exercises: [exercise()])

        session.goToNext()

        XCTAssertEqual(session.index, 0)
    }

    func testGoToPreviousDoesNothingAtTheFirstExercise() {
        let session = SelfEditExerciseSession(exercises: [exercise(), exercise()])

        session.goToPrevious()

        XCTAssertEqual(session.index, 0)
    }

    func testGoToPreviousReturnsToAnEarlierExerciseAfterAdvancing() {
        let first = exercise(excerpt: "first")
        let session = SelfEditExerciseSession(exercises: [first, exercise(excerpt: "second")])
        session.goToNext()

        session.goToPrevious()

        XCTAssertEqual(session.current, first)
        XCTAssertEqual(session.index, 0)
    }

    func testIsAtLastExerciseWhenThereAreNoExercises() {
        // No exercise to be "at", but nothing left to advance to either -- the view uses this to
        // decide whether its Next/Finish button would have anywhere to go.
        let session = SelfEditExerciseSession(exercises: [])

        XCTAssertTrue(session.isAtLastExercise)
    }

    func testIsAtLastExerciseBecomesTrueOnlyAfterReachingTheEnd() {
        let session = SelfEditExerciseSession(exercises: [exercise(), exercise(), exercise()])

        XCTAssertFalse(session.isAtLastExercise)
        session.goToNext()
        XCTAssertFalse(session.isAtLastExercise)
        session.goToNext()
        XCTAssertTrue(session.isAtLastExercise)
    }

    func testAttemptDefaultsToEmptyStringUntilSet() {
        let target = exercise()
        let session = SelfEditExerciseSession(exercises: [target])

        XCTAssertEqual(session.attempt(for: target), "")
    }

    func testSetAttemptPersistsWhatWasTyped() {
        let target = exercise()
        let session = SelfEditExerciseSession(exercises: [target])

        session.setAttempt("because", for: target)

        XCTAssertEqual(session.attempt(for: target), "because")
    }

    /// The acceptance criterion this protects: navigating away and back must never lose or mix up
    /// an in-progress attempt from a different exercise.
    func testAttemptsAreKeptSeparatePerExercise() {
        let first = exercise(excerpt: "first")
        let second = exercise(excerpt: "second")
        let session = SelfEditExerciseSession(exercises: [first, second])

        session.setAttempt("first attempt", for: first)
        session.setAttempt("second attempt", for: second)

        XCTAssertEqual(session.attempt(for: first), "first attempt")
        XCTAssertEqual(session.attempt(for: second), "second attempt")
    }

    func testRevealDefaultsToFalseUntilRevealed() {
        let target = exercise()
        let session = SelfEditExerciseSession(exercises: [target])

        XCTAssertFalse(session.isRevealed(target))
    }

    func testRevealMarksOnlyTheRevealedExercise() {
        let first = exercise(excerpt: "first")
        let second = exercise(excerpt: "second")
        let session = SelfEditExerciseSession(exercises: [first, second])

        session.reveal(first)

        XCTAssertTrue(session.isRevealed(first))
        XCTAssertFalse(session.isRevealed(second))
    }
}
