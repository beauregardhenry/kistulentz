import XCTest
@testable import Kistulentz

final class PublishExportViewModelTests: XCTestCase {
    func testPlanReconciliationPreservesTemporaryOrderAndExclusions() throws {
        let archive = PublicationArchive(projectName: "Book", projectKind: .fiction)
        let profile = try XCTUnwrap(archive.profiles.first)
        let old = Self.plan(
            profile: profile,
            items: [
                Self.item(id: "chapter-b", included: false),
                Self.item(id: "chapter-a", included: true),
            ]
        )
        let refreshed = Self.plan(
            profile: profile,
            items: [
                Self.item(id: "chapter-a", included: true),
                Self.item(id: "chapter-b", included: true),
                Self.item(id: "missing", included: true, exclusion: "The Markdown file is missing."),
            ]
        )

        let result = PublishExportViewModel.reconciling(refreshed, with: old)

        XCTAssertEqual(result.items.map(\.id), ["chapter-b", "chapter-a", "missing"])
        XCTAssertFalse(try XCTUnwrap(result.items.first(where: { $0.id == "chapter-b" })).isIncluded)
        XCTAssertFalse(try XCTUnwrap(result.items.first(where: { $0.id == "missing" })).isIncluded)
    }

    @MainActor
    func testMixedDigitalAndPrintDestinationsRequireSeparateProfiles() {
        let harness = Harness()
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.draft.selectedDestinations = [.genericEPUB, .kdpPrint]

        model.applyDestinationPreset()

        XCTAssertEqual(
            model.errorMessage,
            "The selected digital and print destinations require separate exports and separate profiles."
        )
    }

    @MainActor
    func testMetadataAndMatterEditsAreNormalizedPersistedAndPreviewed() {
        let harness = Harness()
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.authorsText = "  Beau Henry  \n\n Editor Name "
        model.keywordsText = " writing,  local-first, ,macOS "
        model.draft.metadata.title = "Revised Book"

        model.saveMetadata()

        XCTAssertEqual(harness.archive.metadata.authors, ["Beau Henry", "Editor Name"])
        XCTAssertEqual(harness.archive.metadata.keywords, ["writing", "local-first", "macOS"])
        XCTAssertTrue(model.previewText.contains("# chapter"))

        model.draft.matter[0].markdown = "Author-edited matter"
        model.regenerateSafeMatter()
        model.saveMatter()

        XCTAssertEqual(
            harness.archive.matter.first(where: { $0.id == model.draft.matter[0].id })?.markdown,
            model.draft.matter[0].markdown
        )
    }

