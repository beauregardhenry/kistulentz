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

        app.buttons["Close Research Library"].firstMatch.click()
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

    func testDiagnosticReportExportsPrivacySafeVersionedReproductionGuide() throws {
        let destination = testRoot.appendingPathComponent("Kistulentz Diagnostics.md")
        launch(
            completedOnboarding: true,
            acknowledgedEnglishPack: true,
            environment: ["KISTULENTZ_UI_TEST_SAVE_DESTINATION_PATH": destination.path]
        )
        openSystemCheck()

        let export = app.buttons["ExportDiagnosticReport"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.click()

        let confirmation = app.staticTexts["SystemCheckMessage"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: confirmation), "Diagnostic report exported.")
        waitUntil(description: "Diagnostic report should be written to the selected destination") {
            FileManager.default.fileExists(atPath: destination.path)
        }
        let markdown = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Kistulentz System Check"))
        XCTAssertTrue(markdown.contains("- Kistulentz:"))
        XCTAssertTrue(markdown.contains("## Help us reproduce a problem"))
        XCTAssertTrue(markdown.contains("excludes document and manuscript text"))
        XCTAssertFalse(markdown.contains(testRoot.path))
    }

    func testDiagnosticExportWriteFailureStaysUsableAndReportsTheError() throws {
        let unwritableDestination = testRoot.appendingPathComponent("Existing Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: unwritableDestination, withIntermediateDirectories: true)
        launch(
            completedOnboarding: true,
            acknowledgedEnglishPack: true,
            environment: ["KISTULENTZ_UI_TEST_SAVE_DESTINATION_PATH": unwritableDestination.path]
        )
        openSystemCheck()

        let export = app.buttons["ExportDiagnosticReport"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.click()

        let alert = app.staticTexts["Couldn’t export the report"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let confirmation = app.sheets.firstMatch.buttons["OK"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        XCTAssertTrue(export.isEnabled)
        XCTAssertTrue(app.windows.firstMatch.exists)
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
        // This test opens and closes four major workspaces in sequence, which takes
        // noticeably longer than the shared 60s default on slower CI hardware (the
        // Intel runner used for the release smoke test in particular). Give it more
        // room so a slow runner doesn't get flagged as a hang.
        executionTimeAllowance = 120
        let project = try makeProject(
            name: "Workspace Exit Fixture",
            documents: [("Draft.md", "# Draft\n\nA stable project passage.\n")],
            kind: "nonfiction"
        )
        launch(environment: project.environment)

        openProjectCommand("Project Organization…")
        XCTAssertTrue(app.staticTexts["Project Organization"].waitForExistence(timeout: 5))
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

    func testSystemicRevisionSupportsEditedProposalCancelApplyAndOneStepUndo() throws {
        let original = "# Draft\n\nWe utilize tools.\n"
        let edited = "# Draft\n\nWe employ tools.\n"
        let project = try makeProject(
            name: "Systemic Revision Journey",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )
        let chapter = project.root.appendingPathComponent("Draft.md")

        launch(environment: project.environment)
        openProjectCommand("Systemic Revision Center…")
        XCTAssertTrue(
            app.descendants(matching: .any)["SystemicRevisionCenterView"]
                .waitForExistence(timeout: 5)
        )
        let scan = app.buttons["Scan Locally"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.click()
        let lineEditing = app.staticTexts["Line Editing"].firstMatch
        XCTAssertTrue(lineEditing.waitForExistence(timeout: 5))
        lineEditing.click()

        let selectChange = app.checkBoxes["Select change: Simpler alternative"].firstMatch
        XCTAssertTrue(selectChange.waitForExistence(timeout: 12))
        selectChange.click()
        let previewButton = app.buttons["Preview Selected Changes…"]
        XCTAssertTrue(previewButton.isEnabled)
        previewButton.click()

        let previewTitle = app.staticTexts["Preview Coordinated Changes"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))
        let proposal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Proposed systemic replacement for Draft.md:'"))
            .firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 5))
        replaceText(in: proposal, with: "employ")

        app.buttons["Apply Included Changes…"].click()
        let cancelApply = app.buttons["CancelSystemicRevisionApply"]
        XCTAssertTrue(cancelApply.waitForExistence(timeout: 3))
        cancelApply.click()
        XCTAssertTrue(previewTitle.exists)
        XCTAssertEqual(try String(contentsOf: chapter, encoding: .utf8), original)

        app.buttons["Apply Included Changes…"].click()
        let confirmApply = app.buttons["ConfirmSystemicRevisionApply"]
        XCTAssertTrue(confirmApply.waitForExistence(timeout: 3))
        confirmApply.click()
        XCTAssertFalse(previewTitle.waitForExistence(timeout: 2))
        waitUntil(description: "Systemic Revision should persist the edited proposal") {
            (try? String(contentsOf: chapter, encoding: .utf8)) == edited
        }

        app.buttons["Done"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: editor), edited)
        let undoOutcome = try undoProjectChange(expecting: original)
        XCTAssertTrue(undoOutcome.contains("error=none"), undoOutcome)
        let redoOutcome = try redoProjectChange(expecting: edited)
        XCTAssertTrue(redoOutcome.contains("error=none"), redoOutcome)
    }

    func testSystemicRevisionRecheckBlocksAnExternallyChangedPassage() throws {
        let original = "# Draft\n\nWe utilize tools.\n"
        let external = "# Draft\n\nAn external editor changed this passage.\n"
        let project = try makeProject(
            name: "Stale Systemic Revision Journey",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )
        let chapter = project.root.appendingPathComponent("Draft.md")

        launch(environment: project.environment)
        openProjectCommand("Systemic Revision Center…")
        XCTAssertTrue(app.descendants(matching: .any)["SystemicRevisionCenterView"].waitForExistence(timeout: 5))
        let scan = app.buttons["Scan Locally"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.click()
        let lineEditing = app.staticTexts["Line Editing"].firstMatch
        XCTAssertTrue(lineEditing.waitForExistence(timeout: 5))
        lineEditing.click()
        let selectChange = app.checkBoxes["Select change: Simpler alternative"].firstMatch
        XCTAssertTrue(selectChange.waitForExistence(timeout: 12))
        selectChange.click()
        app.buttons["Preview Selected Changes…"].click()
        let previewTitle = app.staticTexts["Preview Coordinated Changes"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))

        try external.write(to: chapter, atomically: true, encoding: .utf8)
        app.buttons["Recheck"].click()

        XCTAssertTrue(
            app.staticTexts["The original passage changed after this suggestion was created."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["Apply Included Changes…"].isEnabled)
        app.buttons["Cancel"].click()
        app.buttons["Done"].click()
        XCTAssertEqual(try String(contentsOf: chapter, encoding: .utf8), external)
    }

    func testPublishExportPreflightCancelAndSuccessfulPackageJourney() throws {
        let project = try makeProject(
            name: "Publish Journey",
            documents: [("Draft.md", "# Draft\n\nA short, complete publication passage.\n")],
            kind: "fiction"
        )
        let output = testRoot.appendingPathComponent("Publication Output", isDirectory: true)
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_PUBLICATION_OUTPUT_PATH"] = output.path

        launch(environment: environment)
        openProjectCommand("Publish & Export…")
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 8))
        let preflightPane = app.staticTexts["Preflight & Export"].firstMatch
        XCTAssertTrue(preflightPane.waitForExistence(timeout: 5))
        preflightPane.click()

        app.buttons["Run Preflight"].click()
        let errorCount = app.staticTexts["0 errors"]
        XCTAssertTrue(errorCount.waitForExistence(timeout: 5))
        app.buttons["Choose Output Folder…"].click()
        let outputLabel = app.staticTexts["PublicationOutputDirectory"]
        XCTAssertTrue(outputLabel.waitForExistence(timeout: 3))

        let export = app.buttons["Export EPUB 3"]
        XCTAssertTrue(export.isEnabled)
        export.click()
        let cancelExport = app.buttons["CancelPublicationExport"]
        XCTAssertTrue(cancelExport.waitForExistence(timeout: 3))
        cancelExport.click()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: output.appendingPathComponent("Publish Journey-submission").path
        ))

        export.click()
        let confirmExport = app.buttons["ConfirmPublicationExport"]
        XCTAssertTrue(confirmExport.waitForExistence(timeout: 3))
        confirmExport.click()

        let package = output.appendingPathComponent("Publish Journey-submission", isDirectory: true)
        let publication = package.appendingPathComponent("Publish Journey.epub")
        waitUntil(timeout: 20, description: "Publication export should finish") {
            FileManager.default.fileExists(atPath: publication.path)
        }
        let historyPane = app.staticTexts["History"].firstMatch
        XCTAssertTrue(historyPane.waitForExistence(timeout: 3))
        historyPane.click()
        XCTAssertTrue(app.buttons["Copy Checksum"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["EPUB 3"].firstMatch.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: publication.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.appendingPathComponent("Submission Readiness Report.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.appendingPathComponent("Submission Readiness Report.pdf").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.appendingPathComponent("SHA256SUMS.txt").path
        ))
        XCTAssertTrue(try String(
            contentsOf: project.root.appendingPathComponent(".kistulentz/publication.json"),
            encoding: .utf8
        ).contains("Publish Journey-submission"))
    }

    func testActivePublicationExportCanBeCancelledAndClosingStopsARetry() throws {
        let project = try makeProject(
            name: "Cancelled Publish Journey",
            documents: [("Draft.md", "# Draft\n\nA complete publication passage.\n")],
            kind: "fiction"
        )
        let output = testRoot.appendingPathComponent("Cancelled Publication Output", isDirectory: true)
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_PUBLICATION_OUTPUT_PATH"] = output.path
        environment["KISTULENTZ_UI_TEST_PUBLICATION_EXPORT_DELAY_MS"] = "5000"

        launch(environment: environment)
        openProjectCommand("Publish & Export…")
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 8))
        app.staticTexts["Preflight & Export"].firstMatch.click()
        app.buttons["Run Preflight"].click()
        XCTAssertTrue(app.staticTexts["0 errors"].waitForExistence(timeout: 5))
        app.buttons["Choose Output Folder…"].click()

        beginPublicationExport()
        let cancel = app.buttons["CancelActivePublicationExport"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        let export = app.buttons["Export EPUB 3"]
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        XCTAssertTrue(export.isEnabled)
        assertNoPublicationPackageAppears(in: output, timeout: 2.0)

        beginPublicationExport()
        XCTAssertTrue(app.buttons["CancelActivePublicationExport"].waitForExistence(timeout: 3))
        app.buttons["Close"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertNoPublicationPackageAppears(in: output, timeout: 2.0)
        XCTAssertFalse(try String(
            contentsOf: project.root.appendingPathComponent(".kistulentz/publication.json"),
            encoding: .utf8
        ).contains("Cancelled Publish Journey-submission"))
    }

    func testReferenceLibraryWelcomeAlwaysOffersACancelPath() {
        launch(completedOnboarding: true, acknowledgedEnglishPack: true)

        let referenceMenu = referenceControl
        XCTAssertTrue(referenceMenu.waitForExistence(timeout: 8))
        referenceMenu.click()
        let libraryItem = app.menuItems["Reference Library…"]
        XCTAssertTrue(libraryItem.waitForExistence(timeout: 3))
        libraryItem.click()

        let chooseFolder = app.buttons["Choose Library Folder"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.click()
        XCTAssertFalse(chooseFolder.waitForExistence(timeout: 2))
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

        let title = app.staticTexts["What’s New in Kistulentz 0.23.10"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let craftExamplesSummary = app.descendants(matching: .any)["WhatsNewCraftExamples"].firstMatch
        XCTAssertTrue(craftExamplesSummary.exists)
        let writingActivitySummary = app.descendants(matching: .any)["WhatsNewWritingActivity"].firstMatch
        XCTAssertTrue(writingActivitySummary.exists)
        let anaphoraEpistropheSummary = app.descendants(matching: .any)["WhatsNewAnaphoraEpistrophe"].firstMatch
        XCTAssertTrue(anaphoraEpistropheSummary.exists)
        app.buttons["Continue"].click()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
    }

    func testTheLandingPageAppearsOnEveryLaunchNotJustTheFirst() {
        // completedOnboarding: true, suppressLandingPage: false -- this is specifically the normal,
        // already-onboarded, repeat-launch case, not first-run onboarding. The landing page should
        // still greet every launch, in front of whatever document this launch opens.
        launch(completedOnboarding: true, acknowledgedEnglishPack: true, suppressLandingPage: false)

        let title = app.staticTexts["Welcome to Kistulentz"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Create a Project"].exists)
        XCTAssertTrue(app.buttons["Open a Document"].exists)
        XCTAssertTrue(app.buttons["Import Documents"].exists)

        app.buttons["Continue to Editor"].click()
        XCTAssertFalse(title.waitForExistence(timeout: 2))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    private var referenceControl: XCUIElement {
        app.descendants(matching: .any)["ReferenceMenu"].firstMatch
    }

    private func beginPublicationExport() {
        let export = app.buttons["Export EPUB 3"]
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        XCTAssertTrue(export.isEnabled)
        export.click()
        let confirm = app.buttons["ConfirmPublicationExport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
    }

    private func assertNoPublicationPackageAppears(in output: URL, timeout: TimeInterval) {
        let package = output.appendingPathComponent(
            "Cancelled Publish Journey-submission",
            isDirectory: true
        )
        let appearance = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                FileManager.default.fileExists(atPath: package.path)
            },
            object: nil
        )
        appearance.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [appearance], timeout: timeout), .completed)
    }

    private func openSystemCheck() {
        let applicationMenu = app.menuBars.menuBarItems["Kistulentz"].firstMatch
        XCTAssertTrue(applicationMenu.waitForExistence(timeout: 3))
        applicationMenu.click()
        let systemCheckItem = app.menuItems["Kistulentz System Check…"]
        XCTAssertTrue(systemCheckItem.waitForExistence(timeout: 3))
        systemCheckItem.click()
        XCTAssertTrue(app.staticTexts["Kistulentz System Check"].waitForExistence(timeout: 10))
    }
}
