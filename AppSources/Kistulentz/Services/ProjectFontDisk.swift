import CoreText
import Foundation

/// Bundles app-wide custom fonts (added through Settings, see `CustomFontDisk`) into a project's
/// own `.kistulentz` metadata folder whenever the project's publication layout references one, so
/// opening that project on a different Mac has access to the font file without that Mac's user
/// separately adding it through Settings first -- the font "travels with the project."
///
/// Reuses `CustomFontDisk` wholesale for the project-local copy: the project's `Fonts` folder is
/// just another root with its own manifest and managed `Files` directory, in exactly the shape
/// `CustomFontDisk` already manages for the app-wide one. That gets deduplication-by-family-name,
/// rollback-on-failed-manifest-write, and idempotent re-registration for free.
///
/// Always `.process` scope, never `.persistent`: opening a project file is not the same act as a
/// user deliberately installing a font, and must never make a permanent, system-wide font
/// registration on a Mac that isn't the one the font was originally added on.
enum ProjectFontDisk {
    private static let fontsDirectoryName = "Fonts"

    static func fontsRootURL(at projectRoot: URL) -> URL {
        WritingProjectDisk.metadataURL(at: projectRoot).appendingPathComponent(fontsDirectoryName, isDirectory: true)
    }

    /// Copies the managed file behind any app-wide custom font that a publication profile's
    /// body/heading font references into this project's own `Fonts` folder. Silently skips a name
    /// that isn't an app-wide custom font (an ordinary system font name, most of the time) and
    /// silently skips a copy that fails -- bundling is a best-effort convenience on top of a
    /// publication save that already succeeded; it must never turn that save into a failure.
    static func bundleReferencedFonts(
        in archive: PublicationArchive,
        at projectRoot: URL,
        availableCustomFonts: [CustomFontRecord],
        fileURL: (CustomFontRecord) -> URL
    ) {
        guard !availableCustomFonts.isEmpty else { return }
        let referencedNames = Set(archive.profiles.flatMap { [$0.layout.bodyFontName, $0.layout.headingFontName] })
        let root = fontsRootURL(at: projectRoot)
        for name in referencedNames {
            guard let record = availableCustomFonts.first(where: {
                $0.familyName.caseInsensitiveCompare(name) == .orderedSame
            }) else { continue }
            let source = fileURL(record)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            _ = try? CustomFontDisk.addFont(from: source, at: root, scope: .process)
        }
    }

    /// Registers every font already bundled into this project for the current process, so the
    /// editor and publication export can resolve them this session even on a Mac that has never
    /// added them app-wide.
    @discardableResult
    static func registerBundledFonts(at projectRoot: URL) -> [(record: CustomFontRecord, failureReason: String?)] {
        CustomFontDisk.registerAll(at: fontsRootURL(at: projectRoot), scope: .process)
    }
}
