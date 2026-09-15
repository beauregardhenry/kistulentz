import AppKit
import XCTest
@testable import Kistulentz

/// `NSOpenPanel`/`NSSavePanel` participate in Cocoa's window-state restoration inside a real,
/// bundled, running app -- left unconfigured, quitting (or being killed) while one of these
/// transient file-choosers is open makes AppKit silently re-show that exact panel on the next
/// launch, ahead of anything Kistulentz's own startup logic gets a chance to run. `isRestorable`'s
/// ambient default depends on that app context (it measures `false` for a bare, unbundled test
/// process, since restoration needs a running `NSApplication` this process never starts), so this
/// only asserts the postcondition our own code is responsible for -- that `configureForPresentation`
/// unconditionally turns restoration off -- rather than a precondition this process can't
/// meaningfully observe. No panel is ever presented (no `runModal`/`beginSheetModal`), so this
/// stays headless-safe.
@MainActor
final class MacFilePanelTests: XCTestCase {
    func testConfigureForPresentationDisablesStateRestorationOnAnOpenPanel() {
        let panel = NSOpenPanel()

        MacFilePanel.configureForPresentation(panel)

        XCTAssertFalse(panel.isRestorable)
    }

    func testConfigureForPresentationDisablesStateRestorationOnASavePanel() {
        let panel = NSSavePanel()

        MacFilePanel.configureForPresentation(panel)

        XCTAssertFalse(panel.isRestorable)
    }
}
