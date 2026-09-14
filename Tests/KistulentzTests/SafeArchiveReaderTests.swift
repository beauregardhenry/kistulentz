import Foundation
import XCTest
@testable import Kistulentz

final class SafeArchiveReaderTests: XCTestCase {
    func testInspectsReadsAndExtractsAValidArchive() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("A safe document.".utf8).write(to: package.appendingPathComponent("document.txt"))
        let archive = root.appendingPathComponent("document.zip")
        try zip(["-Xqr", archive.path, "document.txt"], in: package)

        let inspection = try SafeArchiveReader.inspect(archive, policy: generousPolicy)
        let data = try XCTUnwrap(SafeArchiveReader.data(
            for: "document.txt",
            in: archive,
            inspection: inspection
        ))
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try SafeArchiveReader.extract(
            archive,
            to: extracted,
            inspection: inspection,
            policy: generousPolicy
        )

        XCTAssertEqual(inspection.paths, ["document.txt"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "A safe document.")
        XCTAssertEqual(
            try String(contentsOf: extracted.appendingPathComponent("document.txt"), encoding: .utf8),
            "A safe document."
        )
    }

    func testRejectsParentTraversalBeforeExtraction() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        let nested = package.appendingPathComponent("xx", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: nested.appendingPathComponent("secret.txt"))
        let archive = root.appendingPathComponent("traversal.zip")
        try zip(["-Xqr", archive.path, "xx"], in: package)
        try replaceBytes(in: archive, matching: "xx/", with: "../")

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: generousPolicy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .unsafeArchive)
        }
    }

    func testRejectsCaseInsensitiveFilenameCollisions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: package.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: package.appendingPathComponent("two.txt"))
        let archive = root.appendingPathComponent("collision.zip")
        try zip(["-Xq", archive.path, "one.txt", "two.txt"], in: package)
        try replaceBytes(in: archive, matching: "two.txt", with: "ONE.txt")

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: generousPolicy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .unsafeArchive)
        }
    }

    func testRejectsSymbolicLinksBeforeExtraction() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: package.appendingPathComponent("target.txt"))
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent("link.txt"),
            withDestinationURL: package.appendingPathComponent("target.txt")
        )
        let archive = root.appendingPathComponent("symlink.zip")
        try zip(["-Xqry", archive.path, "link.txt"], in: package)

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: generousPolicy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .unsafeArchive)
        }
    }

    func testRejectsAnEntryOverThePerFileLimit() throws {
        let archive = try archiveContaining(byteCount: 32)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let policy = ArchiveSafetyPolicy(
            maximumArchiveBytes: 1_000_000,
            maximumEntries: 10,
            maximumEntryBytes: 16,
            maximumExtractedBytes: 1_000,
            maximumCompressionRatio: 1_000,
            maximumPathBytes: 100
        )

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: policy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .entryTooLarge)
        }
    }

    func testRejectsMoreEntriesThanThePolicyAllows() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: package.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: package.appendingPathComponent("two.txt"))
        let archive = root.appendingPathComponent("too-many.zip")
        try zip(["-Xq", archive.path, "one.txt", "two.txt"], in: package)
        let policy = ArchiveSafetyPolicy(
            maximumArchiveBytes: 1_000_000,
            maximumEntries: 1,
            maximumEntryBytes: 100,
            maximumExtractedBytes: 1_000,
            maximumCompressionRatio: 1_000,
            maximumPathBytes: 100
        )

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: policy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .unsafeArchive)
        }
    }

    func testExtractionAllowsImplicitParentDirectoriesWithinTheHardLimit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package", isDirectory: true)
        let nested = package.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("document".utf8).write(to: nested.appendingPathComponent("document.txt"))
        let archive = root.appendingPathComponent("implicit-directory.zip")
        try zip(["-Xq", archive.path, "nested/document.txt"], in: package)

        let inspection = try SafeArchiveReader.inspect(archive, policy: generousPolicy)
        XCTAssertEqual(inspection.entries.count, 1)
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try SafeArchiveReader.extract(
            archive,
            to: extracted,
            inspection: inspection,
            policy: generousPolicy
        )

        XCTAssertEqual(
            try String(contentsOf: extracted.appendingPathComponent("nested/document.txt"), encoding: .utf8),
            "document"
        )
    }

    func testRejectsAnArchiveOverTheTotalExpandedLimit() throws {
        let archive = try archiveContaining(byteCount: 32)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let policy = ArchiveSafetyPolicy(
            maximumArchiveBytes: 1_000_000,
            maximumEntries: 10,
            maximumEntryBytes: 100,
            maximumExtractedBytes: 16,
            maximumCompressionRatio: 1_000,
            maximumPathBytes: 100
        )

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: policy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .archiveTooLarge)
        }
    }

    func testRejectsExtremeCompressionRatios() throws {
        let archive = try archiveContaining(byteCount: 100_000)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let policy = ArchiveSafetyPolicy(
            maximumArchiveBytes: 1_000_000,
            maximumEntries: 10,
            maximumEntryBytes: 200_000,
            maximumExtractedBytes: 200_000,
            maximumCompressionRatio: 2,
            maximumPathBytes: 100
        )

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: policy)) { error in
            XCTAssertEqual(error as? ArchiveSafetyError, .unsafeArchive)
        }
    }

    func testRejectsTruncatedArchiveMetadata() throws {
        let archive = try archiveContaining(byteCount: 32)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        var bytes = try Data(contentsOf: archive)
        bytes.removeLast(min(32, bytes.count))
        try bytes.write(to: archive, options: .atomic)

        XCTAssertThrowsError(try SafeArchiveReader.inspect(archive, policy: generousPolicy))
    }

    private var generousPolicy: ArchiveSafetyPolicy {
        ArchiveSafetyPolicy(
            maximumArchiveBytes: 1_000_000,
            maximumEntries: 100,
            maximumEntryBytes: 500_000,
            maximumExtractedBytes: 1_000_000,
            maximumCompressionRatio: 1_000,
            maximumPathBytes: 1_024
        )
    }

    private func archiveContaining(byteCount: Int) throws -> URL {
        let root = try temporaryDirectory()
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 65, count: byteCount).write(to: package.appendingPathComponent("payload.txt"))
        let archive = root.appendingPathComponent("payload.zip")
        try zip(["-Xq9", archive.path, "payload.txt"], in: package)
        return archive
    }

    private func replaceBytes(in url: URL, matching original: String, with replacement: String) throws {
        XCTAssertEqual(original.utf8.count, replacement.utf8.count)
        var bytes = try Data(contentsOf: url)
        let originalBytes = Data(original.utf8)
        let replacementBytes = Data(replacement.utf8)
        var searchStart = bytes.startIndex
        var count = 0
        while let range = bytes.range(of: originalBytes, in: searchStart..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: replacementBytes)
            searchStart = range.lowerBound + replacementBytes.count
            count += 1
        }
        XCTAssertGreaterThan(count, 0)
        try bytes.write(to: url, options: .atomic)
    }

    private func zip(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-SafeArchiveReader-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
