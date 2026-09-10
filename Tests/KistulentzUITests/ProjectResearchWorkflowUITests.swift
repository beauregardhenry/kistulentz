import Foundation
import XCTest

@MainActor
final class ProjectResearchWorkflowUITests: KistulentzUITestCase {
    func testSharedSourceStyleAndCitationInsertionPersist() throws {
        let original = "# Draft\n\nThe archive supports this claim.\n"
        let project = try makeProject(
            name: "Project Research Journey",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )
        let library = testRoot.appendingPathComponent("Shared Research Library", isDirectory: true)
        let record = try makeCSLRecord(named: "Archive Evidence")
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_RESEARCH_LIBRARY_PATH"] = library.path
        environment["KISTULENTZ_UI_TEST_RESEARCH_RECORD_PATHS"] = record.path
        launch(environment: environment)

        prepareSharedResearchLibrary()
        openProjectCommand("Project Research…")
        XCTAssertTrue(app.descendants(matching: .any)["ProjectResearchView"].waitForExistence(timeout: 5))

        let addSource = app.buttons["Add Archive Evidence to Project"]
        XCTAssertTrue(addSource.waitForExistence(timeout: 5))
        addSource.click()
        let source = app.staticTexts["Archive Evidence"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.click()

        chooseCitationStyle("APA")
        let locator = app.descendants(matching: .any)["ProjectResearchCitationLocator"].firstMatch
        XCTAssertTrue(locator.waitForExistence(timeout: 3))
        replaceText(in: locator, with: "p. 31")
        let insertCitation = app.buttons["InsertProjectResearchCitation"]
        XCTAssertTrue(insertCitation.isEnabled)
        insertCitation.click()

        let citation = "[@henry2026archive, p. 31]"
        waitUntil(description: "The citation should be inserted and saved in the project chapter") {
            (try? String(contentsOf: project.root.appendingPathComponent("Draft.md"), encoding: .utf8))?
                .contains(citation) == true
        }

        let bibliography = try bibliographyArchive(in: project.root)
        XCTAssertEqual(bibliography["style"] as? String, "apa")
        XCTAssertEqual((bibliography["sourceIDs"] as? [String])?.count, 1)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    func testQuotationsClaimLinksAndNotesPersist() throws {
        let original = "# Draft\n\nThe archive supports this claim.\n"
        let project = try makeProject(
            name: "Project Evidence Journey",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )
        let library = testRoot.appendingPathComponent("Seeded Research Library", isDirectory: true)
        let sourceID = UUID()
        try seedResearchLibrary(at: library, sourceID: sourceID)
        try seedProjectBibliography(at: project.root, sourceID: sourceID)
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_PREOPEN_RESEARCH_LIBRARY_PATH"] = library.path
        launch(environment: environment)

        selectEntireDraft()
        openProjectCommand("Project Research…")
        openSection("Quotations & Claims")
        let projectSource = app.staticTexts["Archive Evidence"].firstMatch
        XCTAssertTrue(projectSource.waitForExistence(timeout: 5))
        projectSource.click()

        let quotation = app.descendants(matching: .any)["ProjectResearchQuotation"].firstMatch
        replaceText(in: quotation, with: "The archive records the original route.")
        let evidenceLocator = app.descendants(matching: .any)["ProjectResearchEvidenceLocator"].firstMatch
        replaceText(in: evidenceLocator, with: "p. 44")
        let evidenceNote = app.descendants(matching: .any)["ProjectResearchEvidenceNote"].firstMatch
        replaceText(in: evidenceNote, with: "Confirm against the annotated edition.")
        app.buttons["SaveProjectResearchQuotation"].click()
        XCTAssertTrue(app.staticTexts["“The archive records the original route.”"].waitForExistence(timeout: 5))

        let linkClaim = app.buttons["LinkProjectResearchClaim"]
        XCTAssertTrue(linkClaim.isEnabled)
        linkClaim.click()
        let claimRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'ProjectResearchClaimItem-'"))
            .firstMatch
        XCTAssertTrue(claimRow.waitForExistence(timeout: 5))

        openSection("Research Notes")
        XCTAssertTrue(app.staticTexts["Kistulentz Research Notes.md"].waitForExistence(timeout: 3))
        let notes = app.textViews["Project Research Notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        replaceText(in: notes, with: "# Research Notes\n\nVerify the harbor date before publication.\n")
        app.buttons["CloseProjectResearch"].click()

        let bibliography = try bibliographyArchive(in: project.root)
        XCTAssertEqual((bibliography["quotations"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((bibliography["claimLinks"] as? [[String: Any]])?.count, 1)
        XCTAssertTrue(try String(
            contentsOf: project.root.appendingPathComponent("Kistulentz Research Notes.md"),
            encoding: .utf8
        ).contains("Verify the harbor date"))

        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    func testSavedQuotationsClaimLinksAndNotesLoad() throws {
        let original = "# Draft\n\nThe archive supports this claim.\n"
        let project = try makeProject(
            name: "Saved Project Evidence",
            documents: [("Draft.md", original)],
            kind: "nonfiction"
        )
        let library = testRoot.appendingPathComponent("Saved Research Library", isDirectory: true)
        let sourceID = UUID()
        try seedResearchLibrary(at: library, sourceID: sourceID)
        try seedSavedProjectResearch(at: project.root, sourceID: sourceID)
        var environment = project.environment
        environment["KISTULENTZ_UI_TEST_PREOPEN_RESEARCH_LIBRARY_PATH"] = library.path
        launch(environment: environment)

        openProjectCommand("Project Research…")
        openSection("Quotations & Claims")
        XCTAssertTrue(app.staticTexts["“The archive records the original route.”"].waitForExistence(timeout: 5))
        let claimRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'ProjectResearchClaimItem-'"))
            .firstMatch
        XCTAssertTrue(claimRow.waitForExistence(timeout: 5))
        openSection("Research Notes")
        let reopenedNotes = app.textViews["Project Research Notes"]
        XCTAssertTrue(reopenedNotes.waitForExistence(timeout: 3))
        XCTAssertTrue(value(of: reopenedNotes).contains("Verify the harbor date"))
        app.buttons["CloseProjectResearch"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    private func prepareSharedResearchLibrary() {
        let reference = app.descendants(matching: .any)["ReferenceMenu"].firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 8))
        reference.click()
        let libraryItem = app.menuItems["Research Library…"]
        XCTAssertTrue(libraryItem.waitForExistence(timeout: 3))
        libraryItem.click()
        XCTAssertTrue(app.staticTexts["Research Library"].waitForExistence(timeout: 5))
        app.buttons["Choose Folder…"].firstMatch.click()
        XCTAssertTrue(app.buttons["Show Markdown"].waitForExistence(timeout: 5))

        let actions = app.descendants(matching: .any)["ResearchSourceActions"].firstMatch
        actions.click()
        let importItem = app.menuItems["Import BibTeX, RIS, or CSL-JSON…"]
        XCTAssertTrue(importItem.waitForExistence(timeout: 3))
        importItem.click()
        XCTAssertTrue(app.staticTexts["Archive Evidence"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Close Research Library"].click()
    }

    private func selectEntireDraft() {
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
    }

    private func chooseCitationStyle(_ style: String) {
        let picker = app.popUpButtons["Project Research Citation Style"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.click()
        let item = app.menuItems[style]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    private func openSection(_ title: String) {
        let option = app.radioButtons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.click()
    }

    private func makeCSLRecord(named title: String) throws -> URL {
        let url = testRoot.appendingPathComponent("Project Research Source.json")
        let object: [[String: Any]] = [[
            "id": "henry2026archive",
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

    private func seedResearchLibrary(at root: URL, sourceID: UUID) throws {
        let metadata = root.appendingPathComponent(".kistulentz", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let now = "2026-09-10T00:00:00Z"
        let source: [String: Any] = [
            "id": sourceID.uuidString,
            "citeKey": "henry2026archive",
            "type": "book",
            "title": "Archive Evidence",
            "subtitle": "",
            "creators": [[
                "id": UUID().uuidString,
                "role": "author",
                "givenName": "Beau",
                "familyName": "Henry",
                "literalName": ""
            ]],
            "issuedYear": 2026,
            "issuedDate": "",
            "containerTitle": "",
            "publisher": "Test Press",
            "publisherPlace": "",
            "volume": "",
            "issue": "",
            "edition": "",
            "pages": "",
            "DOI": "",
            "ISBN": "",
            "URLString": "",
            "accessedDate": "",
            "abstract": "",
            "keywords": [],
            "libraryNotes": "",
            "attachments": [],
            "createdAt": now,
            "modifiedAt": now
        ]
        let archive: [String: Any] = ["schemaVersion": 1, "sources": [source]]
        try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys])
            .write(to: metadata.appendingPathComponent("research-library.json"), options: .atomic)
    }

    private func seedProjectBibliography(at root: URL, sourceID: UUID) throws {
        let metadata = root.appendingPathComponent(".kistulentz", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let archive: [String: Any] = [
            "schemaVersion": 2,
            "sourceIDs": [sourceID.uuidString],
            "style": "apa",
            "quotations": [],
            "claimLinks": []
        ]
        try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys])
            .write(to: metadata.appendingPathComponent("bibliography.json"), options: .atomic)
    }

    private func seedSavedProjectResearch(at root: URL, sourceID: UUID) throws {
        let metadata = root.appendingPathComponent(".kistulentz", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let archive: [String: Any] = [
            "schemaVersion": 2,
            "sourceIDs": [sourceID.uuidString],
            "style": "apa",
            "quotations": [[
                "id": UUID().uuidString,
                "sourceID": sourceID.uuidString,
                "text": "The archive records the original route.",
                "locator": "p. 44",
                "note": "Confirm against the annotated edition.",
                "createdAt": "2026-09-10T00:00:00Z"
            ]],
            "claimLinks": [[
                "id": UUID().uuidString,
                "sourceID": sourceID.uuidString,
                "chapterPath": "Draft.md",
                "claimExcerpt": "The archive supports this claim.",
                "locator": "p. 44",
                "note": "Confirm against the annotated edition."
            ]]
        ]
        try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys])
            .write(to: metadata.appendingPathComponent("bibliography.json"), options: .atomic)
        try "# Research Notes\n\nVerify the harbor date before publication.\n"
            .write(
                to: root.appendingPathComponent("Kistulentz Research Notes.md"),
                atomically: true,
                encoding: .utf8
            )
    }

    private func bibliographyArchive(in root: URL) throws -> [String: Any] {
        let url = root.appendingPathComponent(".kistulentz/bibliography.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
