import AppKit
import CoreText
import XCTest
@testable import Kistulentz

/// Every test here registers real fonts through Core Text -- there's no way to verify this
/// feature meaningfully without doing so -- but always at `.process` scope, so nothing survives
/// past the test run and nothing ever reaches the `.persistent`, system-wide registration a real
/// user's "Add Font File" click uses. `CustomFontDisk`/`CustomFontStore` take that scope as a
/// parameter specifically so tests can make this guarantee.
final class CustomFontTests: XCTestCase {
    private let testScope: CTFontManagerScope = .process

    func testAddFontCopiesRegistersAndPersistsARecord() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try copiedFixtureFont(named: "Chalkduster.ttf", into: root)

        let record = try CustomFontDisk.addFont(from: source, at: root, scope: testScope)

        XCTAssertEqual(record.familyName, "Chalkduster")
        XCTAssertEqual(record.originalFilename, "Chalkduster.ttf")
        XCTAssertTrue(NSFontManager.shared.availableFontFamilies.contains("Chalkduster"))
        let storedURL = root.appendingPathComponent("Files").appendingPathComponent(record.storedFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        // Compare by id/familyName rather than full Equatable: `.iso8601` date encoding drops
        // sub-second precision, so `addedAt` on a record just reloaded from disk can legitimately
        // differ from the in-memory value by a fraction of a second -- not a sign anything is
        // actually wrong.
        let manifest = try CustomFontDisk.loadManifest(at: root)
        XCTAssertEqual(manifest.fonts.map(\.id), [record.id])
        XCTAssertEqual(manifest.fonts.map(\.familyName), [record.familyName])
    }

    func testAddFontRejectsAFileThatIsNotARealFont() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeFont = root.appendingPathComponent("Not-A-Font.ttf")
        try "definitely not font data".write(to: fakeFont, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try CustomFontDisk.addFont(from: fakeFont, at: root, scope: testScope)) { error in
            guard case CustomFontError.invalidFontFile = error else {
                return XCTFail("Expected invalidFontFile, got \(error)")
            }
        }
        let manifest = try CustomFontDisk.loadManifest(at: root)
        XCTAssertTrue(manifest.fonts.isEmpty)
    }

    func testAddingTheSameFontFamilyTwiceReturnsTheExistingRecordRatherThanDuplicating() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try copiedFixtureFont(named: "Chalkduster.ttf", into: root, subdirectory: "first")
        let second = try copiedFixtureFont(named: "Chalkduster.ttf", into: root, subdirectory: "second")

        let firstRecord = try CustomFontDisk.addFont(from: first, at: root, scope: testScope)
        let secondRecord = try CustomFontDisk.addFont(from: second, at: root, scope: testScope)

        // Same reasoning as the round-trip comparison above: `addedAt` isn't part of what "the
        // same record" means here, just id/familyName.
        XCTAssertEqual(firstRecord.id, secondRecord.id)
        XCTAssertEqual(firstRecord.familyName, secondRecord.familyName)
        let manifest = try CustomFontDisk.loadManifest(at: root)
        XCTAssertEqual(manifest.fonts.count, 1)
    }

    func testRemoveFontDeletesTheManagedCopyAndTheManifestEntry() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try copiedFixtureFont(named: "Chalkduster.ttf", into: root)
        let record = try CustomFontDisk.addFont(from: source, at: root, scope: testScope)
        let storedURL = root.appendingPathComponent("Files").appendingPathComponent(record.storedFilename)

        try CustomFontDisk.removeFont(record, at: root, scope: testScope)

        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        let manifest = try CustomFontDisk.loadManifest(at: root)
        XCTAssertTrue(manifest.fonts.isEmpty)
    }

    func testRemoveFontThrowsWhenTheRecordIsNoLongerInTheManifest() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let phantom = CustomFontRecord(familyName: "Nonexistent", originalFilename: "x.ttf", storedFilename: "x.ttf")

        XCTAssertThrowsError(try CustomFontDisk.removeFont(phantom, at: root, scope: testScope)) { error in
            guard case CustomFontError.missingFont = error else {
                return XCTFail("Expected missingFont, got \(error)")
            }
        }
    }

    func testRegisterAllIsIdempotentAndSkipsAlreadyAvailableFamilies() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try copiedFixtureFont(named: "Chalkduster.ttf", into: root)
        _ = try CustomFontDisk.addFont(from: source, at: root, scope: testScope)

        let results = CustomFontDisk.registerAll(at: root, scope: testScope)

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].failureReason)
    }

    @MainActor
    func testStoreAddAndRemoveUpdatePublishedFonts() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try copiedFixtureFont(named: "Chalkduster.ttf", into: root)
        let store = CustomFontStore(rootURL: root, scope: testScope)
        XCTAssertTrue(store.fonts.isEmpty)

        store.addFont(from: source)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.fonts.map(\.familyName), ["Chalkduster"])

        let added = try XCTUnwrap(store.fonts.first)
        store.removeFont(added)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.fonts.isEmpty)
    }

    @MainActor
    func testStoreSurfacesAnErrorMessageWhenAddingAnInvalidFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fakeFont = root.appendingPathComponent("Not-A-Font.ttf")
        try "definitely not font data".write(to: fakeFont, atomically: true, encoding: .utf8)
        let store = CustomFontStore(rootURL: root, scope: testScope)

        store.addFont(from: fakeFont)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.fonts.isEmpty)
    }

    func testAddFailedAndRollbackIncompleteErrorDescriptionNamesBothFailuresDistinctly() {
        let error = CustomFontError.addFailedAndRollbackIncomplete(
            originalReason: "the manifest could not be written",
            rollbackReason: "removing the added font: permission denied"
        )

        let description = try? XCTUnwrap(error.errorDescription)

        XCTAssertTrue(description?.contains("the manifest could not be written") == true)
        XCTAssertTrue(description?.contains("removing the added font: permission denied") == true)
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-CustomFont-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies a real system font into the test's own sandbox so `addFont` has genuine font bytes
    /// to work with, without depending on -- or ever registering directly from -- a system path.
    private func copiedFixtureFont(named name: String, into root: URL, subdirectory: String = "source") throws -> URL {
        let systemFontURL = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/\(name)")
        guard FileManager.default.fileExists(atPath: systemFontURL.path) else {
            throw XCTSkip("Fixture font \(name) is not present on this system.")
        }
        let sourceDirectory = root.appendingPathComponent(subdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let destination = sourceDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: systemFontURL, to: destination)
        return destination
    }
}
