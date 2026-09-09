import Foundation
import SwiftUI

enum PublicationWorkspacePane: String, CaseIterable, Identifiable, Equatable {
    case plan = "Export Plan"
    case setup = "Publication Setup"
    case matter = "Generated Matter"
    case profile = "Export Profile"
    case preflight = "Preflight & Export"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .plan: "list.bullet.rectangle"
        case .setup: "book.pages"
        case .matter: "doc.badge.gearshape"
        case .profile: "slider.horizontal.3"
        case .preflight: "checkmark.seal"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// Coordinates the publication workspace independently of SwiftUI controls.
/// The view owns file panels; this object owns plan reconciliation, preflight,
/// persistence, and one cancellable export operation.
@MainActor
final class PublishExportViewModel: ObservableObject {
    typealias Exporter = (
        PublicationExportPlan,
        URL,
        URL,
        Bool
    ) async throws -> PublicationExportResult
    typealias ArchiveLoader = @MainActor () -> PublicationArchive
    typealias ArchiveSaver = @MainActor (PublicationArchive) -> Void
    typealias PlanBuilder = @MainActor (
        [ResearchSource],
        UUID,
        PublicationExportFormat
    ) throws -> PublicationExportPlan
    typealias RootProvider = @MainActor () -> URL?
    typealias InclusionUpdater = @MainActor (UUID, Bool) -> Void
    typealias ExportRecorder = @MainActor (PublicationExportResult, PublicationExportPlan) -> Void

    struct Dependencies {
        var loadArchive: ArchiveLoader
        var saveArchive: ArchiveSaver
        var makePlan: PlanBuilder
        var rootURL: RootProvider
        var updateOutlineInclusion: InclusionUpdater
        var recordExport: ExportRecorder
        var preview: (PublicationExportPlan, URL) -> PublicationRenderedBook
        var preflight: (PublicationExportPlan, URL) -> PublicationPreflightReport
        var export: Exporter

        @MainActor static func live(
            store: WritingProjectStore,
            publicationStore: PublicationStore
        ) -> Dependencies {
            Dependencies(
                loadArchive: { publicationStore.publicationArchive },
                saveArchive: { publicationStore.updatePublicationArchive($0) },
                makePlan: { sources, profileID, format in
                    try publicationStore.publicationPlan(
                        sources: sources,
                        profileID: profileID,
                        format: format
                    )
                },
                rootURL: { store.rootURL },
                updateOutlineInclusion: { id, isIncluded in
                    guard var node = store.outlineNode(id: id) else { return }
                    node.metadata.includedInExport = isIncluded
                    store.updateOutlineNode(node)
                },
                recordExport: { publicationStore.recordPublicationExport($0, plan: $1) },
                preview: { PublicationExporter.preview(plan: $0, root: $1) },
                preflight: { PublicationPreflight.run(plan: $0, root: $1) },
                export: { plan, root, outputDirectory, allowingWarnings in
                    let worker = Task.detached(priority: .userInitiated) {
                        try PublicationExporter.export(
                            plan: plan,
                            root: root,
                            outputDirectory: outputDirectory,
                            allowingWarnings: allowingWarnings
                        )
                    }
                    return try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                }
            )
        }
    }

    @Published var pane: PublicationWorkspacePane? = .plan
    @Published var draft = PublicationArchive()
    @Published var selectedProfileID = UUID()
    @Published var format: PublicationExportFormat = .epub
    @Published var plan: PublicationExportPlan?
    @Published var previewText = ""
    @Published var preflight: PublicationPreflightReport?
    @Published var outputDirectory: URL?
    @Published private(set) var isExporting = false
    @Published var lastExportURL: URL?
    @Published var lastReportURL: URL?
    @Published var errorMessage: String?
    @Published var showingWarningConfirmation = false
    @Published var authorsText = ""
    @Published var keywordsText = ""

    private let dependencies: Dependencies
    private var sources: [ResearchSource] = []
    private var exportTask: Task<Void, Never>?
    private var exportOperationID: UUID?

