import XCTest

final class AccessibilityProviderUITests: KistulentzUITestCase {
    func testProviderModelMenusAndPrivacySafeConnectionControlsAreDiscoverable() {
        launch()
        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["ModelPicker-openAI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["ModelPicker-anthropic"].exists)

        let openAITest = app.descendants(matching: .any)["TestConnection-openAI"]
        let anthropicTest = app.descendants(matching: .any)["TestConnection-anthropic"]
        XCTAssertTrue(openAITest.exists)
        XCTAssertTrue(anthropicTest.exists)
        XCTAssertFalse(openAITest.isEnabled)
        XCTAssertFalse(anthropicTest.isEnabled)
        XCTAssertTrue(
            app.staticTexts["This checks only the saved key and selected model. No manuscript, project, reference, or prompt text is sent."]
                .firstMatch.exists
        )
    }

    func testPolishKeyboardShortcutRunsLocalReviewAndUndoTargetsTheAppliedPassage() {
        let original = "# Draft\n\nWe utilize tools.\n"
        launch(environment: ["KISTULENTZ_UI_TEST_DOCUMENT_TEXT": original])
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.buttons["Simpler alternative, utilize, Use a simpler alternative."]
                .waitForExistence(timeout: 8)
        )

        app.typeKey("r", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Review Local Polish"].waitForExistence(timeout: 5))
        let accept = app.buttons["Accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 3))
        accept.click()
        app.buttons["Apply Selected"].click()

        waitUntil(description: "The keyboard-triggered local polish should apply the selected passage") {
            self.value(of: self.editor).contains("We use tools.")
        }
        app.typeKey("z", modifierFlags: .command)
        waitUntil(description: "Undo should unapply the local polish, not remove the scan") {
            self.value(of: self.editor) == original
        }
    }
}
