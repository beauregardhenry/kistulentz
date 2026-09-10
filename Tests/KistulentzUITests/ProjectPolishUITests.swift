import Foundation
import XCTest

@MainActor
final class ProjectPolishUITests: KistulentzUITestCase {
    func testProjectPolishSupportsStagesEditedProposalCancelApplyAndOneStepUndo() throws {
        let original = "# Draft\n\nWe utilize tools.\n"
        let edited = "# Draft\n\nWe employ tools.\n"
        let project = try makeProject(
            name: "Polish Project Fixture",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )

        launch(environment: project.environment)
        openProjectCommand("Polish Project…")
        XCTAssertTrue(
            app.descendants(matching: .any)["ProjectPolishView"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Apply in stages"].waitForExistence(timeout: 12))

        let readabilityStage = app.checkBoxes["Clarity & Readability"]
        XCTAssertTrue(readabilityStage.waitForExistence(timeout: 3))
        readabilityStage.click()
        XCTAssertFalse(app.buttons["Apply Included Changes…"].isEnabled)
        readabilityStage.click()
        XCTAssertTrue(app.buttons["Apply Included Changes…"].isEnabled)

        app.buttons["Clear All"].click()
        XCTAssertFalse(app.buttons["Apply Included Changes…"].isEnabled)
        app.buttons["Include All"].click()

        let proposal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Proposed replacement for Draft:'"))
            .firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 5))
        replaceText(in: proposal, with: "We employ tools.\n")

        app.buttons["Apply Included Changes…"].click()
        let cancel = app.descendants(matching: .any)["CancelProjectPolishApply"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(app.staticTexts["Apply in stages"].waitForExistence(timeout: 3))
        XCTAssertEqual(try String(contentsOf: project.root.appendingPathComponent("Draft.md"), encoding: .utf8), original)

        app.buttons["Apply Included Changes…"].click()
        let confirm = app.descendants(matching: .any)["ConfirmProjectPolishApply"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let chapter = project.root.appendingPathComponent("Draft.md")
        waitUntil(description: "Project Polish should persist the edited proposal") {
            (try? String(contentsOf: chapter, encoding: .utf8)) != original
        }
        let appliedText = try String(contentsOf: chapter, encoding: .utf8)
        XCTAssertEqual(appliedText, edited)
        XCTAssertEqual(value(of: editor), edited)
        let undoStatus = try projectUndoStatus()
        XCTAssertTrue(undoStatus.contains("canUndo=true"), undoStatus)

        let undoOutcome = try undoProjectChange(expecting: original)
        XCTAssertTrue(undoOutcome.contains("error=none"), undoOutcome)
        let redoOutcome = try redoProjectChange(expecting: edited)
        XCTAssertTrue(redoOutcome.contains("error=none"), redoOutcome)
    }

    func testProjectPolishMarksAnExternallyChangedPassageStaleWithoutOverwritingIt() throws {
        let original = "# Draft\n\nWe utilize tools.\n"
        let externallyChanged = "# Draft\n\nAn external editor changed this passage.\n"
        let project = try makeProject(
            name: "Stale Polish Fixture",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )
        let chapter = project.root.appendingPathComponent("Draft.md")

        launch(environment: project.environment)
        openProjectCommand("Polish Project…")
        XCTAssertTrue(app.staticTexts["Apply in stages"].waitForExistence(timeout: 12))
        try externallyChanged.write(to: chapter, atomically: true, encoding: .utf8)

        app.buttons["Recheck Included"].click()
        let staleWarning = app.staticTexts.matching(
            NSPredicate(
                format: "value == %@",
                "One or more included passages changed, occur more than once, or overlap another proposal. Review the marked cards; Kistulentz has not changed any file."
            )
        ).firstMatch
        XCTAssertTrue(staleWarning.waitForExistence(timeout: 5))
        XCTAssertEqual(try String(contentsOf: chapter, encoding: .utf8), externallyChanged)
    }

    func testProjectPolishScanCanBeCancelledAndClosedWithoutChangingFiles() throws {
        let first = "# First\n\nWe utilize tools.\n"
        let second = "# Second\n\nWe utilize records.\n"
        let project = try makeProject(
            name: "Slow Polish Fixture",
            documents: [("First.md", first), ("Second.md", second)],
            kind: "nonfiction"
        )
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_PROJECT_POLISH_DELAY_MS"] = "1500"

        launch(environment: environment)
        openProjectCommand("Polish Project…")
        let cancelScan = app.buttons["Cancel Scan"]
        XCTAssertTrue(cancelScan.waitForExistence(timeout: 5))
        cancelScan.click()
        XCTAssertTrue(app.staticTexts["Scan cancelled"].waitForExistence(timeout: 5))
        app.buttons["Close"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        try assertProject(project.root, stillContains: [
            ("First.md", first),
            ("Second.md", second)
        ])

        openProjectCommand("Polish Project…")
        XCTAssertTrue(app.buttons["Cancel Scan"].waitForExistence(timeout: 5))
        app.buttons["Close"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        try assertProject(project.root, stillContains: [
            ("First.md", first),
            ("Second.md", second)
        ])
    }

    private func assertProject(_ root: URL, stillContains documents: [(String, String)]) throws {
        for (path, expected) in documents {
            XCTAssertEqual(
                try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8),
                expected
            )
        }
    }
}
