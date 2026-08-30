import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ProjectImportCompletion {
    case markdown(URL)
    case project(URL)
}

struct ProjectImportAssistantView: View {
    let currentProjectName: String?
    let addToCurrentProject: (([ProjectImportConversion], [UUID: DocumentTrackedChangeDecision]) throws -> ProjectImportWriteResult)?
    let onComplete: (ProjectImportCompletion) -> Void
    let onCancel: () -> Void

    @State private var sources: [ProjectImportSource] = []
    @State private var skippedItems: [String] = []
    @State private var conversions: [UUID: ProjectImportConversion] = [:]
    @State private var failures: [UUID: ProjectImportFailure] = [:]
    @State private var decisions: [UUID: DocumentTrackedChangeDecision] = [:]
    @State private var selectedSourceID: UUID?
    @State private var destination: ProjectImportDestination = .combinedMarkdown
    @State private var projectName = "Imported Project"
    @State private var projectKind: WritingProjectKind = .fiction
    @State private var projectParentURL: URL?
    @State private var showingSourceChooser = false
    @State private var showingProjectParentChooser = false
    @State private var isDiscovering = false
    @State private var isConverting = false
    @State private var isWriting = false
    @State private var completedCount = 0
    @State private var currentSourceName = ""
    @State private var conversionTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sourceColumn
                    .frame(minWidth: 410, idealWidth: 460, maxWidth: 540)
                previewColumn
                    .frame(minWidth: 520)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1_020, minHeight: 720)
        .fileImporter(
            isPresented: $showingSourceChooser,
            allowedContentTypes: allowedSourceTypes,
            allowsMultipleSelection: true,
            onCompletion: addSelections
        )
        .fileImporter(
            isPresented: $showingProjectParentChooser,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls): projectParentURL = urls.first
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Project Import Assistant", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onExitCommand {
            if isConverting {
                cancelConversion()
            } else if !isWriting {
                onCancel()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Project Import Assistant")
                    .font(.title2.bold())
                Text("Preview and organize every document before Kistulentz writes anything.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isConverting {
                Button("Cancel Conversion", role: .cancel, action: cancelConversion)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Close", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWriting)
            }
        }
        .padding()
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(hasResults ? "Import Results" : "Documents and Order", systemImage: "list.number")
                    .font(.headline)
                Spacer()
                if hasResults && !isConverting {
                    Button("Edit Plan") { resetResults() }
                }
            }
            .padding(12)
            Divider()

            if sources.isEmpty {
                ContentUnavailableView {
                    Label("No Documents Yet", systemImage: "doc.badge.plus")
                } description: {
                    Text("Add individual files, folders, or both. Folders are searched recursively.")
                } actions: {
                    Button("Add Files or Folders…") { showingSourceChooser = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selectedSourceID) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        sourceRow(source, index: index)
                            .tag(source.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            VStack(alignment: .leading, spacing: 9) {
                if isConverting {
                    ProgressView(
                        "Converting \(currentSourceName)…",
                        value: Double(completedCount),
                        total: Double(max(sources.count, 1))
                    )
                    Text("\(completedCount) of \(sources.count) finished")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !hasResults {
                    HStack {
                        Button("Add Files or Folders…") { showingSourceChooser = true }
                            .disabled(isDiscovering)
                        if isDiscovering { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Convert and Preview", action: startConversion)
                            .buttonStyle(.borderedProminent)
                            .disabled(sources.isEmpty || isDiscovering)
                    }
                    Text("Supported: Markdown, DOCX, RTF, RTFD, HTML, ODT, and TXT.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Label("\(orderedConversions.count) converted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !failures.isEmpty {
                            Label("\(failures.count) failed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        if !failures.isEmpty {
                            Button("Retry Failed", action: retryFailures)
                        }
                    }
                    if !skippedItems.isEmpty {
                        Text("\(skippedItems.count) unsupported or unreadable item\(skippedItems.count == 1 ? " was" : "s were") skipped during discovery.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: ProjectImportSource, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: statusIcon(for: source.id))
                    .foregroundStyle(statusColor(for: source.id))
                if hasResults {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title).fontWeight(.medium)
                        Text(source.kind.title + " · " + source.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("Document title", text: binding(for: source.id, keyPath: \.title))
                        .textFieldStyle(.plain)
                        .fontWeight(.medium)
                    Picker("Structure", selection: binding(for: source.id, keyPath: \.kind)) {
                        ForEach(OutlineNodeKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 108)
                }
                Spacer(minLength: 4)
            }

            if let failure = failures[source.id] {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasResults {
                HStack {
                    Text(source.url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { moveSource(from: index, by: -1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("Move earlier")
                    Button { moveSource(from: index, by: 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == sources.count - 1)
                    .help("Move later")
                    Button(role: .destructive) { removeSource(source.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from import")
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Preview", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                if let selectedConversion {
                    Text(selectedConversion.source.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()

            if let conversion = selectedConversion {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversion.source.title).font(.title3.bold())
                            Text(conversion.source.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if !conversion.reviewCards.isEmpty {
                            trackedChanges(for: conversion)
                        }

                        if !conversion.notices.isEmpty {
                            conversionNotices(conversion.notices)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(destination == .combinedMarkdown ? "Combined-file section" : "Imported Markdown")
                                    .font(.headline)
                                Spacer()
                                Text("\(previewMarkdown(for: conversion).split(whereSeparator: \.isWhitespace).count) words")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ScrollView([.vertical, .horizontal]) {
                                Text(previewMarkdown(for: conversion))
                                    .font(.system(.callout, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(12)
                            }
                            .frame(minHeight: 260, maxHeight: 420)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(16)
                }
            } else if let failure = selectedFailure {
                ContentUnavailableView(
                    "Conversion Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure.message)
                )
            } else {
                ContentUnavailableView(
                    "Preview Appears Here",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Arrange and assign the source documents, then choose Convert and Preview.")
                )
            }
        }
    }

    private func trackedChanges(for conversion: ProjectImportConversion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tracked Changes").font(.headline)
                Spacer()
                Menu("Decide All") {
                    Button("Accept All") {
                        for card in conversion.reviewCards { decisions[card.id] = .accept }
                    }
                    Button("Reject All") {
                        for card in conversion.reviewCards { decisions[card.id] = .reject }
                    }
                }
            }
            ForEach(conversion.reviewCards) { card in
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        card.kind.title,
                        systemImage: card.kind == .insertion ? "plus.circle.fill" : "minus.circle.fill"
                    )
                    .font(.subheadline.bold())
                    Text(card.changedMarkdown)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(5)
                    Picker("Decision", selection: trackedDecisionBinding(card.id)) {
                        Text("Choose…").tag(DocumentTrackedChangeDecision?.none)
                        ForEach(DocumentTrackedChangeDecision.allCases) { decision in
                            Text(decision.title).tag(Optional(decision))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func conversionNotices(_ notices: [DocumentImportNotice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversion Report").font(.headline)
            ForEach(notices) { notice in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: notice.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(notice.severity == .warning ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title).font(.subheadline.bold())
                        Text(notice.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            if hasResults {
                Picker("Create", selection: $destination) {
                    ForEach(ProjectImportDestination.allCases) { option in
                        Text(option.title)
                            .tag(option)
                            .disabled(option == .currentProject && addToCurrentProject == nil)
                    }
                }
                .frame(width: 310)

                destinationControls
            } else {
                Label("Original files are never modified.", systemImage: "lock.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hasResults {
                if let hierarchyError {
                    Text(hierarchyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 310, alignment: .trailing)
                } else if !failures.isEmpty {
                    Text("Only the successfully converted documents will be written.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(finishButtonTitle, action: finish)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFinish || isWriting)
                if isWriting { ProgressView().controlSize(.small) }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var destinationControls: some View {
        switch destination {
        case .combinedMarkdown:
            Text("Part = H1, Chapter = H2, Scene/Section = H3")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .newProject:
            TextField("Project name", text: $projectName)
                .frame(width: 160)
            Picker("Kind", selection: $projectKind) {
                ForEach(WritingProjectKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .labelsHidden()
            .frame(width: 110)
            Button(projectParentURL?.lastPathComponent ?? "Choose Location…") {
                showingProjectParentChooser = true
            }
        case .currentProject:
            Label(currentProjectName ?? "No project open", systemImage: "folder.fill")
                .font(.callout)
        }
    }

    private var allowedSourceTypes: [UTType] {
        var seen: Set<String> = []
        return ([.folder, .markdownDocument] + DocumentImportFormat.importableContentTypes)
            .filter { seen.insert($0.identifier).inserted }
    }

    private var hasResults: Bool {
        !conversions.isEmpty || !failures.isEmpty || isConverting
    }

    private var orderedConversions: [ProjectImportConversion] {
        sources.compactMap { conversions[$0.id] }
    }

    private var selectedConversion: ProjectImportConversion? {
        if let selectedSourceID { return conversions[selectedSourceID] }
        return orderedConversions.first
    }

    private var selectedFailure: ProjectImportFailure? {
        selectedSourceID.flatMap { failures[$0] }
    }

    private var requiredTrackedChangeIDs: Set<UUID> {
        Set(orderedConversions.flatMap(\.reviewCards).map(\.id))
    }

    private var hierarchyError: String? {
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

    private var canFinish: Bool {
        guard !orderedConversions.isEmpty,
              Set(decisions.keys).isSuperset(of: requiredTrackedChangeIDs),
              hierarchyError == nil else { return false }
        switch destination {
        case .combinedMarkdown: return true
        case .newProject:
            return projectParentURL != nil
                && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .currentProject: return addToCurrentProject != nil
        }
    }

    private var finishButtonTitle: String {
        switch destination {
        case .combinedMarkdown: "Save Combined Markdown…"
        case .newProject: "Create and Open Project"
        case .currentProject: "Add to Current Project"
        }
    }

    private func statusIcon(for id: UUID) -> String {
        if conversions[id] != nil { return "checkmark.circle.fill" }
        if failures[id] != nil { return "exclamationmark.triangle.fill" }
        if isConverting { return "clock" }
        return "doc"
    }

    private func statusColor(for id: UUID) -> Color {
        if conversions[id] != nil { return .green }
        if failures[id] != nil { return .orange }
        return .secondary
    }

    private func binding<Value>(
        for id: UUID,
        keyPath: WritableKeyPath<ProjectImportSource, Value>
    ) -> Binding<Value> {
        Binding(
            get: { sources.first(where: { $0.id == id })![keyPath: keyPath] },
            set: { value in
                guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
                sources[index][keyPath: keyPath] = value
            }
        )
    }

    private func trackedDecisionBinding(_ id: UUID) -> Binding<DocumentTrackedChangeDecision?> {
        Binding(
            get: { decisions[id] },
            set: { value in
                if let value { decisions[id] = value } else { decisions.removeValue(forKey: id) }
            }
        )
    }

    private func moveSource(from index: Int, by offset: Int) {
        let target = index + offset
        guard sources.indices.contains(index), sources.indices.contains(target) else { return }
        sources.swapAt(index, target)
    }

    private func removeSource(_ id: UUID) {
        sources.removeAll { $0.id == id }
        if selectedSourceID == id { selectedSourceID = sources.first?.id }
    }

    private func addSelections(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error): errorMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isDiscovering = true
            Task { @MainActor in
                do {
                    let discovery = try await Task.detached(priority: .userInitiated) {
                        try ProjectImportSourceDiscovery.discover(from: urls)
                    }.value
                    let existing = Set(sources.map { $0.url.standardizedFileURL.resolvingSymlinksInPath().path })
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

    private func startConversion() {
        conversions.removeAll()
        failures.removeAll()
        decisions.removeAll()
        convert(sources)
    }

    private func retryFailures() {
        let retrySources = sources.filter { failures[$0.id] != nil }
        for source in retrySources { failures.removeValue(forKey: source.id) }
        convert(retrySources)
    }

    private func convert(_ targets: [ProjectImportSource]) {
        guard !targets.isEmpty else { return }
        isConverting = true
        completedCount = sources.count - targets.count
        conversionTask = Task { @MainActor in
            for source in targets {
                guard !Task.isCancelled else { break }
                currentSourceName = source.url.lastPathComponent
                let outcome: (ProjectImportConversion?, String?) = await Task.detached(priority: .userInitiated) {
                    do {
                        return (Optional(try ProjectImportConversionService.load(source)), nil)
                    } catch {
                        return (nil, error.localizedDescription)
                    }
                }.value
                guard !Task.isCancelled else { break }
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
            isConverting = false
            currentSourceName = ""
            if selectedSourceID.flatMap({ conversions[$0] ?? nil }) == nil {
                selectedSourceID = orderedConversions.first?.id ?? failures.values.first?.id
            }
        }
    }

    private func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
        isConverting = false
        currentSourceName = ""
    }

    private func resetResults() {
        cancelConversion()
        conversions.removeAll()
        failures.removeAll()
        decisions.removeAll()
        completedCount = 0
    }

    private func previewMarkdown(for conversion: ProjectImportConversion) -> String {
        let markdown = conversion.renderedMarkdown(decisions: decisions)
        return destination == .combinedMarkdown
            ? ProjectImportMarkdown.hierarchicalSection(
                title: conversion.source.title,
                kind: conversion.source.kind,
                markdown: markdown
            )
            : markdown
    }

    private func finish() {
        guard canFinish else { return }
        switch destination {
        case .combinedMarkdown: chooseCombinedMarkdownDestination()
        case .newProject: createNewProject()
        case .currentProject: addDocumentsToCurrentProject()
        }
    }

    private func chooseCombinedMarkdownDestination() {
        let panel = NSSavePanel()
        panel.title = "Save Combined Markdown"
        panel.message = "Choose a new filename. Kistulentz will not replace an existing document."
        panel.prompt = "Save"
        panel.allowedContentTypes = [.markdownDocument]
        panel.nameFieldStringValue = "Combined Manuscript.md"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in writeCombinedMarkdown(to: url) }
        }
    }

    private func writeCombinedMarkdown(to url: URL) {
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
                onComplete(.markdown(result.rootURL))
            } catch {
                errorMessage = error.localizedDescription
            }
            isWriting = false
        }
    }

    private func createNewProject() {
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
                onComplete(.project(result.rootURL))
            } catch {
                errorMessage = error.localizedDescription
            }
            isWriting = false
        }
    }

    private func addDocumentsToCurrentProject() {
        guard let addToCurrentProject else { return }
        isWriting = true
        do {
            let result = try addToCurrentProject(orderedConversions, decisions)
            onComplete(.project(result.rootURL))
        } catch {
            errorMessage = error.localizedDescription
        }
        isWriting = false
    }
}
