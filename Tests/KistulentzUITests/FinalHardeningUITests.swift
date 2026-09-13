import Foundation
import XCTest

@MainActor
final class FinalHardeningUITests: KistulentzUITestCase {
    func testProjectSearchCancelsStaleQueriesAndNavigatesToTheMatchingDocument() throws {
        let first = "# Opening\n\nNothing relevant appears here.\n"
        let second = "# Discovery\n\nThe copper lighthouse is the unique clue.\n"
        let project = try makeProject(
            name: "Search Journey",
            documents: [("Opening.md", first), ("Discovery.md", second)]
        )
        launch(environment: project.environment)

        let search = app.descendants(matching: .any)["ProjectSearchField"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        replaceText(in: search, with: "lighthouse")
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'ProjectSearchResult-'"))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))

        replaceText(in: search, with: "phrase-that-does-not-exist")
        XCTAssertFalse(result.waitForExistence(timeout: 2))
        replaceText(in: search, with: "lighthouse")
        let refreshedResult = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'ProjectSearchResult-'"))
            .firstMatch
        XCTAssertTrue(refreshedResult.waitForExistence(timeout: 8))
        refreshedResult.click()

        waitUntil(description: "Opening a search result should select its source document") {
            self.value(of: self.editor) == second
        }
    }

    func testProjectBibleAndCustomBetaReaderPersistAcrossRelaunch() throws {
        let project = try makeProject(
            name: "Insights Journey",
            documents: [("Draft.md", "# Draft\n\nMara crosses the frozen river before dawn.\n")]
        )
        launch(environment: project.environment)
        openProjectCommand("Manuscript Insights…")
        XCTAssertTrue(app.staticTexts["Manuscript Insights"].waitForExistence(timeout: 8))

        selectInsightsTab("Bible")
        let bible = app.descendants(matching: .any)["ProjectBibleEditor"].firstMatch
        XCTAssertTrue(bible.waitForExistence(timeout: 5))
        waitUntil(description: "Automatic local analysis should settle before the Bible is edited") {
            !self.app.staticTexts["Updating locally…"].exists
        }
        let authoredBible = "# Story Bible\n\n## Continuity\nMara carries a brass compass.\n"
        replaceText(in: bible, with: authoredBible)

        selectInsightsTab("Beta Readers")
        let addReader = app.buttons["Reader"].firstMatch
        XCTAssertTrue(addReader.waitForExistence(timeout: 5))
        addReader.click()
        XCTAssertTrue(app.staticTexts["New Custom Beta Reader"].waitForExistence(timeout: 3))
        replaceText(
            in: app.descendants(matching: .any)["CustomBetaReaderName"].firstMatch,
            with: "Continuity Scout"
        )
        replaceText(
            in: app.descendants(matching: .any)["CustomBetaReaderFocus"].firstMatch,
            with: "Track objects, travel time, and character knowledge."
        )
        app.buttons["SaveCustomBetaReader"].click()
        XCTAssertTrue(app.staticTexts["Continuity Scout"].waitForExistence(timeout: 5))

        let run = app.buttons["RunLocalBetaReader"]
        XCTAssertTrue(run.waitForExistence(timeout: 3))
        run.click()
        let feedback = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'BetaReaderFeedback-'"))
            .firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 8))
        app.buttons["Done"].click()

        let bibleURL = project.root.appendingPathComponent("Kistulentz Bible.md")
        waitUntil(description: "The authored Bible should be saved before the window closes") {
            (try? String(contentsOf: bibleURL, encoding: .utf8)) == authoredBible
        }
        let readersURL = project.root.appendingPathComponent(".kistulentz/beta-readers.json")
        XCTAssertTrue(try String(contentsOf: readersURL, encoding: .utf8).contains("Continuity Scout"))

