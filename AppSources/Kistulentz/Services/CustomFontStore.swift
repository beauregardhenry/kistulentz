import CoreText
import Foundation

/// App-wide custom fonts the user has added through Settings. A thin `ObservableObject` wrapper
/// around `CustomFontDisk`, matching the shape of `BeneparLanguagePackManager`: static disk/system
/// logic below, a `@Published`-backed manager above that Views bind to directly.
@MainActor
final class CustomFontStore: ObservableObject {
    @Published private(set) var fonts: [CustomFontRecord] = []
    @Published var errorMessage: String?

    private let rootURL: URL
    private let scope: CTFontManagerScope

    /// `scope` defaults to `.persistent` for real use; tests inject `.process` so registering a
    /// font during a test run never becomes a permanent, system-wide change on whichever Mac runs
    /// the suite.
    init(
        rootURL: URL = CustomFontDisk.defaultRootURL(),
        scope: CTFontManagerScope = .persistent
    ) {
        self.rootURL = rootURL
        self.scope = scope
        refresh()
    }

    func refresh() {
        do {
            let manifest = try CustomFontDisk.loadManifest(at: rootURL)
            fonts = Self.sorted(manifest.fonts)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let results = CustomFontDisk.registerAll(at: rootURL, scope: scope)
        let failures = results.compactMap { result in
            result.failureReason.map { "\(result.record.familyName): \($0)" }
        }
        guard !failures.isEmpty else { return }
        errorMessage = "Kistulentz could not re-register \(failures.count) custom font\(failures.count == 1 ? "" : "s") on launch: \(failures.joined(separator: "; "))"
    }

    func addFont(from url: URL) {
        do {
            let record = try CustomFontDisk.addFont(from: url, at: rootURL, scope: scope)
            if !fonts.contains(record) {
                fonts = Self.sorted(fonts + [record])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The managed copy's on-disk location for one of this store's own records -- used to bundle
    /// an app-wide custom font into a project so the project can travel with its own copy of the
    /// font file (see `ProjectFontDisk`).
    func fileURL(for record: CustomFontRecord) -> URL {
        CustomFontDisk.fileURL(for: record, at: rootURL)
    }

    func removeFont(_ record: CustomFontRecord) {
        do {
            try CustomFontDisk.removeFont(record, at: rootURL, scope: scope)
            fonts.removeAll { $0.id == record.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func sorted(_ fonts: [CustomFontRecord]) -> [CustomFontRecord] {
        fonts.sorted { $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending }
    }
}
