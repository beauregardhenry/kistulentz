import Foundation
import XCTest

class KistulentzUITestCase: XCTestCase {
    var app: XCUIApplication!
    var testRoot: URL!
    var editCommandURL: URL!
    var statusURL: URL!

    private var launchEnvironment: [String: String] = [:]
    private var launchArguments: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        executionTimeAllowance = 60
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-UI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        editCommandURL = testRoot.appendingPathComponent("Editor Command.txt")
        statusURL = testRoot.appendingPathComponent("UI Test Status.txt")
    }

    override func tearDownWithError() throws {
        let application = app
        MainActor.assumeIsolated {
            application?.terminate()
        }
        app = nil
        editCommandURL = nil
        statusURL = nil
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        try super.tearDownWithError()
    }

    @discardableResult
    @MainActor
    func launch(
        completedOnboarding: Bool = true,
        acknowledgedEnglishPack: Bool = true,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) -> XCUIApplication {
        launchEnvironment = environment
        launchArguments = arguments
        app = makeApplication(
            completedOnboarding: completedOnboarding,
            acknowledgedEnglishPack: acknowledgedEnglishPack
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    @discardableResult
    @MainActor
    func relaunch(
        completedOnboarding: Bool = true,
        acknowledgedEnglishPack: Bool = true
    ) -> XCUIApplication {
        app = makeApplication(
            completedOnboarding: completedOnboarding,
            acknowledgedEnglishPack: acknowledgedEnglishPack
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    @MainActor var editor: XCUIElement {
        app.descendants(matching: .any)["MarkdownEditor"].firstMatch
    }

    @MainActor func openProjectCommand(_ title: String) {
        let control = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Project:'"))
            .firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 8))
        control.click()
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    @MainActor func openProjectImportAssistant() {
        let projects = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Projects'"))
            .firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 8))
        projects.click()
        let item = app.menuItems["Project Import Assistant…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["ProjectImportAssistantView"]
                .waitForExistence(timeout: 5)
        )
    }

    @discardableResult
    func makeProject(
        name: String,
        documents: [(String, String)],
        kind: String = "fiction"
    ) throws -> (root: URL, environment: [String: String]) {
        let root = testRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relativePath, text) in documents {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return (
            root,
            [
                "KISTULENTZ_UI_TEST_PROJECT_PATH": root.path,
                "KISTULENTZ_UI_TEST_PROJECT_NAME": name,
                "KISTULENTZ_UI_TEST_PROJECT_KIND": kind
            ]
        )
    }

    func writeRecoveryEntry(
        directory: URL,
        original: URL?,
        recoveredText: String,
        title: String = "Recovered Draft.md"
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = RecoveryEntryFixture(
            formatVersion: 1,
            id: UUID(),
            sessionID: UUID(),
            title: title,
            originalFilePath: original?.path,
            projectRootPath: nil,
            recoveredText: recoveredText,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(fixture).write(
            to: directory.appendingPathComponent("draft-\(fixture.id.uuidString).json"),
            options: .atomic
        )
    }

    func waitUntil(
        timeout: TimeInterval = 8,
        description: String,
        _ condition: @escaping () -> Bool
    ) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, description)
    }

    @MainActor func value(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    @MainActor func replaceText(in element: XCUIElement, with text: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
        waitUntil(description: "The editor should finish applying the typed text") {
            self.value(of: element) == text
        }
    }

    @MainActor func replaceEditorText(with text: String) throws {
        try text.write(to: editCommandURL, atomically: true, encoding: .utf8)
        waitUntil(description: "Kistulentz should apply the test edit through its document pipeline") {
            self.value(of: self.editor) == text
        }
        try "".write(to: editCommandURL, atomically: true, encoding: .utf8)
    }

    @MainActor func undoEditorText(expecting text: String) throws {
        try "__KISTULENTZ_UNDO__".write(to: editCommandURL, atomically: true, encoding: .utf8)
        waitUntil(description: "Undo should restore the complete previous passage") {
            self.value(of: self.editor) == text
        }
        try "".write(to: editCommandURL, atomically: true, encoding: .utf8)
    }

    @MainActor func redoEditorText(expecting text: String) throws {
        try "__KISTULENTZ_REDO__".write(to: editCommandURL, atomically: true, encoding: .utf8)
        waitUntil(description: "Redo should restore the revised passage") {
            self.value(of: self.editor) == text
        }
        try "".write(to: editCommandURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    @MainActor
    func undoProjectChange(expecting text: String) throws -> String {
        try? FileManager.default.removeItem(at: statusURL)
        try "__KISTULENTZ_PROJECT_UNDO__".write(to: editCommandURL, atomically: true, encoding: .utf8)
        waitUntil(description: "Kistulentz should report the project Undo outcome") {
            FileManager.default.fileExists(atPath: self.statusURL.path)
        }
        let status = try String(contentsOf: statusURL, encoding: .utf8)
        waitUntil(description: "One Undo should revert the complete project transaction. \(status)") {
            self.value(of: self.editor) == text
        }
        try "".write(to: editCommandURL, atomically: true, encoding: .utf8)
        return status
    }

    func projectUndoStatus() throws -> String {
        try? FileManager.default.removeItem(at: statusURL)
        try "__KISTULENTZ_PROJECT_UNDO_STATUS__".write(
            to: editCommandURL,
            atomically: true,
            encoding: .utf8
        )
        waitUntil(description: "Kistulentz should report project Undo availability") {
            FileManager.default.fileExists(atPath: self.statusURL.path)
        }
        let status = try String(contentsOf: statusURL, encoding: .utf8)
        try "".write(to: editCommandURL, atomically: true, encoding: .utf8)
        return status
    }

    @discardableResult
    @MainActor
    func redoProjectChange(expecting text: String) throws -> String {
        try? FileManager.default.removeItem(at: statusURL)
        try "__KISTULENTZ_PROJECT_REDO__".write(to: editCommandURL, atomically: true, encoding: .utf8)
        waitUntil(description: "Kistulentz should report the project Redo outcome") {
            FileManager.default.fileExists(atPath: self.statusURL.path)
        }
        let status = try String(contentsOf: statusURL, encoding: .utf8)
        waitUntil(description: "Redo should restore the complete project transaction. \(status)") {
            self.value(of: self.editor) == text
        }
        try "".write(to: editCommandURL, atomically: true, encoding: .utf8)
        return status
    }

    func fixture(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(relativePath)
    }

    @MainActor private func makeApplication(
        completedOnboarding: Bool,
        acknowledgedEnglishPack: Bool
    ) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment["KISTULENTZ_UI_TESTING"] = "1"
        application.launchEnvironment["CFFIXED_USER_HOME"] = testRoot
            .appendingPathComponent("Home", isDirectory: true)
            .path
        application.launchEnvironment["KISTULENTZ_UI_TEST_EDIT_COMMAND_PATH"] = editCommandURL.path
        application.launchEnvironment["KISTULENTZ_UI_TEST_STATUS_PATH"] = statusURL.path
        for (key, value) in launchEnvironment {
            application.launchEnvironment[key] = value
        }
        application.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-hasCompletedOnboarding", completedOnboarding ? "YES" : "NO",
            "-hasAcknowledgedEnglishPackPrompt", acknowledgedEnglishPack ? "YES" : "NO",
            "-lastSeenAppVersion", "0.17.1"
        ]
        application.launchArguments += launchArguments
        return application
    }
}

private struct RecoveryEntryFixture: Encodable {
    let formatVersion: Int
    let id: UUID
    let sessionID: UUID
    let title: String
    let originalFilePath: String?
    let projectRootPath: String?
    let recoveredText: String
    let updatedAt: Date
}
