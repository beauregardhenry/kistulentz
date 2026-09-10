import Foundation
import XCTest

@MainActor
final class ResearchLibraryWorkflowUITests: KistulentzUITestCase {
    func testBibliographyExchangeAndManagedAttachmentJourneyPersistsAndCleansUp() throws {
        let library = testRoot.appendingPathComponent("Research Exchange Library", isDirectory: true)
        let record = try makeCSLRecord(named: "Harbor Evidence")
        let attachment = testRoot.appendingPathComponent("lighthouse-evidence.txt")
        try "A concealed lighthouse observation confirms the route.".write(
            to: attachment,
            atomically: true,
            encoding: .utf8
        )
        let exported = testRoot.appendingPathComponent("Research Export.bib")
        launch(environment: [
            "KISTULENTZ_UI_TEST_RESEARCH_LIBRARY_PATH": library.path,
            "KISTULENTZ_UI_TEST_RESEARCH_RECORD_PATHS": record.path,
            "KISTULENTZ_UI_TEST_RESEARCH_ATTACHMENT_PATHS": attachment.path,
            "KISTULENTZ_UI_TEST_SAVE_DESTINATION_PATH": exported.path
        ])

        openResearchLibrary(choosingFolder: true)
        openSourceActions(named: "Import BibTeX, RIS, or CSL-JSON…")
        XCTAssertTrue(app.staticTexts["Harbor Evidence"].firstMatch.waitForExistence(timeout: 5))

        let addAttachment = app.descendants(matching: .any)["AddResearchAttachment"].firstMatch
        XCTAssertTrue(addAttachment.waitForExistence(timeout: 5))
        addAttachment.click()
        XCTAssertTrue(app.staticTexts["lighthouse-evidence.txt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Locally indexed"].waitForExistence(timeout: 8))

        let managedFolder = library.appendingPathComponent("Attachments", isDirectory: true)
        waitUntil(description: "The attachment should be copied into the managed library") {
            self.files(named: "lighthouse-evidence.txt", below: managedFolder).count == 1
        }
        let search = app.descendants(matching: .any)["ResearchSourceSearch"].firstMatch
        replaceText(in: search, with: "concealed lighthouse")
        XCTAssertTrue(app.staticTexts["Harbor Evidence"].firstMatch.waitForExistence(timeout: 3))

        openSourceActions(named: "Export All as BibTeX…")
        waitUntil(description: "The visible library should export as BibTeX") {
            FileManager.default.fileExists(atPath: exported.path)
        }
        let bibTeX = try String(contentsOf: exported, encoding: .utf8)
        XCTAssertTrue(bibTeX.contains("@book{henry2026harbor"))
        XCTAssertTrue(bibTeX.contains("title = {Harbor Evidence}"))

        let removeAttachment = app.buttons["Remove lighthouse-evidence.txt"]
        XCTAssertTrue(removeAttachment.waitForExistence(timeout: 3))
        removeAttachment.click()
        waitUntil(description: "Removing a managed attachment should remove its copied file") {
            self.files(named: "lighthouse-evidence.txt", below: managedFolder).isEmpty
        }
        XCTAssertFalse(app.staticTexts["lighthouse-evidence.txt"].waitForExistence(timeout: 2))

        app.buttons["Close Research Library"].click()
        XCTAssertFalse(app.staticTexts["Research Library"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            try String(
                contentsOf: library.appendingPathComponent("Kistulentz Research Library.md"),
                encoding: .utf8
            ).contains("Harbor Evidence")
        )
    }

    func testCancellingAndClosingSlowAttachmentIndexingLeavesRecoverableRecords() throws {
        let library = testRoot.appendingPathComponent("Cancelled Index Library", isDirectory: true)
        let record = try makeCSLRecord(named: "Cancellation Evidence")
        let attachment = testRoot.appendingPathComponent("slow-evidence.txt")
        try "This text should remain available for a later indexing attempt.".write(
            to: attachment,
            atomically: true,
            encoding: .utf8
        )
        launch(environment: [
            "KISTULENTZ_UI_TEST_RESEARCH_LIBRARY_PATH": library.path,
            "KISTULENTZ_UI_TEST_RESEARCH_RECORD_PATHS": record.path,
            "KISTULENTZ_UI_TEST_RESEARCH_ATTACHMENT_PATHS": attachment.path,
            "KISTULENTZ_UI_TEST_RESEARCH_INDEX_DELAY_MS": "5000"
        ])

        openResearchLibrary(choosingFolder: true)
        openSourceActions(named: "Import BibTeX, RIS, or CSL-JSON…")
        XCTAssertTrue(app.staticTexts["Cancellation Evidence"].firstMatch.waitForExistence(timeout: 5))
        let addAttachment = app.descendants(matching: .any)["AddResearchAttachment"].firstMatch
        XCTAssertTrue(addAttachment.waitForExistence(timeout: 5))

        addAttachment.click()
        XCTAssertTrue(app.staticTexts["Indexing locally…"].waitForExistence(timeout: 5))
        let cancel = app.descendants(matching: .any)["CancelResearchAttachmentIndexing"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(app.staticTexts["Not indexed"].waitForExistence(timeout: 5))
        waitUntil(description: "A cancelled index should finish unwinding before another attachment starts") {
            addAttachment.isEnabled
        }

        let addAgain = app.descendants(matching: .any)["AddResearchAttachment"].firstMatch
        XCTAssertTrue(addAgain.waitForExistence(timeout: 3))
        addAgain.click()
        XCTAssertTrue(app.staticTexts["Indexing locally…"].waitForExistence(timeout: 5))
        waitUntil(description: "The second attachment should be recorded before its index is cancelled by closing") {
            (try? self.persistedAttachments(in: library).count) == 2
        }
        app.buttons["Close Research Library"].click()
        XCTAssertFalse(app.staticTexts["Research Library"].waitForExistence(timeout: 3))

        openResearchLibrary(choosingFolder: false)
        let source = app.staticTexts["Cancellation Evidence"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.click()
        XCTAssertTrue(app.staticTexts["Not indexed"].firstMatch.waitForExistence(timeout: 5))
        let attachments = try persistedAttachments(in: library)
        XCTAssertEqual(attachments.count, 2)
        XCTAssertTrue(attachments.allSatisfy { $0["extractionStatus"] as? String == "notStarted" })
        XCTAssertEqual(files(withExtension: "txt", below: library.appendingPathComponent("Extracted Text")).count, 0)
        let storedPaths = try attachments.map {
            try XCTUnwrap($0["storedRelativePath"] as? String)
        }
        XCTAssertEqual(Set(storedPaths).count, 2)
        XCTAssertTrue(storedPaths.allSatisfy {
            FileManager.default.fileExists(atPath: library.appendingPathComponent($0).path)
        })
    }

    private func openResearchLibrary(choosingFolder: Bool) {
        let reference = app.descendants(matching: .any)["ReferenceMenu"].firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 8))
        reference.click()
        let item = app.menuItems["Research Library…"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
        XCTAssertTrue(app.staticTexts["Research Library"].waitForExistence(timeout: 5))
        if choosingFolder {
            app.buttons["Choose Folder…"].firstMatch.click()
            XCTAssertTrue(app.buttons["Show Markdown"].waitForExistence(timeout: 5))
        }
    }

    private func openSourceActions(named item: String) {
        let actions = app.descendants(matching: .any)["ResearchSourceActions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        actions.click()
        let menuItem = app.menuItems[item]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3))
        menuItem.click()
    }

    private func makeCSLRecord(named title: String) throws -> URL {
        let url = testRoot.appendingPathComponent("\(title).json")
        let object: [[String: Any]] = [[
            "id": "henry2026harbor",
            "type": "book",
            "title": title,
            "author": [["given": "Beau", "family": "Henry"]],
            "issued": ["date-parts": [[2026]]],
            "publisher": "Test Press"
        ]]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            .write(to: url, options: .atomic)
        return url
    }

    private func files(named name: String, below root: URL) -> [URL] {
        files(below: root).filter { $0.lastPathComponent == name }
    }

    private func files(withExtension pathExtension: String, below root: URL) -> [URL] {
        files(below: root).filter { $0.pathExtension == pathExtension }
    }

    private func files(below root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func persistedAttachments(in library: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: library.appendingPathComponent(".kistulentz/research-library.json"))
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sources = try XCTUnwrap(archive["sources"] as? [[String: Any]])
        return try XCTUnwrap(sources.first?["attachments"] as? [[String: Any]])
    }
}
