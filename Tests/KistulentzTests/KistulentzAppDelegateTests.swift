import AppKit
import XCTest
@testable import Kistulentz

/// This is deliberately a thin test. The actual behavior it's protecting -- whether a real,
/// bundled Kistulentz.app shows a blank document or macOS's own system "Open" panel at launch or
/// at Dock reactivation -- can only be observed by really quitting, relaunching, and reactivating
/// the real app; there's no way to make that a CI-runnable, automated reproduction (in particular,
/// whether applicationSupportsSecureRestorableState actually causes AppKit to persist a
/// ~/Library/Saved Application State/ directory is an OS-level effect no unit test can see). What's
/// verified here is the piece of it that genuinely is unit-testable: that KistulentzAppDelegate
/// registers the NSUserDefaults value real launches depend on, and returns the expected answer from
/// each hook that doesn't itself touch the real window server. The delegate's own doc comment
/// records what was tried, tested against a real installed app through repeated quit/relaunch and
/// reactivation cycles, and found insufficient on its own -- including the miss in the first pass
/// at this fix (0.22.0), which shipped without applicationSupportsSecureRestorableState and so
/// never actually stopped the panel from reappearing on every launch, and a later regression where
/// an unconditional `applicationWillFinishLaunching` fix opened a second, genuinely blank window on
/// top of a document secure state restoration had already reopened.
///
/// `applicationDidFinishLaunching`'s two settling signals and the `settleLaunchDocuments()` method
/// they both call (which opens an untitled document when nothing is open, or closes a redundant
/// blank one left over from racing SwiftUI `DocumentGroup` behavior when a real document is open
/// too -- fixing the original "system panel after quitting with every window closed" bug and a
/// later duplicate-window regression) and `applicationShouldHandleReopen`'s `hasVisibleWindows ==
/// false` branch (the same open-untitled-document call, fixing the system panel appearing on Dock
/// reactivation instead of a fresh launch) are deliberately not exercised here at all: unlike the
/// other hooks, they ask AppKit to open, close, or enumerate real document windows, which would try
/// to touch the real window server from inside a headless test run rather than just returning a
/// value -- exactly the kind of side effect this file otherwise avoids. They're verified the same
/// way as everything else in this delegate: real quit/relaunch/reactivation cycles against a real
/// installed build, recorded in the delegate's own doc comment.
final class KistulentzAppDelegateTests: XCTestCase {
    @MainActor
    func testInitRegistersNSQuitAlwaysKeepsWindowsDefault() {
        _ = KistulentzAppDelegate()

        XCTAssertTrue(UserDefaults.standard.bool(forKey: "NSQuitAlwaysKeepsWindows"))
    }

    @MainActor
    func testApplicationShouldOpenUntitledFileReturnsTrue() {
        let delegate = KistulentzAppDelegate()

        XCTAssertTrue(delegate.applicationShouldOpenUntitledFile(NSApplication.shared))
    }

    @MainActor
    func testApplicationSupportsSecureRestorableStateReturnsTrue() {
        let delegate = KistulentzAppDelegate()

        XCTAssertTrue(delegate.applicationSupportsSecureRestorableState(NSApplication.shared))
    }

    /// Only the `hasVisibleWindows == true` branch is exercised: it returns immediately without
    /// touching `NSDocumentController`, unlike the `false` branch (see the file header).
    @MainActor
    func testApplicationShouldHandleReopenReturnsTrueWhenWindowsAreAlreadyVisible() {
        let delegate = KistulentzAppDelegate()

        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
    }
}
