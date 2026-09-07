import AppKit
import Darwin
import Foundation
import XCTest

final class EditingRecoveryUITests: KistulentzUITestCase {
    func testProjectEditPersistsAcrossRelaunchAndUndoRedo() throws {
        let original = "We utilize tools."
        let revised = "We use clear tools."
        let project = try makeProject(
            name: "Persistence Project",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )

        launch(environment: project.environment)
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertTrue(value(of: editor).contains("We utilize tools."))

        try replaceEditorText(with: revised)
        XCTAssertEqual(value(of: editor), revised)

        try undoEditorText(expecting: original)
        try redoEditorText(expecting: revised)

        let chapterURL = project.root.appendingPathComponent("Draft.md")
        waitUntil(description: "The project autosave should reach disk") {
            (try? String(contentsOf: chapterURL, encoding: .utf8)) == revised
        }

        app.terminate()
        relaunch()
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(value(of: editor), revised)
    }

    func testForcedCrashOffersRecoveryAndCanSaveARecoveredCopy() throws {
        let recoveryDirectory = testRoot.appendingPathComponent("Recovery", isDirectory: true)
        let recoveredCopy = testRoot.appendingPathComponent("Recovered Copy.md")
        let recoveredText = "This sentence survived an interrupted session."
        let environment = [
            "KISTULENTZ_UI_TEST_DOCUMENT_TEXT": "Saved text.",
            "KISTULENTZ_UI_TEST_RECOVERY_DIRECTORY": recoveryDirectory.path,
            "KISTULENTZ_UI_TEST_RECOVERY_COPY_PATH": recoveredCopy.path
        ]

        launch(environment: environment)
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        try replaceEditorText(with: recoveredText)
        waitUntil(description: "Editing should create a recovery journal before the crash") {
            let files = try? FileManager.default.contentsOfDirectory(atPath: recoveryDirectory.path)
            return files?.contains(where: { $0.hasSuffix(".json") }) == true
        }

        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.beauhenry.kistulentz"
        )
        guard let runningApplication = runningApplications.first(where: \.isActive)
            ?? runningApplications.last else {
            return XCTFail("The launched Kistulentz process could not be located")
        }
        let processID = runningApplication.processIdentifier
        XCTAssertEqual(Darwin.kill(processID, SIGKILL), 0)
        waitUntil(description: "The test host should stop after the forced crash") {
            self.app.state == .notRunning
        }

        relaunch()
        XCTAssertTrue(app.staticTexts["Draft Recovery Review"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["Recovered draft text"].exists)

        let saveCopy = app.descendants(matching: .any)["SaveRecoveredCopy"]
        XCTAssertTrue(saveCopy.waitForExistence(timeout: 3))
        saveCopy.click()
        waitUntil(description: "Saving a recovered copy should preserve the complete recovered text") {
            (try? String(contentsOf: recoveredCopy, encoding: .utf8)) == recoveredText
        }
        XCTAssertTrue(app.staticTexts["No Drafts Need Recovery"].waitForExistence(timeout: 5))
    }

    func testRecoveryRefusesToReplaceAFileChangedAfterPreview() throws {
        let original = testRoot.appendingPathComponent("Original.md")
        let recoveryDirectory = testRoot.appendingPathComponent("Recovery", isDirectory: true)
        try "# Saved\n\nOriginal version.\n".write(to: original, atomically: true, encoding: .utf8)
        try writeRecoveryEntry(
            directory: recoveryDirectory,
            original: original,
            recoveredText: "# Saved\n\nRecovered version.\n",
            title: "Original.md"
        )

        launch(environment: [
            "KISTULENTZ_UI_TEST_RECOVERY_DIRECTORY": recoveryDirectory.path
        ])
        XCTAssertTrue(app.staticTexts["Draft Recovery Review"].waitForExistence(timeout: 8))
        let requestReplace = app.descendants(matching: .any)["RequestReplaceSavedFile"]
        XCTAssertTrue(requestReplace.waitForExistence(timeout: 5))
        waitUntil(description: "Replacement should enable after the saved-file preview loads") {
            requestReplace.isEnabled
        }

        let externalText = "# Saved\n\nChanged by another editor.\n"
        try externalText.write(to: original, atomically: true, encoding: .utf8)
        requestReplace.click()
        let confirm = app.descendants(matching: .any)["ConfirmReplaceSavedFile"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()

        XCTAssertTrue(
            app.staticTexts["The saved file changed after the recovery preview loaded. Reload the preview before replacing it."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), externalText)
    }
}
