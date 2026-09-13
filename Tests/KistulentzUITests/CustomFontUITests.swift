import XCTest

@MainActor
final class CustomFontUITests: KistulentzUITestCase {
    func testAddingAndRemovingACustomFontUpdatesTheListImmediately() {
        launch(environment: [
            "KISTULENTZ_UI_TEST_CUSTOM_FONT_PATHS": "/System/Library/Fonts/Supplemental/Chalkduster.ttf"
        ])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 8))

        XCTAssertTrue(app.staticTexts["No custom fonts added yet."].waitForExistence(timeout: 5))

        let addButton = app.descendants(matching: .any)["AddCustomFont"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        XCTAssertTrue(app.staticTexts["Chalkduster"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["No custom fonts added yet."].exists)

        app.buttons["Remove"].click()

        XCTAssertTrue(app.staticTexts["No custom fonts added yet."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Chalkduster"].exists)
    }
}
