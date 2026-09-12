import XCTest

@MainActor
final class ManuscriptInsightsUITests: KistulentzUITestCase {
    func testBetaReaderRunsLocallyAndProducesFeedbackForTheOpenChapter() throws {
        let project = try makeProject(
            name: "Insights Journey",
            documents: [
                ("Chapter 1.md", """
                # Chapter 1

                Alice met Alicia in Chicago on Monday. Alice carefully reviewed the evidence.
                Research proves the change caused a 25% improvement in 2025.
                The repeated silver signal appeared. The repeated silver signal appeared.
                "We should verify it," Alice said.
                """)
            ]
        )
        launch(environment: project.environment)

        openProjectCommand("Manuscript Insights…")
        XCTAssertTrue(app.staticTexts["Manuscript Insights"].waitForExistence(timeout: 5))

        app.radioButtons["Beta Readers"].click()
        // "General Reader" is already visible in the sidebar list before any run, so it isn't
        // useful as a sign the run finished; "Strengths"/"Concerns"/"Questions" only render
        // inside a feedback card the run actually produced.
        XCTAssertFalse(app.staticTexts["Strengths"].exists)

        let runLocally = app.buttons["Run Locally"]
        XCTAssertTrue(runLocally.waitForExistence(timeout: 3))
        XCTAssertTrue(runLocally.isEnabled)
        runLocally.click()

        XCTAssertTrue(app.staticTexts["Strengths"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Concerns"].exists)
        XCTAssertTrue(app.staticTexts["Questions"].exists)

        app.buttons["Done"].click()
        XCTAssertFalse(app.staticTexts["Manuscript Insights"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
