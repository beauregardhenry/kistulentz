import XCTest

final class KistulentzUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["KISTULENTZ_UI_TESTING"] = "1"
        app.launchEnvironment["CFFIXED_USER_HOME"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-UI-\(UUID().uuidString)", isDirectory: true)
            .path
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testFirstLaunchEnglishPackPromptCanBeDeclined() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: false)

        let prompt = app.staticTexts["Enable Better Local Analysis"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        app.buttons["Not Now"].click()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testResearchLibraryFolderChooserCancelsAndLibraryCloses() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: true)

        let referenceMenu = app.buttons["Reference"]
        XCTAssertTrue(referenceMenu.waitForExistence(timeout: 8))
        referenceMenu.click()
        app.menuItems["Research Library…"].click()

        let title = app.staticTexts["Research Library"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["Choose Folder…"].firstMatch.click()

        let cancel = app.buttons.matching(identifier: "CancelButton").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(title.waitForExistence(timeout: 2))

        app.buttons["Close"].firstMatch.click()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testDiagnosticExportPanelCanBeCancelled() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: true)

        app.menuBars.menuItems["Kistulentz"].click()
        app.menuItems["Kistulentz System Check…"].click()

        let export = app.buttons["Export Diagnostic Report…"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        XCTAssertTrue(export.isEnabled)
        export.click()

        let cancel = app.buttons.matching(identifier: "CancelButton").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(export.waitForExistence(timeout: 2))
    }

    private func launch(completedOnboarding: Bool, acknowledgedEnglishPack: Bool) {
        app.launchArguments += [
            "-hasCompletedOnboarding", completedOnboarding ? "YES" : "NO",
            "-hasAcknowledgedEnglishPackPrompt", acknowledgedEnglishPack ? "YES" : "NO"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // DocumentGroup initially presents the standard Open panel when no
        // restoration state exists. Command-N creates the isolated test draft
        // and leaves the user's filesystem untouched.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Reference"].waitForExistence(timeout: 8))
    }
}
