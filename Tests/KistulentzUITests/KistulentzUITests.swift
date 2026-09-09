import XCTest

@MainActor
final class KistulentzUITests: KistulentzUITestCase {

    func testLaunchLoadsTheRequestedDocumentInsteadOfFallbackText() throws {
        let documentURL = testRoot.appendingPathComponent("Requested Draft.md")
        let requestedText = "# Requested Draft\n\nLoaded from disk.\n"
        try requestedText.write(to: documentURL, atomically: true, encoding: .utf8)

        launch(environment: [
            "KISTULENTZ_UI_TEST_DOCUMENT_PATH": documentURL.path,
            "KISTULENTZ_UI_TEST_DOCUMENT_TEXT": "This fallback must not appear."
        ])

        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(value(of: editor), requestedText)
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

    func testResearchLibraryFolderChooserOpensTheApprovedFolder() throws {
        let library = testRoot.appendingPathComponent("Chosen Research Library", isDirectory: true)
        launch(
            completedOnboarding: true,
            acknowledgedEnglishPack: true,
            environment: ["KISTULENTZ_UI_TEST_RESEARCH_LIBRARY_PATH": library.path]
        )

        XCTAssertTrue(referenceControl.waitForExistence(timeout: 8))
        referenceControl.click()
        let researchLibraryItem = app.menuItems["Research Library…"]
        XCTAssertTrue(researchLibraryItem.waitForExistence(timeout: 3))
        researchLibraryItem.click()

        let title = app.staticTexts["Research Library"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["Choose Folder…"].firstMatch.click()

        XCTAssertTrue(app.buttons["Show Markdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: library.appendingPathComponent(".kistulentz", isDirectory: true).path
        ))
        XCTAssertTrue(title.exists)
    }

    func testResearchLibraryCanCreateEditSearchAndSafelyRemoveAManualSource() throws {
        let library = testRoot.appendingPathComponent("Research CRUD Library", isDirectory: true)
        launch(
            completedOnboarding: true,
            acknowledgedEnglishPack: true,
            environment: ["KISTULENTZ_UI_TEST_RESEARCH_LIBRARY_PATH": library.path]
        )

        XCTAssertTrue(referenceControl.waitForExistence(timeout: 8))
        referenceControl.click()
        let researchLibraryItem = app.menuItems["Research Library…"]
        XCTAssertTrue(researchLibraryItem.waitForExistence(timeout: 3))
        researchLibraryItem.click()
        XCTAssertTrue(app.staticTexts["Research Library"].waitForExistence(timeout: 5))
        app.buttons["Choose Folder…"].firstMatch.click()
        XCTAssertTrue(app.buttons["Show Markdown"].waitForExistence(timeout: 5))

        let sourceActions = app.descendants(matching: .any)["ResearchSourceActions"].firstMatch
        XCTAssertTrue(sourceActions.waitForExistence(timeout: 3))
        sourceActions.click()
        let manualSource = app.menuItems["Manual Source"]
        XCTAssertTrue(manualSource.waitForExistence(timeout: 3))
        manualSource.click()

        let titleField = app.descendants(matching: .any)["ResearchSourceTitle"].firstMatch
        let citeKeyField = app.descendants(matching: .any)["ResearchSourceCiteKey"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertTrue(citeKeyField.exists)
        replaceText(in: titleField, with: "Harbor Study")
        replaceText(in: citeKeyField, with: "henry2026harbor")
        app.descendants(matching: .any)["SaveResearchSource"].firstMatch.click()

        let sourceTitle = app.staticTexts["Harbor Study"].firstMatch
        XCTAssertTrue(sourceTitle.waitForExistence(timeout: 5))
        let indexURL = library.appendingPathComponent(".kistulentz/research-library.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertTrue(try String(contentsOf: indexURL, encoding: .utf8).contains("Harbor Study"))

        let search = app.descendants(matching: .any)["ResearchSourceSearch"].firstMatch
        XCTAssertTrue(search.exists)
        replaceText(in: search, with: "no matching source")
        XCTAssertFalse(sourceTitle.waitForExistence(timeout: 2))
        replaceText(in: search, with: "harbor")
        XCTAssertTrue(app.staticTexts["Harbor Study"].firstMatch.waitForExistence(timeout: 3))

        app.staticTexts["Harbor Study"].firstMatch.rightClick()
        app.menuItems["Remove"].click()
        let cancelRemoval = app.descendants(matching: .any)["CancelResearchSourceRemoval"].firstMatch
        XCTAssertTrue(cancelRemoval.waitForExistence(timeout: 3))
        cancelRemoval.click()
        XCTAssertTrue(app.staticTexts["Harbor Study"].firstMatch.exists)

        app.staticTexts["Harbor Study"].firstMatch.rightClick()
        app.menuItems["Remove"].click()
        let confirmRemoval = app.descendants(matching: .any)["ConfirmResearchSourceRemoval"].firstMatch
        XCTAssertTrue(confirmRemoval.waitForExistence(timeout: 3))
        confirmRemoval.click()
        XCTAssertFalse(app.staticTexts["Harbor Study"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(try String(contentsOf: indexURL, encoding: .utf8).contains("Harbor Study"))
        XCTAssertTrue(app.staticTexts["Research Library"].exists)
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

        let title = app.staticTexts["What’s New in Kistulentz 0.17.1"]
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
