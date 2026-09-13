import XCTest
@testable import Kistulentz

final class RollbackTrackerTests: XCTestCase {
    private enum StepError: Error { case boom }
    private enum EscalatedError: Error, Equatable {
        case escalated(originalReason: String, rollbackReason: String)
    }

    func testRethrowsTheOriginalErrorUncalteredWhenEveryStepSucceeds() {
        var ran: [String] = []

        XCTAssertThrowsError(
            try RollbackTracker.run(
                after: SampleError.original,
                steps: [
                    ("first", { ran.append("first") }),
                    ("second", { ran.append("second") })
                ]
            ) { originalReason, rollbackReason in
                XCTFail("escalate should not be called when every step succeeds")
                return EscalatedError.escalated(originalReason: originalReason, rollbackReason: rollbackReason)
            }
        ) { error in
            guard case SampleError.original = error else {
                return XCTFail("Expected the original error, got \(error)")
            }
        }
        XCTAssertEqual(ran, ["first", "second"])
    }

    func testEscalatesAndNamesEveryFailingStepWhenAnyStepThrows() {
        var ran: [String] = []

        XCTAssertThrowsError(
            try RollbackTracker.run(
                after: SampleError.original,
                steps: [
                    ("first", { ran.append("first") }),
                    ("second", { throw StepError.boom }),
                    ("third", { throw StepError.boom })
                ]
            ) { originalReason, rollbackReason in
                EscalatedError.escalated(originalReason: originalReason, rollbackReason: rollbackReason)
            }
        ) { error in
            guard case EscalatedError.escalated(let originalReason, let rollbackReason) = error else {
                return XCTFail("Expected an escalated error, got \(error)")
            }
            XCTAssertEqual(originalReason, SampleError.original.localizedDescription)
            XCTAssertTrue(rollbackReason.contains("second"))
            XCTAssertTrue(rollbackReason.contains("third"))
            XCTAssertFalse(rollbackReason.contains("first"), "A step that succeeded shouldn't appear in the failure list.")
        }
        // Every step still runs even after an earlier one fails -- rollback isn't abandoned
        // partway through just because one step couldn't complete.
        XCTAssertEqual(ran, ["first"])
    }

    private enum SampleError: LocalizedError, Equatable {
        case original
        var errorDescription: String? { "the original operation failed" }
    }
}
