import CoreText
import XCTest
@testable import Kistulentz

/// All registration here uses `.process` scope -- same reasoning as `CustomFontTests`: a project's
/// bundled fonts must never make a permanent, system-wide registration on whichever Mac opens the
/// project or runs this suite.
final class ProjectFontDiskTests: XCTestCase {
    private let testScope: CTFontManagerScope = .process

    func testBundleReferencedFontsCopiesAFontWhoseFamilyMatchesTheLayout() throws {
        let projectRoot = temporaryDirectory()
        let appFontsRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: appFontsRoot)
        }
        let source = try copiedFixtureFont(into: appFontsRoot)
        let appRecord = try CustomFontDisk.addFont(from: source, at: appFontsRoot, scope: testScope)

        var archive = PublicationArchive(projectName: "Bundling", projectKind: .nonfiction)
        archive.profiles[0].layout.bodyFontName = appRecord.familyName

        ProjectFontDisk.bundleReferencedFonts(
            in: archive,
            at: projectRoot,
            availableCustomFonts: [appRecord],
            fileURL: { CustomFontDisk.fileURL(for: $0, at: appFontsRoot) }
        )

        let projectManifest = try CustomFontDisk.loadManifest(at: ProjectFontDisk.fontsRootURL(at: projectRoot))
        XCTAssertEqual(projectManifest.fonts.map(\.familyName), [appRecord.familyName])
    }

    func testBundleReferencedFontsSkipsNamesThatAreNotAppWideCustomFonts() throws {
        let projectRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        var archive = PublicationArchive(projectName: "No Match", projectKind: .nonfiction)
        archive.profiles[0].layout.bodyFontName = "Palatino"

        ProjectFontDisk.bundleReferencedFonts(
            in: archive,
            at: projectRoot,
            availableCustomFonts: [],
            fileURL: { CustomFontDisk.fileURL(for: $0, at: projectRoot) }
        )

        let projectManifest = try CustomFontDisk.loadManifest(at: ProjectFontDisk.fontsRootURL(at: projectRoot))
        XCTAssertTrue(projectManifest.fonts.isEmpty)
    }

    func testRegisterBundledFontsMakesAPreviouslyBundledFontAvailable() throws {
        let projectRoot = temporaryDirectory()
        let appFontsRoot = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: appFontsRoot)
        }
        let source = try copiedFixtureFont(into: appFontsRoot)
        let appRecord = try CustomFontDisk.addFont(from: source, at: appFontsRoot, scope: testScope)
        _ = try CustomFontDisk.addFont(
            from: CustomFontDisk.fileURL(for: appRecord, at: appFontsRoot),
            at: ProjectFontDisk.fontsRootURL(at: projectRoot),
            scope: testScope
        )

        let results = ProjectFontDisk.registerBundledFonts(at: projectRoot)

        XCTAssertEqual(results.map(\.record.familyName), [appRecord.familyName])
        XCTAssertNil(results.first?.failureReason)
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ProjectFont-Test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copiedFixtureFont(into root: URL) throws -> URL {
        let systemFontURL = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Chalkduster.ttf")
        guard FileManager.default.fileExists(atPath: systemFontURL.path) else {
            throw XCTSkip("Fixture font is not present on this system.")
        }
        let destination = root.appendingPathComponent("Chalkduster.ttf")
        try FileManager.default.copyItem(at: systemFontURL, to: destination)
        return destination
    }
}
