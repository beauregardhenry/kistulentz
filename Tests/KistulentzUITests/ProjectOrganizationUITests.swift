import XCTest

@MainActor
final class ProjectOrganizationUITests: KistulentzUITestCase {
    func testAddReorderSplitUndoRedoAndReopenProjectOrganization() throws {
        let splitText = """
        # Splittable Chapter

        A short chapter preface.

        ## Opening Scene

        Mara opens the sealed door.

        ## Conflict Scene

        The alarm answers her.
        """
        let splitResultText = "# Splittable Chapter\n\nA short chapter preface.\n"
        let project = try makeProject(
            name: "Organization Journey",
            documents: [
                ("01 First.md", "# First Chapter\n\nThe first chapter remains selected.\n"),
                ("02 Second.md", "# Second Chapter\n\nThe second chapter moves earlier.\n"),
                ("03 Splittable.md", splitText)
            ]
        )
        launch(environment: project.environment)
        openOrganization()

        app.radioButtons["Outliner"].click()
        let moveSecondEarlier = app.buttons["Move Second Chapter earlier"]
        XCTAssertTrue(moveSecondEarlier.waitForExistence(timeout: 5))
        moveSecondEarlier.click()

        app.staticTexts["Splittable Chapter"].firstMatch.click()
        let split = app.buttons["Split Headings into Scenes…"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        split.click()
        XCTAssertTrue(app.staticTexts["Split Chapter Headings"].waitForExistence(timeout: 5))
        let createScenes = app.buttons["Create 2 Files"]
        XCTAssertTrue(createScenes.isEnabled)
        createScenes.click()

        let opening = project.root.appendingPathComponent("Opening Scene.md")
        let conflict = project.root.appendingPathComponent("Conflict Scene.md")
        waitUntil(description: "Heading split should create both scene files") {
            FileManager.default.fileExists(atPath: opening.path)
                && FileManager.default.fileExists(atPath: conflict.path)
        }

        let add = app.descendants(matching: .any)["AddOutlineItem"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        let addChapter = app.menuItems["Chapter"]
        XCTAssertTrue(addChapter.waitForExistence(timeout: 3))
        addChapter.click()
        let title = app.descendants(matching: .any)["NewOutlineItemTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceText(in: title, with: "Appendix")
        app.buttons["Create"].click()
        XCTAssertTrue(app.staticTexts["Appendix"].waitForExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.root.appendingPathComponent("Appendix.md").path))

        app.buttons["Done"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let undoStatus = try undoProjectChange(expecting: splitText)
        XCTAssertTrue(undoStatus.contains("error=none"), undoStatus)
        XCTAssertFalse(FileManager.default.fileExists(atPath: opening.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: conflict.path))

        let redoStatus = try redoProjectChange(expecting: splitResultText)
        XCTAssertTrue(redoStatus.contains("error=none"), redoStatus)
        XCTAssertTrue(FileManager.default.fileExists(atPath: opening.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflict.path))

        app.terminate()
        relaunch()
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        openOrganization()
        app.radioButtons["Outliner"].click()
        XCTAssertTrue(app.staticTexts["Opening Scene"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Conflict Scene"].exists)
        XCTAssertTrue(app.staticTexts["Appendix"].exists)

        let outline = try String(
            contentsOf: project.root.appendingPathComponent(".kistulentz/outline.json"),
            encoding: .utf8
        )
        let second = try XCTUnwrap(outline.range(of: "Second Chapter"))
        let first = try XCTUnwrap(outline.range(of: "First Chapter"))
        XCTAssertLessThan(second.lowerBound, first.lowerBound)
        XCTAssertTrue(outline.contains("Opening Scene"))
        XCTAssertTrue(outline.contains("Conflict Scene"))
    }

    private func openOrganization() {
        openProjectCommand("Project Organization…")
        XCTAssertTrue(app.staticTexts["Project Organization"].waitForExistence(timeout: 5))
    }
}
