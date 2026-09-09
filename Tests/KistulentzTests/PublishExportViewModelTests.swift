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

    private static func item(
        id: String,
        included: Bool,
        exclusion: String? = nil
    ) -> ExportPlanItem {
        ExportPlanItem(
            id: id,
            kind: .manuscript,
            title: id,
            markdown: "# \(id)\n",
            sourcePath: "\(id).md",
            outlineNodeID: nil,
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
}

@MainActor
private final class Harness {
    var archive = PublicationArchive(projectName: "Book", projectKind: .fiction)
    var recordedExports = 0
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
                var plan = PublishExportViewModelTests.plan(profile: profile)
                plan.format = format
                plan.destinations = archive.selectedDestinations
                return plan
            },
            rootURL: { URL(fileURLWithPath: "/tmp") },
            updateOutlineInclusion: { _, _ in },
            recordExport: { [weak self] _, _ in self?.recordedExports += 1 },
            preview: { plan, _ in
                PublicationRenderedBook(plan: plan, sections: [], notes: [])
            },
            preflight: { _, _ in PublicationPreflightReport(findings: []) },
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
