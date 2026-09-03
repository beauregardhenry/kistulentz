import XCTest

final class KistulentzUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 45
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

        let referenceMenu = referenceControl
        XCTAssertTrue(referenceMenu.waitForExistence(timeout: 8))
        referenceMenu.click()
        let researchLibraryItem = app.menuItems["Research Library…"]
        XCTAssertTrue(researchLibraryItem.waitForExistence(timeout: 3))
        researchLibraryItem.click()

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

        let applicationMenu = app.menuBars.menuBarItems["Kistulentz"].firstMatch
        XCTAssertTrue(applicationMenu.waitForExistence(timeout: 3))
        applicationMenu.click()
        let systemCheckItem = app.menuItems["Kistulentz System Check…"]
        XCTAssertTrue(systemCheckItem.waitForExistence(timeout: 3))
        systemCheckItem.click()

        let export = app.buttons["Export Diagnostic Report…"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        XCTAssertTrue(export.isEnabled)
        export.click()

        let cancel = app.buttons.matching(identifier: "CancelButton").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(export.waitForExistence(timeout: 2))
    }

    func testDestinkReviewOpensRunsLocallyAndCloses() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: true)

        let openReview = app.buttons["De-stink"]
        XCTAssertTrue(openReview.waitForExistence(timeout: 8))
        openReview.click()

        let title = app.staticTexts["De-stink Review"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let score = app.descendants(matching: .any)["DestinkScoreSummary"].firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review only: this screen never changes your prose."].exists)

        app.buttons["Done"].click()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    private func launch(completedOnboarding: Bool, acknowledgedEnglishPack: Bool) {
        app.launchArguments += [
            "-hasCompletedOnboarding", completedOnboarding ? "YES" : "NO",
            "-hasAcknowledgedEnglishPackPrompt", acknowledgedEnglishPack ? "YES" : "NO"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
    }

    private var referenceControl: XCUIElement {
        app.descendants(matching: .any)["ReferenceMenu"].firstMatch
    }
}