    @MainActor
    func testProfileAndDestinationCommandsPersistSafeDigitalAndPrintPresets() throws {
        let harness = Harness()
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])

        let nonfiction = try XCTUnwrap(model.draft.profiles.first(where: { $0.kind == .nonfictionBook }))
        model.selectProfile(nonfiction.id)
        XCTAssertEqual(model.format, .printPDF)

        model.duplicateSelectedProfile()
        let copy = try XCTUnwrap(model.draft.profiles.first(where: { $0.id == model.selectedProfileID }))
        XCTAssertEqual(copy.kind, .custom)
        XCTAssertTrue(copy.name.hasSuffix(" Copy"))
        model.deleteSelectedProfile()
        XCTAssertFalse(model.draft.profiles.contains(where: { $0.id == copy.id }))

        let fiction = try XCTUnwrap(model.draft.profiles.first(where: { $0.kind == .fictionBook }))
        model.selectProfile(fiction.id)
        model.setDestination(.genericEPUB, isSelected: false)
        model.setDestination(.appleBooks, isSelected: true)
        model.applyDestinationPreset()
        XCTAssertEqual(model.format, .epub)
        XCTAssertTrue(try XCTUnwrap(model.draft.profiles.first(where: { $0.id == fiction.id })).includeCover)

        model.selectProfile(nonfiction.id)
        model.draft.selectedDestinations = [.kdpPrint]
        model.applyDestinationPreset()
        let printProfile = try XCTUnwrap(model.draft.profiles.first(where: { $0.id == nonfiction.id }))
        XCTAssertEqual(model.format, .printPDF)
        XCTAssertGreaterThanOrEqual(printProfile.layout.insideMargin, 27)
    }

    @MainActor
    func testPlanEditingPersistsOutlineChoicesAndWarningPreflightRequiresConfirmation() throws {
        let firstID = UUID()
        let secondID = UUID()
        let harness = Harness()
        harness.planItems = [
            Self.item(id: "first", included: true, outlineNodeID: firstID),
            Self.item(id: "second", included: true, outlineNodeID: secondID),
        ]
        harness.preflightReport = PublicationPreflightReport(findings: [
            PublicationPreflightFinding(
                id: "warning",
                severity: .warning,
                title: "Review recommended",
                detail: "Confirm the generated metadata.",
                sourcePath: nil
            )
        ])
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.outputDirectory = URL(fileURLWithPath: "/tmp")

        model.setInclusion(false, for: "first")
        model.movePlanItems(from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(model.plan?.items.map(\.id), ["second", "first"])
        XCTAssertFalse(try XCTUnwrap(model.plan?.items.first(where: { $0.id == "first" })).isIncluded)
        XCTAssertFalse(model.previewText.contains("# first"))

        model.savePlanInclusions()
        XCTAssertEqual(harness.outlineUpdates.count, 2)
        XCTAssertEqual(harness.outlineUpdates.first?.0, secondID)
        XCTAssertEqual(harness.outlineUpdates.first?.1, true)
        XCTAssertEqual(harness.outlineUpdates.last?.0, firstID)
        XCTAssertEqual(harness.outlineUpdates.last?.1, false)

        model.requestExport()

        XCTAssertTrue(model.showingWarningConfirmation)
        XCTAssertFalse(model.isExporting)
        XCTAssertEqual(model.preflight?.warnings.count, 1)
    }

    @MainActor
    func testExportFailureClearsProgressAndReportsError() async throws {
        let harness = Harness(exporter: { _, _, _, _ in
            throw ExpectedPublishError.failed
        })
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.outputDirectory = URL(fileURLWithPath: "/tmp")

        model.performExport(allowingWarnings: true)
        try await waitUntil { !model.isExporting }

        XCTAssertEqual(model.errorMessage, ExpectedPublishError.failed.localizedDescription)
        XCTAssertEqual(harness.recordedExports, 0)
        XCTAssertNotEqual(model.pane, .history)
    }

    @MainActor
    func testCancellationPreventsAStaleExportFromBeingRecorded() async throws {
        let harness = Harness(exporter: { plan, _, output, _ in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                // Simulate a slow dependency that finishes despite cancellation.
            }
            return Self.result(for: plan, outputDirectory: output)
        })
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.outputDirectory = URL(fileURLWithPath: "/tmp")

        model.performExport(allowingWarnings: true)
        XCTAssertTrue(model.isExporting)
        model.cancelExport()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertFalse(model.isExporting)
        XCTAssertEqual(harness.recordedExports, 0)
        XCTAssertNil(model.lastExportURL)
        XCTAssertNotEqual(model.pane, .history)
    }

    @MainActor
    func testSuccessfulExportRecordsOnceAndShowsHistory() async throws {
        let harness = Harness(exporter: { plan, _, output, _ in
            Self.result(for: plan, outputDirectory: output)
        })
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.outputDirectory = URL(fileURLWithPath: "/tmp")

        model.performExport(allowingWarnings: true)
        try await waitUntil { !model.isExporting }

        XCTAssertEqual(harness.recordedExports, 1)
        XCTAssertEqual(model.pane, .history)
        XCTAssertEqual(model.lastExportURL?.lastPathComponent, "Book.epub")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testApplyDestinationPresetRequiresAtLeastOneDestination() {
        let harness = Harness()
        let model = PublishExportViewModel(dependencies: harness.dependencies())
        model.load(sources: [])
        model.draft.selectedDestinations = []

        model.applyDestinationPreset()

        XCTAssertEqual(model.errorMessage, "Choose at least one publication destination before applying a preset.")
    }

    /// Every other test in this file injects a fake `Dependencies`. `Dependencies.live` --
    /// the real wiring used in production, including the actual cancellable, `Task.detached`-
    /// wrapped export call -- had never run at all.
    @MainActor
    func testRealDependenciesExportAnActualProjectEndToEnd() async throws {
        let parent = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let outputDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let root = try WritingProjectDisk.createProject(in: parent, name: "Live Export", kind: .fiction)
        let store = WritingProjectStore()
        try store.openProject(at: root)
        var archive = store.publicationStore.publicationArchive
        archive.metadata.authors = ["Author"]
        archive.selectedDestinations = [.genericEPUB]
        if let index = archive.profiles.firstIndex(where: { $0.id == archive.selectedProfileID }) {
            archive.profiles[index].includeCover = false
        }
        store.publicationStore.updatePublicationArchive(archive)

        let model = PublishExportViewModel(store: store, publicationStore: store.publicationStore)
        model.load(sources: [])
        model.outputDirectory = outputDirectory

        model.performExport(allowingWarnings: true)
        try await waitUntil { !model.isExporting }

        XCTAssertNil(model.errorMessage)
        let exportedURL = try XCTUnwrap(model.lastExportURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
        XCTAssertEqual(store.publicationStore.publicationArchive.history.count, 1)
        XCTAssertEqual(model.pane, .history)
    }

    private static func item(
        id: String,
        included: Bool,
        exclusion: String? = nil,
        outlineNodeID: UUID? = nil
    ) -> ExportPlanItem {
        ExportPlanItem(
            id: id,
            kind: .manuscript,
            title: id,
            markdown: "# \(id)\n",
            sourcePath: "\(id).md",
            outlineNodeID: outlineNodeID,
            depth: 0,
            isIncluded: included,
            exclusionReason: exclusion,
            matterKind: nil
        )
    }

    fileprivate static func plan(
        profile: ExportProfile,
        items: [ExportPlanItem]? = nil
    ) -> PublicationExportPlan {
        PublicationExportPlan(
            projectName: "Book",
            profile: profile,
            format: profile.preferredFormat,
            items: items ?? [item(id: "chapter", included: true)],
            metadata: PublicationMetadata(title: "Book"),
            bibliography: ProjectBibliographyArchive(),
            sources: [],
            destinations: [.genericEPUB]
        )
    }

    private static func result(
        for plan: PublicationExportPlan,
        outputDirectory: URL
    ) -> PublicationExportResult {
        PublicationExportResult(
            outputURL: outputDirectory.appendingPathComponent("Book.epub"),
            sha256: String(repeating: "a", count: 64),
            byteCount: 10,
            preflight: PublicationPreflightReport(findings: [])
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw ExpectedPublishError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kistulentz-PublishExportViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class Harness {
    var archive = PublicationArchive(projectName: "Book", projectKind: .fiction)
    var recordedExports = 0
    var outlineUpdates: [(UUID, Bool)] = []
    var planItems: [ExportPlanItem]?
    var preflightReport = PublicationPreflightReport(findings: [])
    let exporter: PublishExportViewModel.Exporter

    init(
        exporter: @escaping PublishExportViewModel.Exporter = { plan, _, output, _ in
            PublicationExportResult(
                outputURL: output.appendingPathComponent("Book.epub"),
                sha256: String(repeating: "a", count: 64),
                byteCount: 10,
                preflight: PublicationPreflightReport(findings: [])
            )
        }
    ) {
        self.exporter = exporter
    }

    func dependencies() -> PublishExportViewModel.Dependencies {
        PublishExportViewModel.Dependencies(
            loadArchive: { [weak self] in self?.archive ?? PublicationArchive() },
            saveArchive: { [weak self] in self?.archive = $0 },
            makePlan: { [weak self] _, profileID, format in
                let archive = self?.archive ?? PublicationArchive()
                let profile = archive.profiles.first(where: { $0.id == profileID }) ?? archive.profiles[0]
                var plan = PublishExportViewModelTests.plan(profile: profile, items: self?.planItems)
                plan.format = format
                plan.destinations = archive.selectedDestinations
                return plan
            },
            rootURL: { URL(fileURLWithPath: "/tmp") },
            updateOutlineInclusion: { [weak self] id, isIncluded in
                self?.outlineUpdates.append((id, isIncluded))
            },
            recordExport: { [weak self] _, _ in self?.recordedExports += 1 },
            preview: { plan, _ in
                let sections = plan.includedItems.map { item in
                    PublicationRenderedSection(
                        id: item.id,
                        title: item.title,
                        kind: item.kind,
                        blocks: [PublicationBlock(
                            kind: .paragraph,
                            text: item.markdown,
                            html: "",
                            imageURL: nil,
                            altText: ""
                        )],
                        bodyHTML: "",
                        sourcePath: item.sourcePath,
                        noteIDs: []
                    )
                }
                return PublicationRenderedBook(plan: plan, sections: sections, notes: [])
            },
            preflight: { [weak self] _, _ in
                self?.preflightReport ?? PublicationPreflightReport(findings: [])
            },
            export: exporter
        )
    }
}

private enum ExpectedPublishError: LocalizedError {
    case failed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .failed: "Expected publication failure."
        case .timedOut: "Timed out waiting for publication state."
        }
    }
}
