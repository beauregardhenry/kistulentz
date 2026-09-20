import XCTest

@MainActor
final class SelfEditExerciseUITests: KistulentzUITestCase {
    /// "due to the fact that" is a `ReadabilityEngine` complex-phrase pattern with a known,
    /// non-nil `replacement` ("because") -- the one reliably deterministic exercise this suite can
    /// assert on regardless of which categories a given analysis pass happens to also flag. The
    /// sentence is short and plain otherwise so it doesn't also trip hard-sentence, adverb, or
    /// passive-voice detection and turn this into a multi-exercise, order-dependent test.
    func testAttemptIsPreservedThroughRevealOfKistulentzsSuggestion() throws {
        let project = try makeProject(
            name: "Self Edit Journey",
            documents: [
                ("Chapter 1.md", """
                # Chapter 1

                We paused due to the fact that the room was quiet.
                """)
            ]
        )
        launch(environment: project.environment)

        let highlightsMenu = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Writing view and highlights'"))
            .firstMatch
        XCTAssertTrue(highlightsMenu.waitForExistence(timeout: 8))
        highlightsMenu.click()
        let menuItem = app.menuItems["Self-Edit Exercises…"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3))
        menuItem.click()

        // Everything below is scoped to the sheet itself, not the whole app: the regular sidebar
        // behind this modal sheet already shows this same flagged passage and its "because"
        // replacement as part of the ordinary IssueCard flow, so an unscoped text query would
        // match those instead. A plain `.sheet(item:)` presentation is exposed the same way
        // `app.sheets` already reaches `confirmationDialog` presentations elsewhere in this suite
        // (see FinalHardeningUITests).
        //
        // The attempt field is found by type, not by its `.accessibilityIdentifier` -- confirmed
        // directly against a real installed build that `TextEditor` on macOS doesn't reliably
        // surface a custom identifier on its underlying `AXTextArea` the way `app.textViews[id]`
        // needs (a known SwiftUI/AppKit bridging gap, not something this view's own code controls).
        // Since the sheet holds exactly one text view, matching by type alone is unambiguous.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Self-Edit Exercises"].waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["due to the fact that"].waitForExistence(timeout: 3))
        XCTAssertFalse(sheet.staticTexts["because"].exists)

        let attemptField = sheet.textViews.firstMatch
        XCTAssertTrue(attemptField.waitForExistence(timeout: 3))
        attemptField.click()
        attemptField.typeText("because")

        sheet.buttons["Reveal Kistulentz's Suggestion"].click()

        XCTAssertTrue(sheet.staticTexts["because"].waitForExistence(timeout: 3))
        XCTAssertEqual(attemptField.value as? String, "because")

        sheet.buttons["Done"].click()
        XCTAssertFalse(app.sheets.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
