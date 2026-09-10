import XCTest

@MainActor
final class OnboardingLocalSetupUITests: KistulentzUITestCase {
    func testFirstRunCreatesANonfictionProjectInTheChosenFolder() throws {
        let parent = testRoot.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        launch(
            completedOnboarding: false,
            environment: ["KISTULENTZ_UI_TEST_PROJECT_FOLDER_PATH": parent.path]
        )

        XCTAssertTrue(app.staticTexts["Welcome to Kistulentz"].waitForExistence(timeout: 8))
        app.buttons["Create a Project"].click()
        XCTAssertTrue(app.staticTexts["New Kistulentz Project"].waitForExistence(timeout: 5))
        let name = app.descendants(matching: .any)["ProjectConfigurationName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        replaceText(in: name, with: "Field Notes")
        app.radioButtons["Nonfiction"].click()
        app.buttons["Create Project"].click()

        let root = parent.appendingPathComponent("Field Notes", isDirectory: true)
        XCTAssertTrue(app.staticTexts["Field Notes"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Nonfiction"].exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Draft.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".kistulentz/project.json").path))
        XCTAssertEqual(value(of: editor), "# Draft\n\nBegin the manuscript here.\n")
    }

    func testOpenProjectPreparesAnExistingMarkdownFolderWithoutReplacingItsDraft() throws {
        let root = testRoot.appendingPathComponent("Existing Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = "# Existing Essay\n\nKeep this exact draft.\n"
        let draft = root.appendingPathComponent("Essay.md")
        try original.write(to: draft, atomically: true, encoding: .utf8)
        launch(environment: ["KISTULENTZ_UI_TEST_PROJECT_FOLDER_PATH": root.path])

        let projects = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Projects'"))
            .firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 8))
        projects.click()
        app.menuItems["Open Project…"].click()
        XCTAssertTrue(app.staticTexts["Set Up Project Folder"].waitForExistence(timeout: 5))
        app.radioButtons["Nonfiction"].click()
        app.buttons["Use This Folder"].click()

        XCTAssertTrue(app.staticTexts["Existing Drafts"].waitForExistence(timeout: 8))
        XCTAssertEqual(value(of: editor), original)
        XCTAssertEqual(try String(contentsOf: draft, encoding: .utf8), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".kistulentz/project.json").path))
    }

    func testEnglishPackDownloadCanBeCancelledBeforeContinuingOnboarding() {
        launch(
            completedOnboarding: false,
            acknowledgedEnglishPack: false,
            environment: ["KISTULENTZ_UI_TEST_BENEPAR_INSTALL_DELAY_MS": "5000"]
        )

        XCTAssertTrue(app.staticTexts["Enable Better Local Analysis"].waitForExistence(timeout: 8))
        app.buttons["Download and Enable"].click()
        let cancel = app.buttons["Cancel Download"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(app.buttons["Not Now"].waitForExistence(timeout: 5))
        app.buttons["Not Now"].click()
        XCTAssertTrue(app.staticTexts["Welcome to Kistulentz"].waitForExistence(timeout: 5))
        app.buttons["Continue to Editor"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    func testOllamaDiscoveryPrefersTheRecommendedLocalModelAndCanBeSelected() {
        launch(environment: [
            "KISTULENTZ_UI_TEST_OLLAMA_MODELS": "small-writer:latest,qwen3.5:4b"
        ])
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Kistulentz Settings"].waitForExistence(timeout: 8))

        let detection = app.descendants(matching: .any)["OllamaDetectionStatus"].firstMatch
        waitUntil(description: "Settings should automatically discover both local models") {
            self.value(of: detection) == "2 models found" || detection.label == "2 models found"
        }
        let picker = app.descendants(matching: .any)["OllamaModelPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(value(of: picker).contains("qwen3.5:4b"))

        let useOllama = app.descendants(matching: .any)["UseOllamaProvider"].firstMatch
        XCTAssertTrue(useOllama.isEnabled)
        useOllama.click()
        XCTAssertTrue(
            app.staticTexts["Ollama is now the selected writing provider."].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["Ollama and its models stay on this Mac. Every download requires confirmation."]
                .firstMatch.exists
        )
    }
}
