import AppKit
import XCTest
@testable import Kistulentz

/// This is deliberately a thin test. The actual behavior it's protecting -- whether a real,
/// bundled Kistulentz.app shows a blank document or macOS's own system "Open" panel at launch --
/// can only be observed by really quitting and relaunching the real app; there's no way to make
/// that a CI-runnable, automated reproduction (in particular, whether
/// applicationSupportsSecureRestorableState actually causes AppKit to persist a
/// ~/Library/Saved Application State/ directory is an OS-level effect no unit test can see). What's
/// verified here is the one piece of it that genuinely is unit-testable: that KistulentzAppDelegate
/// registers the NSUserDefaults value real launches depend on, and returns the expected answer from
/// each of the three AppKit hooks this fix relies on. The delegate's own doc comment records what
/// was tried, tested against a real installed app through repeated quit/relaunch cycles, and found
/// insufficient on its own -- including the miss in the first pass at this fix (0.22.0), which
/// shipped without applicationSupportsSecureRestorableState and so never actually stopped the panel
/// from reappearing on every launch.
///
/// `applicationWillFinishLaunching` (calling `NSDocumentController.shared.openUntitledDocumentAndDisplay`,
/// added to fix the system panel reliably reappearing after quitting with every window already
/// closed) is deliberately not exercised here at all: unlike the other three hooks, it asks
/// AppKit to open and display a real document window, which would try to touch the real window
/// server from inside a headless test run rather than just returning a value -- exactly the kind
/// of side effect this file otherwise avoids. It's verified the same way as everything else in
/// this delegate: real quit/relaunch cycles against a real installed build.
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
}
