import XCTest
@testable import Kistulentz

/// Direct tests for `AppSettings.lastOpenedProjectURL` / `.recordOpenedProject` /
/// `.clearLastOpenedProject` -- the persistence half of automatically reopening a Kistulentz
/// project across quit/relaunch. Without this, closing the app while a project is open silently
/// loses it: macOS's own window restoration only ever knows about the single generic document
/// each window represents at the OS level, never the folder-based project loaded on top of it.
/// `EditorWorkspace.reopenLastProjectIfNeeded` (the launch-time consumer of this value, and where
/// `activateProject`/`closeProject` actually call these setters) is SwiftUI View-layer logic
/// covered by the UI test suite, matching this codebase's existing split between Swift unit tests
/// for models/services and UI tests for view behavior -- not duplicated here.
final class LastOpenedProjectRecallTests: XCTestCase {
    @MainActor
    func testLastOpenedProjectURLDefaultsToNil() throws {
        let suite = "LastOpenedProjectRecallTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertNil(settings.lastOpenedProjectURL)
    }

    @MainActor
    func testRecordOpenedProjectPersistsAcrossReopen() throws {
        let suite = "LastOpenedProjectRecallTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let projectURL = URL(fileURLWithPath: "/tmp/\(suite)/My Novel", isDirectory: true)

        let settings = AppSettings(defaults: defaults)
        settings.recordOpenedProject(url: projectURL)

        // UserDefaults.url(forKey:) round-trips a directory URL with a trailing slash appended
        // even when the original didn't have one, so compare paths rather than the URLs
        // themselves -- both still resolve to the same directory.
        XCTAssertEqual(settings.lastOpenedProjectURL?.path, projectURL.path)

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.lastOpenedProjectURL?.path, projectURL.path)
    }

    @MainActor
    func testClearLastOpenedProjectRemovesTheStoredValue() throws {
        let suite = "LastOpenedProjectRecallTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let projectURL = URL(fileURLWithPath: "/tmp/\(suite)/My Novel", isDirectory: true)

        let settings = AppSettings(defaults: defaults)
        settings.recordOpenedProject(url: projectURL)
        settings.clearLastOpenedProject()

        XCTAssertNil(settings.lastOpenedProjectURL)

        let reopened = AppSettings(defaults: defaults)
        XCTAssertNil(reopened.lastOpenedProjectURL)
    }

    @MainActor
    func testRecordOpenedProjectOverwritesAPreviousValue() throws {
        let suite = "LastOpenedProjectRecallTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstProject = URL(fileURLWithPath: "/tmp/\(suite)/First Draft", isDirectory: true)
        let secondProject = URL(fileURLWithPath: "/tmp/\(suite)/Second Draft", isDirectory: true)

        let settings = AppSettings(defaults: defaults)
        settings.recordOpenedProject(url: firstProject)
        settings.recordOpenedProject(url: secondProject)

        XCTAssertEqual(settings.lastOpenedProjectURL, secondProject)
    }
}
