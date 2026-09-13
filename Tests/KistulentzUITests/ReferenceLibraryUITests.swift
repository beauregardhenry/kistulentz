import XCTest

@MainActor
final class ReferenceLibraryUITests: KistulentzUITestCase {
    func testRealEPUBImportCombinesReferencesAndPreviewsLocalDeepeningBeforeUse() throws {
        let library = testRoot.appendingPathComponent("Reference Library", isDirectory: true)
        let north = try makeFixtureEPUB(
            named: "Lantern North.epub",
            title: "Lantern North",
            author: "Avery North"
        )
        let south = try makeFixtureEPUB(
            named: "Lantern South.epub",
            title: "Lantern South",
            author: "Robin South"
        )

        launch(
            environment: [
                "KISTULENTZ_UI_TEST_REFERENCE_LIBRARY_PATH": library.path,
                "KISTULENTZ_UI_TEST_REFERENCE_EPUB_PATHS": [north.path, south.path].joined(separator: "\n")
            ],
            arguments: ["-selectedAIProvider", "ollama", "-ollamaModel", "llama3.2:3b"]
        )
        openReferenceLibrary()
        app.buttons["Choose Library Folder"].click()

        let importMenu = app.descendants(matching: .any)["ReferenceLibraryImport"].firstMatch
        XCTAssertTrue(importMenu.waitForExistence(timeout: 8))
        importMenu.click()
        let addFiles = app.menuItems["Add EPUB Files…"]
        XCTAssertTrue(addFiles.waitForExistence(timeout: 3))
        addFiles.click()

        let northChoice = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Lantern North,'")
        ).firstMatch
        let southChoice = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Lantern South,'")
        ).firstMatch
        XCTAssertTrue(northChoice.waitForExistence(timeout: 15))
        XCTAssertTrue(southChoice.waitForExistence(timeout: 5))
        northChoice.click()
        southChoice.click()
        XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 3))

        XCTAssertTrue(
            app.staticTexts["Install the optional English language pack in Settings to add Benepar structural profiles."]
                .exists
        )
        let structure = app.descendants(matching: .any)["ReferenceStructureAnalysis"].firstMatch
        XCTAssertTrue(structure.exists)
        XCTAssertFalse(structure.isEnabled)

        app.descendants(matching: .any)["DeepenReferenceLibrary"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Preview Reference Analysis"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["This request stays on this Mac. Review the local material below before running it."]
                .exists
        )
        XCTAssertTrue(app.buttons["Deepen Reference"].isEnabled)
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertFalse(app.staticTexts["Preview Reference Analysis"].waitForExistence(timeout: 3))

        app.buttons["Use Selected"].click()
        XCTAssertFalse(importMenu.waitForExistence(timeout: 3))
        waitUntil(description: "The combined reference should be visible in the editor toolbar") {
            let control = self.app.descendants(matching: .any)["ReferenceMenu"].firstMatch
            return control.label.contains("2 combined references")
                || self.value(of: control).contains("2 combined references")
        }

        let markdownURL = library.appendingPathComponent("Kistulentz Library.md")
        waitUntil(description: "The imported EPUBs should be checkpointed to Markdown") {
            FileManager.default.fileExists(atPath: markdownURL.path)
        }
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Lantern North"))
        XCTAssertTrue(markdown.contains("Lantern South"))
        XCTAssertTrue(markdown.contains("Avery North"))
        XCTAssertTrue(markdown.contains("Robin South"))
    }

    func testSlowEPUBBatchCanBeCancelledAndTheLibraryCanClose() throws {
        let library = testRoot.appendingPathComponent("Cancelled Reference Library", isDirectory: true)
        let epubs = try (1...5).map { index in
            try makeFixtureEPUB(
                named: "Slow Reference \(index).epub",
                title: "Slow Reference \(index)",
                author: "Cancellation Fixture"
            )
        }

        launch(environment: [
            "KISTULENTZ_UI_TEST_REFERENCE_LIBRARY_PATH": library.path,
            "KISTULENTZ_UI_TEST_REFERENCE_EPUB_PATHS": epubs.map(\.path).joined(separator: "\n"),
            "KISTULENTZ_UI_TEST_REFERENCE_IMPORT_DELAY_MS": "750"
        ])
        openReferenceLibrary()
        app.buttons["Choose Library Folder"].click()
        let importMenu = app.descendants(matching: .any)["ReferenceLibraryImport"].firstMatch
        XCTAssertTrue(importMenu.waitForExistence(timeout: 8))
        importMenu.click()
        app.menuItems["Add EPUB Files…"].click()

        let progress = app.progressIndicators["EPUB import progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertFalse(progress.waitForExistence(timeout: 3))

        let done = app.buttons["Done"]
        XCTAssertTrue(done.isEnabled)
        done.click()
        XCTAssertFalse(done.waitForExistence(timeout: 3))
        XCTAssertTrue(app.windows.firstMatch.exists)

        let indexURL = library.appendingPathComponent(".kistulentz/library.json")
        let markdownURL = library.appendingPathComponent("Kistulentz Library.md")
        waitUntil(description: "Cancellation should leave a recoverable reference library") {
            FileManager.default.fileExists(atPath: indexURL.path)
                && FileManager.default.fileExists(atPath: markdownURL.path)
        }
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)))
    }

    private func openReferenceLibrary() {
        let reference = app.descendants(matching: .any)["ReferenceMenu"].firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 8))
        reference.click()
        let item = app.menuItems["Reference Library…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
        XCTAssertTrue(app.buttons["Choose Library Folder"].waitForExistence(timeout: 5))
    }
}
