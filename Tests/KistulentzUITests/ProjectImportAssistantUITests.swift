import Foundation
import XCTest

@MainActor
final class ProjectImportAssistantUITests: KistulentzUITestCase {
    func testMixedRealDocumentsReorderContinuePastFailureRetryAndWriteCombinedMarkdown() throws {
        let first = testRoot.appendingPathComponent("A-first.txt")
        let second = testRoot.appendingPathComponent("B-second.md")
        let broken = testRoot.appendingPathComponent("Broken.docx")
        let output = testRoot.appendingPathComponent("Combined Manuscript.md")
        try "First source paragraph.\n".write(to: first, atomically: true, encoding: .utf8)
        try "# Second\n\nSecond source paragraph.\n".write(to: second, atomically: true, encoding: .utf8)
        try Data("not a Word package".utf8).write(to: broken)

        let realDocuments = [
            fixture("RealImports/macOS-Saved.docx"),
            fixture("RealImports/macOS-Saved.rtf"),
            fixture("RealImports/macOS-Saved.rtfd"),
            fixture("RealImports/macOS-Saved.html"),
            fixture("RealImports/macOS-Saved.odt"),
            fixture("RealImports/Fixture-Source.txt")
        ]
        let sources = [first, second] + realDocuments + [broken]

        launch(environment: [
            "KISTULENTZ_UI_TEST_IMPORT_PATHS": sources.map(\.path).joined(separator: "\n"),
            "KISTULENTZ_UI_TEST_IMPORT_OUTPUT_PATH": output.path
        ])
        openProjectImportAssistant()
        let moveFirstLater = app.buttons["Move A-first later"]
        XCTAssertTrue(moveFirstLater.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["Move B-second earlier"].exists)
        moveFirstLater.click()
        app.buttons["Convert and Preview"].click()

        XCTAssertTrue(app.staticTexts["8 converted"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["1 failed"].exists)
        XCTAssertTrue(app.buttons["Retry Failed"].isEnabled)
        app.buttons["Retry Failed"].click()
        XCTAssertTrue(app.staticTexts["1 failed"].waitForExistence(timeout: 10))

        app.buttons["Save Combined Markdown…"].click()
        waitUntil(timeout: 15, description: "The combined Markdown output should be written") {
            FileManager.default.fileExists(atPath: output.path)
        }
        let combined = try String(contentsOf: output, encoding: .utf8)
        let secondRange = try XCTUnwrap(combined.range(of: "## B-second"))
        let firstRange = try XCTUnwrap(combined.range(of: "## A-first"))
        XCTAssertLessThan(secondRange.lowerBound, firstRange.lowerBound)
        XCTAssertTrue(combined.contains("Real Application Fixture"))
        XCTAssertFalse(combined.contains("Broken"))
    }

    func testNewProjectDestinationWritesSeparateDocumentsAndOpensTheProject() throws {
        let first = testRoot.appendingPathComponent("Opening.md")
        let second = testRoot.appendingPathComponent("Evidence.txt")
        let parent = testRoot.appendingPathComponent("Imported Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try "# Opening\n\nThe opening passage.\n".write(to: first, atomically: true, encoding: .utf8)
        try "Evidence for the second section.\n".write(to: second, atomically: true, encoding: .utf8)

        launch(environment: [
            "KISTULENTZ_UI_TEST_IMPORT_PATHS": [first.path, second.path].joined(separator: "\n"),
            "KISTULENTZ_UI_TEST_IMPORT_PROJECT_PARENT": parent.path
        ])
        openProjectImportAssistant()
        XCTAssertTrue(app.buttons["Move Opening later"].waitForExistence(timeout: 12))
        app.buttons["Convert and Preview"].click()
        XCTAssertTrue(app.staticTexts["2 converted"].waitForExistence(timeout: 12))

        let destination = app.popUpButtons.matching(
            NSPredicate(format: "value == 'One combined Markdown file'")
        ).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        destination.click()
        app.menuItems["A new Kistulentz project"].click()

        let projectName = app.textFields["Project name"]
        XCTAssertTrue(projectName.waitForExistence(timeout: 3))
        replaceText(in: projectName, with: "Imported UI Project")
        app.buttons["Create and Open Project"].click()

        let root = parent.appendingPathComponent("Imported UI Project", isDirectory: true)
        waitUntil(timeout: 15, description: "The separate-document project should be created") {
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Opening.md").path)
                && FileManager.default.fileExists(atPath: root.appendingPathComponent("Evidence.md").path)
        }
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == 'Project: Imported UI Project'"))
                .firstMatch.waitForExistence(timeout: 8)
        )
    }

    func testConversionCanBeCancelledWithoutWritingOutput() throws {
        var sources: [URL] = []
        for index in 1...4 {
            let url = testRoot.appendingPathComponent("Slow \(index).md")
            try "# Slow \(index)\n\nText.\n".write(to: url, atomically: true, encoding: .utf8)
            sources.append(url)
        }
        let output = testRoot.appendingPathComponent("Should Not Exist.md")

        launch(environment: [
            "KISTULENTZ_UI_TEST_IMPORT_PATHS": sources.map(\.path).joined(separator: "\n"),
            "KISTULENTZ_UI_TEST_IMPORT_OUTPUT_PATH": output.path,
            "KISTULENTZ_UI_TEST_IMPORT_DELAY_MS": "800"
        ])
        openProjectImportAssistant()
        XCTAssertTrue(app.buttons["Move Slow 1 later"].waitForExistence(timeout: 12))
        app.buttons["Convert and Preview"].click()

        let cancel = app.buttons["Cancel Conversion"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
        app.buttons["Close"].click()
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(app.windows.firstMatch.exists)
    }
}
