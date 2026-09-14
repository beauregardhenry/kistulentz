import Combine
import Foundation

@MainActor
final class ProjectImportAssistantViewModel: ObservableObject {
    @Published var sources: [ProjectImportSource] = []
    @Published var skippedItems: [String] = []
    @Published var conversions: [UUID: ProjectImportConversion] = [:]
    @Published var failures: [UUID: ProjectImportFailure] = [:]
    @Published var decisions: [UUID: DocumentTrackedChangeDecision] = [:]
    @Published var selectedSourceID: UUID?
    @Published var destination: ProjectImportDestination = .combinedMarkdown
    @Published var projectName = "Imported Project"
    @Published var projectKind: WritingProjectKind = .fiction
    @Published var projectParentURL: URL?
    @Published private(set) var isDiscovering = false
    @Published private(set) var isConverting = false
    @Published private(set) var isWriting = false
    @Published private(set) var completedCount = 0
    @Published private(set) var currentSourceName = ""
    @Published var errorMessage: String?

    private let conversionOperation = CancellableOperationController()

    var hasResults: Bool {
        !conversions.isEmpty || !failures.isEmpty || isConverting
    }

    var orderedConversions: [ProjectImportConversion] {
        sources.compactMap { conversions[$0.id] }
    }

    var selectedConversion: ProjectImportConversion? {
        if let selectedSourceID { return conversions[selectedSourceID] }
        return orderedConversions.first
    }

    var selectedFailure: ProjectImportFailure? {
        selectedSourceID.flatMap { failures[$0] }
    }

    var requiredTrackedChangeIDs: Set<UUID> {
        Set(orderedConversions.flatMap(\.reviewCards).map(\.id))
    }

    var hierarchyError: String? {
        guard destination != .combinedMarkdown, !orderedConversions.isEmpty else { return nil }
        do {
            _ = try ProjectImportOutlineBuilder.build(
                paths: orderedConversions.indices.map { "Imported \($0 + 1).md" },
                sources: orderedConversions.map(\.source)
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func canFinish(hasCurrentProjectImporter: Bool) -> Bool {
        guard !orderedConversions.isEmpty,
              Set(decisions.keys).isSuperset(of: requiredTrackedChangeIDs),
              hierarchyError == nil else { return false }
        switch destination {
        case .combinedMarkdown:
            return true
        case .newProject:
            return projectParentURL != nil
                && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .currentProject:
            return hasCurrentProjectImporter
        }
    }

    var finishButtonTitle: String {
        switch destination {
        case .combinedMarkdown: "Save Combined Markdown…"
        case .newProject: "Create and Open Project"
        case .currentProject: "Add to Current Project"
        }
    }

    func statusIcon(for id: UUID) -> String {
        if conversions[id] != nil { return "checkmark.circle.fill" }
        if failures[id] != nil { return "exclamationmark.triangle.fill" }
        if isConverting { return "clock" }
        return "doc"
    }

    func updateSource<Value>(
        id: UUID,
        keyPath: WritableKeyPath<ProjectImportSource, Value>,
        value: Value
    ) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index][keyPath: keyPath] = value
    }

    func setDecision(_ decision: DocumentTrackedChangeDecision?, for id: UUID) {
        if let decision {
            decisions[id] = decision
        } else {
            decisions.removeValue(forKey: id)
        }
    }

    func decideAll(_ decision: DocumentTrackedChangeDecision, in conversion: ProjectImportConversion) {
        for card in conversion.reviewCards {
            decisions[card.id] = decision
        }
    }

    func moveSource(from index: Int, by offset: Int) {
        let target = index + offset
        guard sources.indices.contains(index), sources.indices.contains(target) else { return }
        sources.swapAt(index, target)
    }

    func removeSource(_ id: UUID) {
        sources.removeAll { $0.id == id }
        if selectedSourceID == id { selectedSourceID = sources.first?.id }
    }

    func addSelections(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isDiscovering = true
            Task { @MainActor in
                do {
                    let discovery = try await Task.detached(priority: .userInitiated) {
                        try ProjectImportSourceDiscovery.discover(from: urls)
                    }.value
                    let existing = Set(sources.map {
                        $0.url.standardizedFileURL.resolvingSymlinksInPath().path
                    })
                    let additions = discovery.sources.filter {
                        !existing.contains($0.url.standardizedFileURL.resolvingSymlinksInPath().path)
                    }
                    sources.append(contentsOf: additions)
                    skippedItems.append(contentsOf: discovery.skippedItems)
                    selectedSourceID = selectedSourceID ?? additions.first?.id ?? sources.first?.id
                } catch {
                    errorMessage = error.localizedDescription
                }
                isDiscovering = false
            }
        }
    }

