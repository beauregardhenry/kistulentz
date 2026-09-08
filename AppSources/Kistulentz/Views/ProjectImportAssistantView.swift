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

    @StateObject private var model = ProjectImportAssistantViewModel()
    @State private var showingSourceChooser = false
    @State private var showingProjectParentChooser = false
#if UI_TEST_HOST
    @State private var didLoadUITestSources = false
#endif

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
        // Keep the footer reachable on smaller displays and scaled CI desktops.
        // Both columns already scroll, so the assistant can safely compress vertically.
        .frame(minWidth: 1_020, minHeight: 600, idealHeight: 720)
        .fileImporter(
            isPresented: $showingSourceChooser,
            allowedContentTypes: allowedSourceTypes,
            allowsMultipleSelection: true,
            onCompletion: model.addSelections
        )
        .fileImporter(
            isPresented: $showingProjectParentChooser,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls): model.projectParentURL = urls.first
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("Project Import Assistant", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onExitCommand {
            if model.isConverting {
                model.cancelConversion()
            } else if !model.isWriting {
                onCancel()
            }
        }
#if UI_TEST_HOST
        .onAppear { loadUITestConfigurationIfNeeded() }
#endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Project Import Assistant")
                    .font(.title2.bold())
                    .accessibilityIdentifier("ProjectImportAssistantView")
                Text("Preview and organize every document before Kistulentz writes anything.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isConverting {
                Button("Cancel Conversion", role: .cancel, action: model.cancelConversion)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Close", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWriting)
            }
        }
        .padding()
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(model.hasResults ? "Import Results" : "Documents and Order", systemImage: "list.number")
                    .font(.headline)
                Spacer()
                if model.hasResults && !model.isConverting {
                    Button("Edit Plan") { model.resetResults() }
                }
            }
            .padding(12)
            Divider()

            if model.sources.isEmpty {
                ContentUnavailableView {
                    Label("No Documents Yet", systemImage: "doc.badge.plus")
                } description: {
                    Text("Add individual files, folders, or both. Folders are searched recursively.")
                } actions: {
                    Button("Add Files or Folders…") { showingSourceChooser = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $model.selectedSourceID) {
                    ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                        sourceRow(source, index: index)
                            .tag(source.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            VStack(alignment: .leading, spacing: 9) {
                if model.isConverting {
                    ProgressView(
                        "Converting \(model.currentSourceName)…",
                        value: Double(model.completedCount),
                        total: Double(max(model.sources.count, 1))
                    )
                    Text("\(model.completedCount) of \(model.sources.count) finished")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !model.hasResults {
                    HStack {
                        Button("Add Files or Folders…") { showingSourceChooser = true }
                            .disabled(model.isDiscovering)
                        if model.isDiscovering { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Convert and Preview", action: model.startConversion)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.sources.isEmpty || model.isDiscovering)
                    }
                    Text("Supported: Markdown, DOCX, RTF, RTFD, HTML, ODT, and TXT.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Label("\(model.orderedConversions.count) converted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !model.failures.isEmpty {
                            Label("\(model.failures.count) failed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        if !model.failures.isEmpty {
                            Button("Retry Failed", action: model.retryFailures)
                        }
                    }
                    if !model.skippedItems.isEmpty {
                        Text("\(model.skippedItems.count) unsupported or unreadable item\(model.skippedItems.count == 1 ? " was" : "s were") skipped during discovery.")
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
                Image(systemName: model.statusIcon(for: source.id))
                    .foregroundStyle(statusColor(for: source.id))
                if model.hasResults {
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

            if let failure = model.failures[source.id] {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.hasResults {
                HStack {
                    Text(source.url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { model.moveSource(from: index, by: -1) } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("Move earlier")
                    .accessibilityLabel("Move \(source.title) earlier")
                    Button { model.moveSource(from: index, by: 1) } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == model.sources.count - 1)
                    .help("Move later")
                    .accessibilityLabel("Move \(source.title) later")
                    Button(role: .destructive) { model.removeSource(source.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from import")
                    .accessibilityLabel("Remove \(source.title) from import")
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
                if let selectedConversion = model.selectedConversion {
                    Text(selectedConversion.source.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()

            if let conversion = model.selectedConversion {
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
                                Text(model.destination == .combinedMarkdown ? "Combined-file section" : "Imported Markdown")
                                    .font(.headline)
                                Spacer()
                                Text("\(model.previewMarkdown(for: conversion).split(whereSeparator: \.isWhitespace).count) words")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ScrollView([.vertical, .horizontal]) {
                                Text(model.previewMarkdown(for: conversion))
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
            } else if let failure = model.selectedFailure {
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
                        model.decideAll(.accept, in: conversion)
                    }
                    Button("Reject All") {
                        model.decideAll(.reject, in: conversion)
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
            if model.hasResults {
                Picker("Create", selection: $model.destination) {
                    ForEach(ProjectImportDestination.allCases) { option in
                        Text(option.title)
                            .tag(option)
                            .disabled(option == .currentProject && addToCurrentProject == nil)
                    }
                }
                .frame(width: 310)
                .accessibilityIdentifier("ImportDestinationPicker")

                destinationControls
            } else {
                Label("Original files are never modified.", systemImage: "lock.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.hasResults {
                if let hierarchyError = model.hierarchyError {
                    Text(hierarchyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 310, alignment: .trailing)
                } else if !model.failures.isEmpty {
                    Text("Only the successfully converted documents will be written.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(model.finishButtonTitle, action: finish)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canFinish(hasCurrentProjectImporter: addToCurrentProject != nil) || model.isWriting)
                if model.isWriting { ProgressView().controlSize(.small) }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var destinationControls: some View {
        switch model.destination {
        case .combinedMarkdown:
            Text("Part = H1, Chapter = H2, Scene/Section = H3")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .newProject:
            TextField("Project name", text: $model.projectName)
                .frame(width: 160)
            Picker("Kind", selection: $model.projectKind) {
                ForEach(WritingProjectKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .labelsHidden()
            .frame(width: 110)
            Button(model.projectParentURL?.lastPathComponent ?? "Choose Location…") {
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

    private func statusColor(for id: UUID) -> Color {
        if model.conversions[id] != nil { return .green }
        if model.failures[id] != nil { return .orange }
        return .secondary
    }

    private func binding<Value>(
        for id: UUID,
        keyPath: WritableKeyPath<ProjectImportSource, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.sources.first(where: { $0.id == id })![keyPath: keyPath] },
            set: { model.updateSource(id: id, keyPath: keyPath, value: $0) }
        )
    }

    private func trackedDecisionBinding(_ id: UUID) -> Binding<DocumentTrackedChangeDecision?> {
        Binding(
            get: { model.decisions[id] },
            set: { model.setDecision($0, for: id) }
        )
    }

    private func finish() {
        guard model.canFinish(hasCurrentProjectImporter: addToCurrentProject != nil) else { return }
        switch model.destination {
        case .combinedMarkdown: chooseCombinedMarkdownDestination()
        case .newProject: createNewProject()
        case .currentProject: addDocumentsToCurrentProject()
        }
    }

    private func chooseCombinedMarkdownDestination() {
#if UI_TEST_HOST
        if let path = ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_IMPORT_OUTPUT_PATH"],
           !path.isEmpty {
            writeCombinedMarkdown(to: URL(fileURLWithPath: path))
            return
        }
#endif
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
        model.writeCombinedMarkdown(to: url) { resultURL in
            onComplete(.markdown(resultURL))
        }
    }

    private func createNewProject() {
        model.createNewProject { resultURL in
            onComplete(.project(resultURL))
        }
    }

    private func addDocumentsToCurrentProject() {
        guard let addToCurrentProject else { return }
        model.addDocumentsToCurrentProject(using: addToCurrentProject) { resultURL in
            onComplete(.project(resultURL))
        }
    }

#if UI_TEST_HOST
    private func loadUITestConfigurationIfNeeded() {
        guard !didLoadUITestSources else { return }
        didLoadUITestSources = true
        let environment = ProcessInfo.processInfo.environment
        if let parentPath = environment["KISTULENTZ_UI_TEST_IMPORT_PROJECT_PARENT"],
           !parentPath.isEmpty {
            model.projectParentURL = URL(fileURLWithPath: parentPath, isDirectory: true)
        }
        guard let rawPaths = environment["KISTULENTZ_UI_TEST_IMPORT_PATHS"] else { return }
        let urls = rawPaths
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
        guard !urls.isEmpty else { return }
        model.addSelections(.success(urls))
    }
#endif
}
