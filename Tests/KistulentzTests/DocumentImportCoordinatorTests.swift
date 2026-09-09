import XCTest
@testable import Kistulentz

final class DocumentImportCoordinatorTests: XCTestCase {
    @MainActor
    func testDefaultCoordinatorLoadsClearsAndSavesARealPlainTextDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KistulentzDocumentImportCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let output = root.appendingPathComponent("imported.md")
        try "Imported plain text".write(to: source, atomically: true, encoding: .utf8)
        let coordinator = DocumentImportCoordinator()

        coordinator.load(from: source)
        try await waitUntil { !coordinator.isRunning }
        let draft = try XCTUnwrap(coordinator.draft)
        XCTAssertEqual(draft.templateMarkdown, "Imported plain text")

        coordinator.clearDraft()
        XCTAssertNil(coordinator.draft)

        var saveResult: DocumentImportSaveResult?
        coordinator.save(draft, decisions: [:], to: output) { result in
            saveResult = result
        }
        try await waitUntil { !coordinator.isRunning }

        XCTAssertEqual(saveResult?.markdownURL, output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "Imported plain text\n")
        XCTAssertNil(coordinator.errorMessage)
    }

    @MainActor
    func testNewLoadSupersedesASlowerPreviousLoad() async throws {
        let slow = URL(fileURLWithPath: "/tmp/slow.txt")
        let newest = URL(fileURLWithPath: "/tmp/newest.txt")
        let coordinator = DocumentImportCoordinator(loader: { url in
            if url == slow {
                try await Task.sleep(for: .milliseconds(150))
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
            return Self.draft(for: url)
        })

        coordinator.load(from: slow)
        try await Task.sleep(for: .milliseconds(10))
        coordinator.load(from: newest)
        try await waitUntil { !coordinator.isRunning }

        XCTAssertEqual(coordinator.draft?.sourceURL, newest)
        XCTAssertNil(coordinator.errorMessage)
    }

    @MainActor
    func testCancelPreventsACompletedLoadFromPublishing() async throws {
        let coordinator = DocumentImportCoordinator(loader: { url in
            try await Task.sleep(for: .milliseconds(80))
            return Self.draft(for: url)
        })

        coordinator.load(from: URL(fileURLWithPath: "/tmp/cancelled.txt"))
        XCTAssertTrue(coordinator.isRunning)
        coordinator.cancel()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(coordinator.isRunning)
        XCTAssertNil(coordinator.draft)
        XCTAssertNil(coordinator.errorMessage)
    }

    @MainActor
    func testSaveFailureClearsProgressAndReportsTheError() async throws {
        let source = URL(fileURLWithPath: "/tmp/source.txt")
        var didComplete = false
        let coordinator = DocumentImportCoordinator(
            loader: { Self.draft(for: $0) },
            saver: { _, _, _ in throw ExpectedDocumentImportError.failed }
        )
        let draft = Self.draft(for: source)
        coordinator.draft = draft

        coordinator.save(
            draft,
            decisions: [:],
            to: URL(fileURLWithPath: "/tmp/output.md")
        ) { _ in
            didComplete = true
        }
        try await waitUntil { !coordinator.isRunning }

        XCTAssertNil(coordinator.draft)
        XCTAssertFalse(didComplete)
        XCTAssertEqual(
            coordinator.errorMessage,
            ExpectedDocumentImportError.failed.localizedDescription
        )
    }

    private static func draft(for url: URL) -> DocumentImportDraft {
        DocumentImportDraft(
            sourceURL: url,
            format: .plainText,
            templateMarkdown: "Imported text\n"
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw ExpectedDocumentImportError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum ExpectedDocumentImportError: LocalizedError {
    case failed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .failed: "Expected document-import failure."
        case .timedOut: "Timed out waiting for document-import state."
        }
    }
}
