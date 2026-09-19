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

        XCTAssertTrue(app.staticTexts["Self-Edit Exercises"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["due to the fact that"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["because"].exists)

        let attemptField = app.textViews["SelfEditAttemptField"]
        XCTAssertTrue(attemptField.waitForExistence(timeout: 3))
        attemptField.click()
        attemptField.typeText("because")

        app.buttons["Reveal Kistulentz's Suggestion"].click()

        XCTAssertTrue(app.staticTexts["because"].waitForExistence(timeout: 3))
        XCTAssertEqual(attemptField.value as? String, "because")

        app.buttons["Done"].click()
        XCTAssertFalse(app.staticTexts["Self-Edit Exercises"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