        relaunch()
        openProjectCommand("Manuscript Insights…")
        selectInsightsTab("Bible")
        let reopenedBible = app.descendants(matching: .any)["ProjectBibleEditor"].firstMatch
        XCTAssertTrue(reopenedBible.waitForExistence(timeout: 5))
        let reopenedBibleText = value(of: reopenedBible)
        XCTAssertTrue(reopenedBibleText.hasPrefix(authoredBible.trimmingCharacters(in: .newlines)))
        XCTAssertTrue(reopenedBibleText.contains("Mara carries a brass compass."))
        XCTAssertTrue(reopenedBibleText.contains("<!-- kistulentz:managed-bible:start -->"))
        selectInsightsTab("Beta Readers")
        XCTAssertTrue(app.staticTexts["Continuity Scout"].waitForExistence(timeout: 5))
    }

    func testNamedSnapshotRestoreAndHistorySurviveRelaunch() throws {
        let original = "# Draft\n\nThe first stable version.\n"
        let revised = "# Draft\n\nThe deliberately revised version.\n"
        let project = try makeProject(
            name: "Snapshot Journey",
            documents: [("Draft.md", original)]
        )
        launch(environment: project.environment)

        openProjectCommand("Create Snapshot…")
        XCTAssertTrue(app.staticTexts["Create Snapshot"].waitForExistence(timeout: 5))
        replaceText(in: app.descendants(matching: .any)["SnapshotName"].firstMatch, with: "Before revision")
        app.buttons["CreateNamedSnapshot"].click()
        try replaceEditorText(with: revised)

        openProjectCommand("Revision History…")
        XCTAssertTrue(app.staticTexts["Revision History"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Before revision"].waitForExistence(timeout: 5))
        let restore = app.buttons["Restore…"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        restore.click()
        let confirm = app.sheets.firstMatch.buttons["Restore Snapshot"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        waitForHittable(confirm, timeout: 3)
        confirm.click()
        waitUntil(description: "Restoring a snapshot should put its exact bytes in the editor") {
            self.value(of: self.editor) == original
        }
        let historyIndex = project.root.appendingPathComponent(".kistulentz/history/index.json")
        waitUntil(description: "Restoring should persist a protective pre-restore snapshot") {
            self.snapshotReasons(in: historyIndex).contains("Before restoring Before revision")
        }

        relaunch()
        XCTAssertEqual(value(of: editor), original)
        openProjectCommand("Revision History…")
        XCTAssertTrue(app.staticTexts["Before revision"].waitForExistence(timeout: 5))
        XCTAssertTrue(snapshotReasons(in: historyIndex).contains("Before restoring Before revision"))
    }

    func testReadingGradeSettingPersistsAcrossRelaunch() {
        launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 8))
        let grade = app.descendants(matching: .any)["TargetReadingGrade"].firstMatch
        XCTAssertTrue(grade.waitForExistence(timeout: 5))
        grade.click()
        let gradeEleven = app.menuItems["Grade 11"]
        XCTAssertTrue(gradeEleven.waitForExistence(timeout: 3))
        gradeEleven.click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertFalse(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 3))

        relaunch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 8))
        let reopenedGrade = app.descendants(matching: .any)["TargetReadingGrade"].firstMatch
        XCTAssertTrue(reopenedGrade.waitForExistence(timeout: 5))
        XCTAssertEqual(value(of: reopenedGrade), "Grade 11")
    }

    func testBeneparFailureRetryInstallationAndRemovalRemainRecoverable() {
        launch(environment: [
            "KISTULENTZ_UI_TEST_BENEPAR_INSTALL_SEQUENCE": "failure,success"
        ])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 8))

        installBeneparFromSettings()
        let failure = app.staticTexts["The simulated English language-pack download failed. Try again."]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        let acknowledgeFailure = app.sheets.firstMatch.buttons["OK"]
        XCTAssertTrue(acknowledgeFailure.waitForExistence(timeout: 3))
        waitForHittable(acknowledgeFailure, timeout: 3)
        acknowledgeFailure.click()
        XCTAssertTrue(app.buttons["InstallBeneparPack"].waitForExistence(timeout: 3))

        installBeneparFromSettings()
        let remove = app.buttons["RemoveBeneparPack"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        let status = app.descendants(matching: .any)["BeneparPackStatus"].firstMatch
        XCTAssertTrue(status.label.contains("ui-test") || value(of: status).contains("ui-test"))

        remove.click()
        let confirmRemoval = app.sheets.firstMatch.buttons["Remove"]
        XCTAssertTrue(confirmRemoval.waitForExistence(timeout: 3))
        waitForHittable(confirmRemoval, timeout: 3)
        confirmRemoval.click()
        XCTAssertTrue(app.buttons["InstallBeneparPack"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["English language pack removed. Native analysis remains active."].exists)
    }

    func testDOCXPublicationCompletesThroughTheRealInterface() throws {
        try assertPublicationExport(format: "DOCX", expectedFilename: "DOCX Journey.docx", signature: "PK")
    }

    func testReaderPDFPublicationCompletesThroughTheRealInterface() throws {
        try assertPublicationExport(
            format: "Reader PDF",
            expectedFilename: "Reader PDF Journey-reader.pdf",
            signature: "%PDF"
        )
    }

    func testDestinkFiltersAndNavigatesToAFindingInAnotherDocument() throws {
        let first = "# Opening\n\nPlain language carries this chapter.\n"
        let second = "# Discovery\n\nWe utilize a robust tapestry to move the needle.\n"
        let project = try makeProject(
            name: "Destink Navigation",
            documents: [("Opening.md", first), ("Discovery.md", second)]
        )
        launch(environment: project.environment)
        app.buttons["De-stink"].click()
        XCTAssertTrue(app.staticTexts["De-stink Review"].waitForExistence(timeout: 5))

        selectPopup(identifier: "DestinkScope", item: "Whole Manuscript")
        XCTAssertTrue(app.descendants(matching: .any)["DestinkScoreSummary"].waitForExistence(timeout: 8))
        let category = app.descendants(matching: .any)["DestinkCategory"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.click()
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.enter, modifierFlags: [])
        waitUntil(description: "The category picker should filter to word-choice findings") {
            self.value(of: category).hasPrefix("Word choice")
        }

        let show = app.buttons.matching(
            NSPredicate(format: "label CONTAINS ' in Discovery'")
        ).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 8))
        show.click()
        waitUntil(description: "A De-stink finding should navigate to its source document") {
            self.value(of: self.editor) == second
        }
    }

    func testLargeDestinkRunCanBeCancelledWithoutHangingTheEditor() throws {
        let repeated = Array(repeating: "We utilize a robust framework to move the needle.", count: 8_000)
            .joined(separator: "\n")
        let project = try makeProject(
            name: "Destink Cancellation",
            documents: [("Large.md", "# Large\n\n\(repeated)\n")]
        )
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_DESTINK_DELAY_MS"] = "5000"
        launch(environment: environment)
        app.buttons["De-stink"].click()

        let cancel = app.buttons["CancelDestinkAnalysis"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(app.buttons["RunDestinkAnalysis"].waitForExistence(timeout: 3))
        app.buttons["Done"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.isHittable)
    }

    private func selectInsightsTab(_ title: String) {
        let radioButton = app.radioButtons[title].firstMatch
        if radioButton.waitForExistence(timeout: 2) {
            radioButton.click()
            return
        }
        let segment = app.segmentedControls.buttons[title].firstMatch
        if segment.waitForExistence(timeout: 2) {
            segment.click()
            return
        }
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.click()
    }

    private func selectPopup(identifier: String, item: String) {
        let picker = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        var menuItem = app.menuItems[item]
        if !menuItem.waitForExistence(timeout: 1) {
            menuItem = app.menuItems.matching(
                NSPredicate(format: "label BEGINSWITH %@", item)
            ).firstMatch
        }
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3))
        menuItem.click()
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline {
            usleep(50_000) // 50ms
        }
        XCTAssertTrue(element.isHittable, "The confirmation control did not become clickable in time.")
    }

    private func installBeneparFromSettings() {
        let install = app.buttons["InstallBeneparPack"]
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        install.click()
        let confirm = app.sheets.firstMatch.buttons["Download and Install"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        waitForHittable(confirm, timeout: 3)
        confirm.click()
    }

    private func snapshotReasons(in indexURL: URL) -> [String] {
        guard let data = try? Data(contentsOf: indexURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshots = object["snapshots"] as? [[String: Any]] else { return [] }
        return snapshots.compactMap { $0["reason"] as? String }
    }

    private func assertPublicationExport(
        format: String,
        expectedFilename: String,
        signature: String
    ) throws {
        let projectName = format == "DOCX" ? "DOCX Journey" : "Reader PDF Journey"
        let project = try makeProject(
            name: projectName,
            documents: [("Draft.md", "# Draft\n\nA complete manuscript with a reliable ending.\n")]
        )
        let output = testRoot.appendingPathComponent("\(projectName) Output", isDirectory: true)
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_PUBLICATION_OUTPUT_PATH"] = output.path
        launch(environment: environment)
        openProjectCommand("Publish & Export…")
        XCTAssertTrue(app.descendants(matching: .any)["PublicationFormatPicker"].waitForExistence(timeout: 8))

        selectPopup(identifier: "PublicationFormatPicker", item: format)
        let genericDestination = app.checkBoxes["Generic EPUB 3.3"].firstMatch
        if genericDestination.exists, value(of: genericDestination) != "0" {
            genericDestination.click()
        }
        app.staticTexts["Preflight & Export"].firstMatch.click()
        app.buttons["Run Preflight"].click()
        XCTAssertTrue(app.staticTexts["0 errors"].waitForExistence(timeout: 8))
        app.buttons["ChoosePublicationOutputFolder"].click()
        let export = app.buttons["ExportPublication"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(export.isEnabled)
        export.click()
        let warningConfirmation = app.buttons["ConfirmPublicationExport"]
        if warningConfirmation.waitForExistence(timeout: 2) {
            warningConfirmation.click()
        }

        let package = output.appendingPathComponent("\(projectName)-submission", isDirectory: true)
        let publication = package.appendingPathComponent(expectedFilename)
        waitUntil(timeout: 25, description: "The \(format) publication should finish") {
            FileManager.default.fileExists(atPath: publication.path)
        }
        let prefix = try String(
            decoding: Data(contentsOf: publication).prefix(signature.utf8.count),
            as: UTF8.self
        )
        XCTAssertEqual(prefix, signature)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.appendingPathComponent("Submission Readiness Report.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.appendingPathComponent("SHA256SUMS.txt").path
        ))
    }
}
