import XCTest
@testable import Kistulentz

@MainActor
final class ProjectImportAssistantViewModelTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDown() {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    func testSourceEditingReorderingAndRemovalStayInModel() {
        let model = ProjectImportAssistantViewModel()
        let first = source("First")
        let second = source("Second")
        model.sources = [first, second]
        model.selectedSourceID = first.id

        model.updateSource(id: first.id, keyPath: \.title, value: "Opening")
        model.updateSource(id: first.id, keyPath: \.kind, value: OutlineNodeKind.part)
        model.moveSource(from: 0, by: 1)

        XCTAssertEqual(model.sources.map(\.title), ["Second", "Opening"])
        XCTAssertEqual(model.sources[1].kind, .part)

        model.removeSource(first.id)

        XCTAssertEqual(model.sources.map(\.id), [second.id])
        XCTAssertEqual(model.selectedSourceID, second.id)
    }

    func testTrackedChangesGateOutputUntilEveryDecisionIsMade() {
        let model = ProjectImportAssistantViewModel()
        let importSource = source("Tracked")
        let insertion = DocumentImportReviewCard(kind: .insertion, changedMarkdown: "new")
        let deletion = DocumentImportReviewCard(kind: .deletion, changedMarkdown: "old")
        let conversion = ProjectImportConversion(
            source: importSource,
            templateMarkdown: DocumentImportDraft.changeToken(insertion.id)
                + DocumentImportDraft.changeToken(deletion.id),
            reviewCards: [insertion, deletion]
        )
        model.sources = [importSource]
        model.conversions = [importSource.id: conversion]

        XCTAssertFalse(model.canFinish(hasCurrentProjectImporter: false))

        model.setDecision(.accept, for: insertion.id)
        XCTAssertFalse(model.canFinish(hasCurrentProjectImporter: false))

        model.decideAll(.reject, in: conversion)
        XCTAssertTrue(model.canFinish(hasCurrentProjectImporter: false))
        XCTAssertEqual(model.decisions[insertion.id], .reject)
        XCTAssertEqual(model.decisions[deletion.id], .reject)

        model.setDecision(nil, for: insertion.id)
        XCTAssertFalse(model.canFinish(hasCurrentProjectImporter: false))
    }

    func testDestinationRequirementsAndPreviewRemainCentralized() {
        let model = ProjectImportAssistantViewModel()
        let importSource = source("Opening", kind: .chapter)
        let conversion = ProjectImportConversion(
            source: importSource,
            templateMarkdown: "# Existing\n\nBody"
        )
        model.sources = [importSource]
        model.conversions = [importSource.id: conversion]

        XCTAssertTrue(model.previewMarkdown(for: conversion).hasPrefix("## Opening"))
        XCTAssertTrue(model.canFinish(hasCurrentProjectImporter: false))

        model.destination = .newProject
        model.projectName = "   "
        XCTAssertFalse(model.canFinish(hasCurrentProjectImporter: false))
        model.projectName = "Imported Book"
        model.projectParentURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
        XCTAssertTrue(model.canFinish(hasCurrentProjectImporter: false))
        XCTAssertEqual(model.previewMarkdown(for: conversion), "# Existing\n\nBody\n")

        model.destination = .currentProject
        XCTAssertFalse(model.canFinish(hasCurrentProjectImporter: false))
        XCTAssertTrue(model.canFinish(hasCurrentProjectImporter: true))
    }

    func testResetClearsResultsButKeepsTheImportPlan() {
        let model = ProjectImportAssistantViewModel()
        let importSource = source("Draft")
        let card = DocumentImportReviewCard(kind: .insertion, changedMarkdown: "new")
        model.sources = [importSource]
        model.conversions = [
            importSource.id: ProjectImportConversion(
                source: importSource,
                templateMarkdown: DocumentImportDraft.changeToken(card.id),
                reviewCards: [card]
            )
        ]
        model.failures = [
            importSource.id: ProjectImportFailure(source: importSource, message: "failed")
        ]
        model.decisions = [card.id: .accept]

        model.resetResults()

        XCTAssertEqual(model.sources, [importSource])
        XCTAssertTrue(model.conversions.isEmpty)
        XCTAssertTrue(model.failures.isEmpty)
        XCTAssertTrue(model.decisions.isEmpty)
        XCTAssertFalse(model.hasResults)
        XCTAssertEqual(model.completedCount, 0)
    }

    func testSelectionDiscoveryDeduplicatesFilesAndReportsErrors() async throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("First.txt")
        let second = root.appendingPathComponent("Second.md")
        try "First body".write(to: first, atomically: true, encoding: .utf8)
        try "# Second".write(to: second, atomically: true, encoding: .utf8)
        let model = ProjectImportAssistantViewModel()

        model.addSelections(.success([first, root]))
        try await waitUntil { !model.isDiscovering }

        XCTAssertEqual(model.sources.map { $0.url.lastPathComponent }, ["First.txt", "Second.md"])
        XCTAssertEqual(model.selectedSourceID, model.sources.first?.id)

        model.addSelections(.success([first]))
        try await waitUntil { !model.isDiscovering }
        XCTAssertEqual(model.sources.count, 2)

