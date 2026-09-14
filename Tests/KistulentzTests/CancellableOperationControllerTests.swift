import XCTest
@testable import Kistulentz

@MainActor
final class CancellableOperationControllerTests: XCTestCase {
    func testStartingNewWorkCancelsAndInvalidatesThePreviousOperation() async throws {
        let controller = CancellableOperationController()
        var firstAccepted = false
        var secondAccepted = false

        let first = controller.start { token in
            try? await Task.sleep(for: .milliseconds(80))
            firstAccepted = controller.accepts(token)
        }
        try await Task.sleep(for: .milliseconds(5))
        let second = controller.start { token in
            secondAccepted = controller.accepts(token)
            _ = controller.finish(token)
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(controller.accepts(first))
        XCTAssertFalse(firstAccepted)
        XCTAssertTrue(secondAccepted)
        XCTAssertFalse(controller.accepts(second))
        XCTAssertFalse(controller.isRunning)
    }

    func testCancelImmediatelyInvalidatesTheTokenAndCancelsTheTask() async throws {
        let controller = CancellableOperationController()
        var observedCancellation = false
        let token = controller.start { _ in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                observedCancellation = true
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertTrue(controller.isRunning)
        XCTAssertTrue(controller.cancel())
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(observedCancellation)
        XCTAssertFalse(controller.accepts(token))
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.cancel())
    }

    func testOnlyTheCurrentTokenCanFinishTheOperation() {
        let controller = CancellableOperationController()
        let token = controller.start { _ in }
        let unrelatedController = CancellableOperationController()
        let unrelated = unrelatedController.start { _ in }

        XCTAssertFalse(controller.finish(unrelated))
        XCTAssertTrue(controller.isRunning)
        XCTAssertTrue(controller.finish(token))
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.finish(token))
        unrelatedController.cancel()
    }
}