    convenience init(store: WritingProjectStore, publicationStore: PublicationStore) {
        self.init(dependencies: .live(store: store, publicationStore: publicationStore))
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func load(sources: [ResearchSource]) {
        self.sources = sources
        reloadArchive()
        refreshPlan(preservingTemporaryPlan: false)
    }

    func updateSources(_ sources: [ResearchSource]) {
        self.sources = sources
    }

    func reloadArchive() {
        draft = dependencies.loadArchive()
        selectedProfileID = draft.selectedProfileID
        authorsText = draft.metadata.authors.joined(separator: "\n")
        keywordsText = draft.metadata.keywords.joined(separator: ", ")
        format = draft.profiles.first(where: { $0.id == selectedProfileID })?.preferredFormat ?? .epub
    }

    func persistDraft() {
        draft.selectedProfileID = selectedProfileID
        applyTextMetadata()
        dependencies.saveArchive(draft)
    }

    func saveMetadata() {
        applyTextMetadata()
        draft.matter = PublicationMatterGenerator.regenerating(draft.matter, metadata: draft.metadata)
        persistDraft()
        reloadArchive()
        refreshPlan(preservingTemporaryPlan: true)
    }

    func regenerateSafeMatter() {
        draft.matter = PublicationMatterGenerator.regenerating(draft.matter, metadata: draft.metadata)
    }

    func saveMatter() {
        persistDraft()
        refreshPlan(preservingTemporaryPlan: true)
    }

    func selectProfile(_ id: UUID) {
        guard let profile = draft.profiles.first(where: { $0.id == id }) else { return }
        draft.selectedProfileID = id
        format = profile.preferredFormat
        persistDraft()
        refreshPlan(preservingTemporaryPlan: true)
    }

    func refreshPlan(preservingTemporaryPlan: Bool) {
        persistDraft()
        do {
            var refreshed = try dependencies.makePlan(sources, selectedProfileID, format)
            if preservingTemporaryPlan, let existing = plan {
                refreshed = Self.reconciling(refreshed, with: existing)
            }
            plan = refreshed
            updatePreview()
            preflight = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setInclusion(_ isIncluded: Bool, for id: String) {
        guard var current = plan,
              let index = current.items.firstIndex(where: { $0.id == id }) else { return }
        current.items[index].isIncluded = isIncluded
        plan = current
        updatePreview()
        preflight = nil
    }

    func setDestination(_ destination: PublicationDestination, isSelected: Bool) {
        if isSelected {
            if !draft.selectedDestinations.contains(destination) {
                draft.selectedDestinations.append(destination)
            }
        } else {
            draft.selectedDestinations.removeAll { $0 == destination }
        }
        draft.selectedDestinations = PublicationDestination.allCases.filter {
            draft.selectedDestinations.contains($0)
        }
        persistDraft()
        refreshPlan(preservingTemporaryPlan: true)
    }

    func movePlanItems(from offsets: IndexSet, to destination: Int) {
        guard var current = plan else { return }
        current.items.move(fromOffsets: offsets, toOffset: destination)
        plan = current
        updatePreview()
        preflight = nil
    }

    func savePlanInclusions() {
        guard let plan else { return }
        for item in plan.items {
            guard let id = item.outlineNodeID else { continue }
            dependencies.updateOutlineInclusion(id, item.isIncluded)
        }
        refreshPlan(preservingTemporaryPlan: false)
    }

    func duplicateSelectedProfile() {
        guard var profile = draft.profiles.first(where: { $0.id == selectedProfileID }) else { return }
        profile.id = UUID()
        profile.kind = .custom
        profile.name += " Copy"
        profile.modifiedAt = Date()
        draft.profiles.append(profile)
        selectedProfileID = profile.id
        persistDraft()
        refreshPlan(preservingTemporaryPlan: true)
    }

    func applyDestinationPreset() {
        guard let index = draft.profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        let formats = Set(draft.selectedDestinations.flatMap(\.compatibleFormats))
        guard formats.count == 1, let recommendedFormat = formats.first else {
            errorMessage = draft.selectedDestinations.isEmpty
                ? "Choose at least one publication destination before applying a preset."
                : "The selected digital and print destinations require separate exports and separate profiles."
            return
        }
        var profile = draft.profiles[index]
        profile.preferredFormat = recommendedFormat
        format = recommendedFormat
        if recommendedFormat == .epub {
            profile.includeCover = true
            profile.includeTableOfContents = true
        } else if recommendedFormat == .printPDF {
            let minimumOuter = profile.printBleed == .outside ? 27.0 : 18.0
            profile.layout.bodyFontSize = max(profile.layout.bodyFontSize, 7)
            profile.layout.topMargin = max(profile.layout.topMargin, minimumOuter)
            profile.layout.bottomMargin = max(profile.layout.bottomMargin, minimumOuter)
            profile.layout.outsideMargin = max(profile.layout.outsideMargin, minimumOuter)
            profile.layout.insideMargin = max(profile.layout.insideMargin, 27)
        }
        profile.modifiedAt = Date()
        draft.profiles[index] = profile
        persistDraft()
        refreshPlan(preservingTemporaryPlan: true)
    }

    func deleteSelectedProfile() {
        draft.profiles.removeAll { $0.id == selectedProfileID && $0.kind == .custom }
        selectedProfileID = draft.profiles.first?.id ?? UUID()
        persistDraft()
        refreshPlan(preservingTemporaryPlan: false)
    }

    func runPreflight() {
        refreshPlan(preservingTemporaryPlan: true)
        guard let plan, let root = dependencies.rootURL() else { return }
        preflight = dependencies.preflight(plan, root)
    }

    func requestExport() {
        runPreflight()
        guard let preflight, preflight.canExport else { return }
        if preflight.warnings.isEmpty {
            performExport(allowingWarnings: false)
        } else {
            showingWarningConfirmation = true
        }
    }

    func performExport(allowingWarnings: Bool) {
        guard !isExporting,
              let plan,
              let root = dependencies.rootURL(),
              let outputDirectory else { return }
        showingWarningConfirmation = false
        errorMessage = nil
        let id = UUID()
        exportOperationID = id
        isExporting = true
        exportTask = Task { [weak self, dependencies] in
            do {
                let result = try await dependencies.export(
                    plan,
                    root,
                    outputDirectory,
                    allowingWarnings
                )
                guard let self, !Task.isCancelled, self.exportOperationID == id else { return }
                dependencies.recordExport(result, plan)
                self.draft = dependencies.loadArchive()
                self.lastExportURL = result.packageURL ?? result.outputURL
                self.lastReportURL = result.reportPDFURL
                self.preflight = result.preflight
                self.pane = .history
                self.finishExport(id)
            } catch is CancellationError {
                self?.finishExport(id)
            } catch {
                guard let self, self.exportOperationID == id else { return }
                self.errorMessage = error.localizedDescription
                self.finishExport(id)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportOperationID = nil
        isExporting = false
    }

    func publicationAssetDidChange() {
        reloadArchive()
        refreshPlan(preservingTemporaryPlan: true)
    }

    nonisolated static func reconciling(
        _ refreshed: PublicationExportPlan,
        with existing: PublicationExportPlan
    ) -> PublicationExportPlan {
        var result = refreshed
        let refreshedByID = Dictionary(uniqueKeysWithValues: refreshed.items.map { ($0.id, $0) })
        var orderedIDs: Set<String> = []
        let ordered = existing.items.compactMap { previous -> ExportPlanItem? in
            guard var item = refreshedByID[previous.id] else { return nil }
            item.isIncluded = previous.isIncluded && item.exclusionReason != "The Markdown file is missing."
            orderedIDs.insert(item.id)
            return item
        }
        var additions = refreshed.items.filter { !orderedIDs.contains($0.id) }
        for index in additions.indices where additions[index].exclusionReason == "The Markdown file is missing." {
            additions[index].isIncluded = false
        }
        result.items = ordered + additions
        return result
    }

    private func applyTextMetadata() {
        draft.metadata.authors = authorsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        draft.metadata.keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updatePreview() {
        guard let plan, let root = dependencies.rootURL() else {
            previewText = ""
            return
        }
        let rendered = dependencies.preview(plan, root)
        previewText = rendered.sections.map { section in
            "# \(section.title)\n\n" + section.blocks.map { block in
                if block.kind == .image {
                    return "[Image: \(block.altText.isEmpty ? block.imageURL?.lastPathComponent ?? "image" : block.altText)]"
                }
                return block.text
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        }
        .joined(separator: "\n\n––––––––––––––––––––\n\n")
    }

    private func finishExport(_ id: UUID) {
        guard exportOperationID == id else { return }
        exportTask = nil
        exportOperationID = nil
        isExporting = false
    }
}
