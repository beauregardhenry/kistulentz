import Foundation
import XCTest
@testable import Kistulentz

final class AtomicFileWriterTests: XCTestCase {
    func testCreatesAndReplacesCompleteFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("project.json")

        try AtomicFileWriter.write(data: Data("first".utf8), to: destination)
        try AtomicFileWriter.write(text: "second", to: destination)

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "second")
        XCTAssertTrue(try temporaryWrites(in: root).isEmpty)
    }

    func testDiskFullDuringStagingLeavesCurrentFileUntouched() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("project.json")
        try Data("known-good".utf8).write(to: destination)
        let diskFull = NSError(domain: NSPOSIXErrorDomain, code: 28)
        let writer = AtomicFileWriter(operations: .init(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            stage: { _, _ in throw diskFull },
            commit: { _, _, _ in XCTFail("A failed stage must never reach commit.") },
            remove: { _ in XCTFail("No staged file exists to remove.") }
        ))

        XCTAssertThrowsError(try writer.write(data: Data("new".utf8), to: destination))

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "known-good")
        XCTAssertTrue(try temporaryWrites(in: root).isEmpty)
    }

    func testInterruptedCommitLeavesCurrentFileAndCleansTheStagedCopy() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("project.json")
        try Data("known-good".utf8).write(to: destination)
        let interrupted = NSError(domain: NSPOSIXErrorDomain, code: 5)
        let writer = AtomicFileWriter(operations: .init(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            stage: { data, url in try data.write(to: url) },
            commit: { _, _, _ in throw interrupted },
            remove: { try FileManager.default.removeItem(at: $0) }
        ))

        XCTAssertThrowsError(try writer.write(data: Data("new".utf8), to: destination))

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "known-good")
        XCTAssertTrue(try temporaryWrites(in: root).isEmpty)
    }

    func testCleanupFailureReportsBothCommitAndCleanupReasons() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("project.json")
        try Data("known-good".utf8).write(to: destination)
        let writer = AtomicFileWriter(operations: .init(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            stage: { data, url in try data.write(to: url) },
            commit: { _, _, _ in throw SampleError.commit },
            remove: { _ in throw SampleError.cleanup }
        ))

        XCTAssertThrowsError(try writer.write(data: Data("new".utf8), to: destination)) { error in
            guard case AtomicFileWriteError.commitFailedAndCleanupIncomplete(let commit, let cleanup) = error else {
                return XCTFail("Expected both failures, got \(error).")
            }
            XCTAssertTrue(commit.contains("commit failed"))
            XCTAssertTrue(cleanup.contains("cleanup failed"))
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "known-good")
    }

    func testRefusesToReplaceDirectoriesAndSymbolicLinks() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.txt")
        let link = root.appendingPathComponent("link.txt")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        for destination in [folder, link] {
            XCTAssertThrowsError(try AtomicFileWriter.write(data: Data("new".utf8), to: destination)) { error in
                XCTAssertEqual(error as? AtomicFileWriteError, .unsafeDestination)
            }
        }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target")
    }

    private enum SampleError: LocalizedError {
        case commit
        case cleanup

        var errorDescription: String? {
            switch self {
            case .commit: "commit failed"
            case .cleanup: "cleanup failed"
            }
        }
    }

    private func temporaryWrites(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix(".Kistulentz-write-")
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-AtomicFileWriter-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
