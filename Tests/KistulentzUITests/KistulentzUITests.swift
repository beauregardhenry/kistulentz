import XCTest

final class KistulentzUITests: KistulentzUITestCase {

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

    func testMajorProjectWorkspacesKeepTheirExitControlsUsableAtTheMinimumWindowSize() throws {
        let project = try makeProject(
            name: "Workspace Exit Fixture",
            documents: [("Draft.md", "# Draft\n\nA stable project passage.\n")],
            kind: "nonfiction"
        )
        launch(environment: project.environment)

        openProjectCommand("Project Organization…")
        XCTAssertTrue(app.descendants(matching: .any)["ProjectOrganizationView"].waitForExistence(timeout: 5))
        let organizationDone = app.buttons["Done"]
        XCTAssertTrue(organizationDone.isHittable)
        organizationDone.click()

        openProjectCommand("Systemic Revision Center…")
        XCTAssertTrue(app.descendants(matching: .any)["SystemicRevisionCenterView"].waitForExistence(timeout: 5))
        let revisionDone = app.buttons["Done"]
        XCTAssertTrue(revisionDone.isHittable)
        revisionDone.click()

        openProjectCommand("Project Research…")
        XCTAssertTrue(app.descendants(matching: .any)["ProjectResearchView"].waitForExistence(timeout: 5))
        let researchDone = app.buttons["Done"]
        XCTAssertTrue(researchDone.isHittable)
        researchDone.click()

        openProjectCommand("Publish & Export…")
        let publicationClose = app.buttons["Close"]
        XCTAssertTrue(publicationClose.waitForExistence(timeout: 8))
        XCTAssertTrue(publicationClose.isHittable)
        publicationClose.click()

        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testReferenceLibraryWelcomeAlwaysOffersACancelPath() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: true)

        let referenceMenu = referenceControl
        XCTAssertTrue(referenceMenu.waitForExistence(timeout: 8))
        referenceMenu.click()
        let libraryItem = app.menuItems["Reference Library…"]
        XCTAssertTrue(libraryItem.waitForExistence(timeout: 3))
        libraryItem.click()

        XCTAssertTrue(app.descendants(matching: .any)["ReferenceLibraryView"].waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.click()
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testWhatsNewCanBeOpenedFromHelpAndClosed() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: true)

        let helpMenu = app.menuBars.menuBarItems["Help"].firstMatch
        XCTAssertTrue(helpMenu.waitForExistence(timeout: 3))
        helpMenu.click()
        let whatsNewItem = app.menuItems["What’s New in Kistulentz…"]
        XCTAssertTrue(whatsNewItem.waitForExistence(timeout: 3))
        whatsNewItem.click()

        let title = app.staticTexts["What’s New in Kistulentz 0.16.1"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let safetySummary = app.descendants(matching: .any)["WhatsNewStorageSafety"].firstMatch
        XCTAssertTrue(safetySummary.exists)
        app.buttons["Continue"].click()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
    }

    private var referenceControl: XCUIElement {
        app.descendants(matching: .any)["ReferenceMenu"].firstMatch
    }
}