    func startConversion() {
        conversions.removeAll()
        failures.removeAll()
        decisions.removeAll()
        convert(sources)
    }

    func retryFailures() {
        let retrySources = sources.filter { failures[$0.id] != nil }
        for source in retrySources { failures.removeValue(forKey: source.id) }
        convert(retrySources)
    }

    func cancelConversion() {
        conversionOperation.cancel()
        isConverting = false
        currentSourceName = ""
    }

    func resetResults() {
        cancelConversion()
        conversions.removeAll()
        failures.removeAll()
        decisions.removeAll()
        completedCount = 0
    }

    func previewMarkdown(for conversion: ProjectImportConversion) -> String {
        let markdown = conversion.renderedMarkdown(decisions: decisions)
        return destination == .combinedMarkdown
            ? ProjectImportMarkdown.hierarchicalSection(
                title: conversion.source.title,
                kind: conversion.source.kind,
                markdown: markdown
            )
            : markdown
    }

    func writeCombinedMarkdown(to url: URL, onComplete: @escaping (URL) -> Void) {
        isWriting = true
        let items = orderedConversions
        let chosenDecisions = decisions
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ProjectImportOutputService.writeCombinedMarkdown(
                        items,
                        decisions: chosenDecisions,
                        to: url
                    )
                }.value
                onComplete(result.rootURL)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWriting = false
        }
    }

    func createNewProject(onComplete: @escaping (URL) -> Void) {
        guard let parent = projectParentURL else { return }
        isWriting = true
        let items = orderedConversions
        let chosenDecisions = decisions
        let chosenName = projectName
        let chosenKind = projectKind
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ProjectImportOutputService.createProject(
                        from: items,
                        decisions: chosenDecisions,
                        in: parent,
                        name: chosenName,
                        kind: chosenKind
                    )
                }.value
                onComplete(result.rootURL)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWriting = false
        }
    }

    func addDocumentsToCurrentProject(
        using operation: ([ProjectImportConversion], [UUID: DocumentTrackedChangeDecision]) throws -> ProjectImportWriteResult,
        onComplete: (URL) -> Void
    ) {
        isWriting = true
        do {
            let result = try operation(orderedConversions, decisions)
            onComplete(result.rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        isWriting = false
    }

    private func convert(_ targets: [ProjectImportSource]) {
        guard !targets.isEmpty else { return }
        conversionOperation.cancel()
        isConverting = true
        completedCount = sources.count - targets.count
        conversionOperation.start { [weak self] token in
            guard let self else { return }
            for source in targets {
                guard self.conversionOperation.accepts(token) else { break }
                currentSourceName = source.url.lastPathComponent
#if UI_TEST_HOST
                if let rawDelay = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_IMPORT_DELAY_MS"],
                   let delay = Int(rawDelay), delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard self.conversionOperation.accepts(token) else { break }
                }
#endif
                let outcome: (ProjectImportConversion?, String?) = await Task.detached(priority: .userInitiated) {
                    do {
                        return (Optional(try ProjectImportConversionService.load(source)), nil)
                    } catch {
                        return (nil, error.localizedDescription)
                    }
                }.value
                guard self.conversionOperation.accepts(token) else { break }
                if let conversion = outcome.0 {
                    conversions[source.id] = conversion
                    selectedSourceID = selectedSourceID ?? source.id
                } else {
                    failures[source.id] = ProjectImportFailure(
                        source: source,
                        message: outcome.1 ?? "The document could not be converted."
                    )
                }
                completedCount += 1
            }
            guard self.conversionOperation.finish(token) else { return }
            self.isConverting = false
            self.currentSourceName = ""
            if self.selectedSourceID.flatMap({ self.conversions[$0] ?? nil }) == nil {
                self.selectedSourceID = self.orderedConversions.first?.id ?? self.failures.values.first?.id
            }
        }
    }
}
