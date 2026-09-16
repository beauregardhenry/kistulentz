import AppKit
import XCTest
@testable import Kistulentz

/// This is deliberately a thin test. The actual behavior it's protecting -- whether a real,
/// bundled Kistulentz.app shows a blank document or macOS's own system "Open" panel at launch --
/// can only be observed by really quitting and relaunching the real app; there's no way to make
/// that a CI-runnable, automated reproduction. What's verified here is the one piece of it that
/// genuinely is unit-testable: that KistulentzAppDelegate registers the NSUserDefaults value real
/// launches depend on, and returns the expected answer from the classic AppKit hook for this case.
/// The delegate's own doc comment records what was tried, tested against a real installed app
/// through repeated quit/relaunch cycles, and found insufficient on its own -- this default is a
/// real improvement (verified to fix resuming an existing document across quit/relaunch), not a
/// complete fix for a truly first-ever launch.
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
}
