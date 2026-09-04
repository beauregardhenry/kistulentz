import AppKit
import XCTest
@testable import Kistulentz

/// Direct tests for the editor font preference: `AppSettings.editorFontName` / `.editorFontSize`
/// (default value, persistence, and the load-time clamp for an out-of-range stored value) and
/// `MarkdownEditorFont.resolve`, the pure function that turns that preference into an actual
/// `NSFont` with a safe fallback when the name is blank or no longer installed. `MarkdownTextView`
/// itself (the NSViewRepresentable that applies the resolved font to a live NSTextView) isn't
/// covered here -- there's no existing precedent in this suite for driving an NSViewRepresentable
/// end to end, and `resolve` is where the actual decision logic lives.
final class EditorPreferencesTests: XCTestCase {
    @MainActor
    func testEditorFontPreferencesDefaultToTheSystemFontAtSeventeenPoints() throws {
        let suite = "EditorPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.editorFontName, "")
        XCTAssertEqual(settings.editorFontSize, 17)
    }

    @MainActor
    func testEditorFontPreferencesPersistAcrossReopen() throws {
        let suite = "EditorPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.editorFontName = "Georgia"
        settings.editorFontSize = 21

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.editorFontName, "Georgia")
        XCTAssertEqual(reopened.editorFontSize, 21)
    }

    @MainActor
    func testEditorFontSizeIsClampedOnLoadWhenTheStoredValueIsAboveTheRange() throws {
        let suite = "EditorPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // "editorFontSize" is AppSettings.DefaultsKey.editorFontSize's raw value -- that enum is
        // private, so this writes the same UserDefaults key by its literal string to simulate a
        // stored value from outside AppSettings's own (unclamped) setter, e.g. a hand-edited or
        // future-version defaults file.
        defaults.set(500.0, forKey: "editorFontSize")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.editorFontSize, AppSettings.editorFontSizeRange.upperBound)
    }

    @MainActor
    func testEditorFontSizeIsClampedOnLoadWhenTheStoredValueIsBelowTheRange() throws {
        let suite = "EditorPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1.0, forKey: "editorFontSize")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.editorFontSize, AppSettings.editorFontSizeRange.lowerBound)
    }

    func testResolveFallsBackToTheSystemFontForABlankFontName() {
        let resolved = MarkdownEditorFont.resolve(name: "   ", size: 21)
        let expected = NSFont.systemFont(ofSize: 21, weight: .regular)

        XCTAssertEqual(resolved.fontName, expected.fontName)
        XCTAssertEqual(resolved.pointSize, 21)
    }

    func testResolveFallsBackToTheSystemFontForAnUnavailableFamilyName() {
        let resolved = MarkdownEditorFont.resolve(
            name: "Definitely Not An Installed Font Family 12345",
            size: 19
        )
        let expected = NSFont.systemFont(ofSize: 19, weight: .regular)

        XCTAssertEqual(resolved.fontName, expected.fontName)
        XCTAssertEqual(resolved.pointSize, 19)
    }

    /// Resolves by family name (via NSFontManager), not by exact PostScript name -- Helvetica's
    /// regular face happens to share its family's name, but the resolved font's `familyName` is
    /// what actually proves family-based resolution engaged, regardless of that coincidence.
    func testResolveUsesTheNamedFamilyWhenItIsInstalled() {
        let resolved = MarkdownEditorFont.resolve(name: "Helvetica", size: 23)

        XCTAssertEqual(resolved.familyName, "Helvetica")
        XCTAssertEqual(resolved.pointSize, 23)
    }

    func testResolveTrimsWhitespaceAroundTheFontName() {
        let resolved = MarkdownEditorFont.resolve(name: "  Helvetica  ", size: 15)

        XCTAssertEqual(resolved.familyName, "Helvetica")
    }
}