        model.addSelections(.failure(ProjectImportError.cancelled))
        XCTAssertEqual(model.errorMessage, ProjectImportError.cancelled.localizedDescription)
    }

    func testConversionContinuesPastFailureAndRetryCanRecover() async throws {
        let root = try makeTemporaryDirectory()
        let validURL = root.appendingPathComponent("Valid.txt")
        let retryURL = root.appendingPathComponent("Retry.txt")
        try "A valid document.".write(to: validURL, atomically: true, encoding: .utf8)
        try Data().write(to: retryURL)
        let valid = ProjectImportSource(url: validURL)
        let retry = ProjectImportSource(url: retryURL)
        let model = ProjectImportAssistantViewModel()
        model.sources = [valid, retry]

        model.startConversion()
        try await waitUntil { !model.isConverting }

        XCTAssertNotNil(model.conversions[valid.id])
        XCTAssertEqual(model.failures[retry.id]?.source, retry)
        XCTAssertEqual(model.completedCount, 2)
        XCTAssertEqual(model.statusIcon(for: valid.id), "checkmark.circle.fill")
        XCTAssertEqual(model.statusIcon(for: retry.id), "exclamationmark.triangle.fill")

        try "Recovered document.".write(to: retryURL, atomically: true, encoding: .utf8)
        model.retryFailures()
        try await waitUntil { !model.isConverting }

        XCTAssertNotNil(model.conversions[retry.id])
        XCTAssertTrue(model.failures.isEmpty)
    }

    func testCancellationStopsConversionAndLeavesThePlanEditable() async throws {
        let root = try makeTemporaryDirectory()
        let url = root.appendingPathComponent("Draft.txt")
        try "Draft".write(to: url, atomically: true, encoding: .utf8)
        let model = ProjectImportAssistantViewModel()
        model.sources = [ProjectImportSource(url: url)]

        model.startConversion()
        XCTAssertTrue(model.isConverting)
        XCTAssertEqual(model.statusIcon(for: model.sources[0].id), "clock")
        model.cancelConversion()
        await Task.yield()

        XCTAssertFalse(model.isConverting)
        XCTAssertEqual(model.currentSourceName, "")
        XCTAssertEqual(model.statusIcon(for: model.sources[0].id), "doc")
        XCTAssertEqual(model.sources.count, 1)
    }

    func testCombinedOutputSuccessAndFailureUpdateObservableState() async throws {
        let root = try makeTemporaryDirectory()
        let sourceURL = root.appendingPathComponent("Source.md")
        try "# Source\n\nBody".write(to: sourceURL, atomically: true, encoding: .utf8)
        let source = ProjectImportSource(url: sourceURL)
        let conversion = ProjectImportConversion(source: source, templateMarkdown: "Body")
        let model = ProjectImportAssistantViewModel()
        model.sources = [source]
        model.conversions = [source.id: conversion]
        let outputURL = root.appendingPathComponent("Combined.md")
        var completedURL: URL?

        model.writeCombinedMarkdown(to: outputURL) { completedURL = $0 }
        try await waitUntil { !model.isWriting }

        XCTAssertEqual(completedURL, outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        model.writeCombinedMarkdown(to: outputURL) { _ in
            XCTFail("An existing destination must not be replaced.")
        }
        try await waitUntil { !model.isWriting }
        XCTAssertNotNil(model.errorMessage)
    }

    func testNewAndCurrentProjectOutputPathsReportCompletionAndErrors() async throws {
        let root = try makeTemporaryDirectory()
        let sourceURL = root.appendingPathComponent("Chapter.md")
        try "# Chapter\n\nBody".write(to: sourceURL, atomically: true, encoding: .utf8)
        let source = ProjectImportSource(url: sourceURL)
        let conversion = ProjectImportConversion(source: source, templateMarkdown: "# Chapter\n\nBody")
        let model = ProjectImportAssistantViewModel()
        model.sources = [source]
        model.conversions = [source.id: conversion]
        model.projectParentURL = root
        model.projectName = "Imported Project"
        var createdProject: URL?

        model.createNewProject { createdProject = $0 }
        try await waitUntil { !model.isWriting }

        XCTAssertEqual(createdProject?.lastPathComponent, "Imported Project")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdProject?.path ?? ""))

        var currentProject: URL?
        let currentURL = root.appendingPathComponent("Current", isDirectory: true)
        model.addDocumentsToCurrentProject(using: { _, _ in
            ProjectImportWriteResult(rootURL: currentURL, importedPaths: ["Chapter.md"], selectedPath: "Chapter.md")
        }) { currentProject = $0 }
        XCTAssertEqual(currentProject, currentURL)
        XCTAssertFalse(model.isWriting)

        model.addDocumentsToCurrentProject(using: { _, _ in
            throw ProjectImportError.currentProjectSaveFailed
        }) { _ in
            XCTFail("A failed current-project operation must not complete.")
        }
        XCTAssertEqual(model.errorMessage, ProjectImportError.currentProjectSaveFailed.localizedDescription)
    }

    func testHierarchyAndDestinationLabelsCoverEveryDestination() {
        let model = ProjectImportAssistantViewModel()
        let scene = source("Scene", kind: .scene)
        model.sources = [scene]
        model.conversions = [scene.id: ProjectImportConversion(source: scene, templateMarkdown: "Body")]

        XCTAssertEqual(model.finishButtonTitle, "Save Combined Markdown…")
        XCTAssertNil(model.hierarchyError)

        model.destination = .newProject
        XCTAssertEqual(model.finishButtonTitle, "Create and Open Project")
        XCTAssertNotNil(model.hierarchyError)

        model.destination = .currentProject
        XCTAssertEqual(model.finishButtonTitle, "Add to Current Project")
        XCTAssertNotNil(model.hierarchyError)
    }

    private func source(_ title: String, kind: OutlineNodeKind = .chapter) -> ProjectImportSource {
        ProjectImportSource(
            url: URL(fileURLWithPath: "/tmp/\(title).md"),
            title: title,
            kind: kind
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-ImportViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        attempts: Int = 500
    ) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the view-model operation to finish.")
    }
}
