import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PublicationWorkspacePane: String, CaseIterable, Identifiable {
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

struct PublishExportView: View {
    @ObservedObject var store: WritingProjectStore
    @EnvironmentObject private var researchLibrary: ResearchLibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var pane: PublicationWorkspacePane? = .plan
    @State private var draft = PublicationArchive()
    @State private var selectedProfileID = UUID()
    @State private var format: PublicationExportFormat = .epub
    @State private var plan: PublicationExportPlan?
    @State private var previewText = ""
    @State private var preflight: PublicationPreflightReport?
    @State private var outputDirectory: URL?
    @State private var isExporting = false
    @State private var lastExportURL: URL?
    @State private var lastReportURL: URL?
    @State private var errorMessage: String?
    @State private var showingWarningConfirmation = false
    @State private var authorsText = ""
    @State private var keywordsText = ""

    var body: some View {
        NavigationSplitView {
            List(PublicationWorkspacePane.allCases, selection: $pane) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("Publish")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(draft.metadata.title.isEmpty ? store.projectName : draft.metadata.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(format.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
        } detail: {
            Group {
                switch pane ?? .plan {
                case .plan: planPane
                case .setup: setupPane
                case .matter: matterPane
                case .profile: profilePane
                case .preflight: preflightPane
                case .history: historyPane
                }
            }
            .navigationTitle(pane?.rawValue ?? "Publish")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { persistDraft(); dismiss() } }
            }
        }
        .frame(minWidth: 1040, minHeight: 720)
        .onAppear(perform: load)
        .onDisappear(perform: persistDraft)
        .alert("Kistulentz", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Export with preflight warnings?",
            isPresented: $showingWarningConfirmation,
            titleVisibility: .visible
        ) {
            Button("Export Anyway") { performExport(allowingWarnings: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Blocking errors are resolved. The remaining warnings will be recorded in export history.")
        }
    }

    private var planPane: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Profile", selection: $selectedProfileID) {
                        ForEach(draft.profiles) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: selectedProfileID) { _, newValue in selectProfile(newValue) }
                    Picker("Format", selection: $format) {
                        ForEach(PublicationExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: format) { _, _ in refreshPlan(preservingTemporaryPlan: true) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Publication destinations").font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 7) {
                        ForEach(PublicationDestination.allCases) { destination in
                            Toggle(destination.title, isOn: destinationBinding(destination))
                                .toggleStyle(.checkbox)
                        }
                    }
                    Text("Choose several when one file is intended for multiple stores. A destination that does not accept the selected format appears as a preflight error.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("These inclusions and this order are temporary until you explicitly save inclusions to Project Organization.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List {
                    if let plan {
                        ForEach(plan.items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: icon(for: item.kind)).foregroundStyle(.secondary)
                                Toggle(isOn: inclusionBinding(item.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                        Text(item.exclusionReason ?? item.sourcePath ?? item.kind.rawValue.capitalized)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(item.exclusionReason == "The Markdown file is missing.")
                            }
                        }
                        .onMove(perform: movePlanItems)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Button("Reset Temporary Plan") { refreshPlan(preservingTemporaryPlan: false) }
                    Button("Save Inclusions to Project Organization") { savePlanInclusions() }
                    Spacer()
                    Text("\(plan?.includedItems.count ?? 0) included")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(minWidth: 470)

            VStack(alignment: .leading, spacing: 10) {
                Text("Exact Content Preview").font(.headline)
                Text("Generated locally from the current temporary plan. No export file is created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(previewText.isEmpty ? "Nothing is included yet." : previewText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(18)
            .frame(minWidth: 390)
        }
    }

    private var setupPane: some View {
        Form {
            Section("Book Identity") {
                TextField("Title", text: $draft.metadata.title)
                TextField("Subtitle", text: $draft.metadata.subtitle)
                TextField("Authors (one per line)", text: $authorsText, axis: .vertical).lineLimit(2...5)
                TextField("Language", text: $draft.metadata.language)
                TextField("ISBN or identifier", text: $draft.metadata.identifier)
                TextField("Publisher", text: $draft.metadata.publisher)
                TextField("Publication date", text: $draft.metadata.publicationDate)
                TextField("Edition", text: $draft.metadata.edition)
                TextField("Rights", text: $draft.metadata.rights, axis: .vertical).lineLimit(2...4)
                TextField("Description", text: $draft.metadata.description, axis: .vertical).lineLimit(3...8)
                TextField("Keywords (comma separated)", text: $keywordsText)
            }
            Section("Cover") {
                LabeledContent("Digital cover") { Text(draft.metadata.coverImageRelativePath ?? "Not selected").foregroundStyle(.secondary) }
                TextField("Cover alternative text", text: $draft.metadata.coverAltText)
                HStack {
                    Button("Choose Cover Image…", action: chooseCover)
                    if draft.metadata.coverImageRelativePath != nil {
                        Button("Remove") { draft.metadata.coverImageRelativePath = nil }
                    }
                }
                LabeledContent("Separate print-cover PDF") { Text(draft.metadata.printCoverPDFRelativePath ?? "Optional").foregroundStyle(.secondary) }
                HStack {
                    Button("Choose Print-Cover PDF…", action: choosePrintCover)
                    if draft.metadata.printCoverPDFRelativePath != nil {
                        Button("Remove") { draft.metadata.printCoverPDFRelativePath = nil }
                    }
                }
                Text("Kistulentz generates the print interior. It keeps a supplied print-cover PDF alongside the project without calculating a vendor-specific spine or wrap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Save Publication Setup") { saveMetadata() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var matterPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editable generated pages").font(.headline)
                    Text("Regeneration skips every locked or author-edited page.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Regenerate Safe Pages") {
                    draft.matter = PublicationMatterGenerator.regenerating(draft.matter, metadata: draft.metadata)
                }
                Button("Save Matter") { persistDraft(); refreshPlan(preservingTemporaryPlan: true) }
                    .buttonStyle(.borderedProminent)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($draft.matter) { $item in
                        DisclosureGroup {
                            TextEditor(text: $item.markdown)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minHeight: 145)
                                .padding(4)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        } label: {
                            HStack {
                                Toggle("Include", isOn: $item.isIncluded).toggleStyle(.checkbox)
                                TextField("Page name", text: $item.title).font(.headline)
                                Spacer()
                                if item.hasAuthorEdits { Text("Author edited").font(.caption).foregroundStyle(.orange) }
                                Toggle(isOn: $item.isLocked) { Image(systemName: item.isLocked ? "lock.fill" : "lock.open") }
                                    .toggleStyle(.button).help(item.isLocked ? "Unlock this page" : "Lock this page")
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
        .padding(18)
    }

    @ViewBuilder private var profilePane: some View {
        if let index = draft.profiles.firstIndex(where: { $0.id == selectedProfileID }) {
            ExportProfileEditor(
                profile: $draft.profiles[index],
                destinations: draft.selectedDestinations,
                onApplyDestinationPreset: applyDestinationPreset,
                onSave: { persistDraft(); refreshPlan(preservingTemporaryPlan: true) },
                onDuplicate: duplicateSelectedProfile,
                onDelete: draft.profiles[index].kind == .custom ? deleteSelectedProfile : nil
            )
        } else {
            ContentUnavailableView("Choose an export profile", systemImage: "slider.horizontal.3")
        }
    }

    private var preflightPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local publication preflight").font(.headline)
                    Text("Hard errors block export. Warnings require explicit approval.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Preflight") { runPreflight() }
            }
            if let preflight {
                HStack(spacing: 14) {
                    Label("\(preflight.errors.count) errors", systemImage: "xmark.octagon.fill").foregroundStyle(preflight.errors.isEmpty ? Color.secondary : Color.red)
                    Label("\(preflight.warnings.count) warnings", systemImage: "exclamationmark.triangle.fill").foregroundStyle(preflight.warnings.isEmpty ? Color.secondary : Color.orange)
                    Label("\(preflight.information.count) notes", systemImage: "info.circle.fill").foregroundStyle(.secondary)
                }
                List(preflight.findings) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: findingIcon(finding.severity)).foregroundStyle(findingColor(finding.severity))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(finding.title).font(.headline)
                                Text(finding.readinessStatus.title)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                            Text(finding.detail).font(.callout).foregroundStyle(.secondary)
                            if let path = finding.sourcePath { Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                            if let address = finding.requirementURL, let url = URL(string: address) {
                                Link("Official requirement", destination: url).font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            } else {
                ContentUnavailableView("Preflight has not run", systemImage: "checkmark.seal", description: Text("Run it after finalizing the export plan and profile."))
                    .frame(maxHeight: .infinity)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(outputDirectory?.path ?? "Choose where finished files should go")
                        .lineLimit(1).truncationMode(.middle)
                    if let lastExportURL { Text("Last export: \(lastExportURL.lastPathComponent)").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Choose Output Folder…", action: chooseOutputFolder)
                if let lastExportURL { Button("Reveal Last Export") { NSWorkspace.shared.activateFileViewerSelecting([lastExportURL]) } }
                if let lastReportURL { Button("Open Readiness Report") { NSWorkspace.shared.open(lastReportURL) } }
                Button(isExporting ? "Exporting…" : "Export \(format.title)") { requestExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || outputDirectory == nil || preflight?.canExport != true)
            }
            if isExporting { ProgressView().progressViewStyle(.linear) }
        }
        .padding(18)
    }

    private var historyPane: some View {
        List {
            ForEach(draft.history) { record in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(record.format.title, systemImage: record.format.systemImage).font(.headline)
                        Text(record.profileName).foregroundStyle(.secondary)
                        Spacer()
                        Text(record.createdAt, style: .date)
                        Text(record.createdAt, style: .time)
                    }
                    Text(record.outputPath).font(.caption).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                        Text("SHA-256 \(record.sha256)").font(.system(size: 10, design: .monospaced)).lineLimit(1)
                        if record.warningCount > 0 { Label("\(record.warningCount) warnings", systemImage: "exclamationmark.triangle") }
                        Spacer()
                        Button("Copy Checksum") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.sha256, forType: .string)
                        }
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.outputPath)]) }
                            .disabled(!FileManager.default.fileExists(atPath: record.outputPath))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .overlay {
            if draft.history.isEmpty { ContentUnavailableView("No exports yet", systemImage: "shippingbox") }
        }
    }

    private func load() {
        draft = store.publicationArchive
        selectedProfileID = draft.selectedProfileID
        authorsText = draft.metadata.authors.joined(separator: "\n")
        keywordsText = draft.metadata.keywords.joined(separator: ", ")
        format = draft.profiles.first(where: { $0.id == selectedProfileID })?.preferredFormat ?? .epub
        refreshPlan(preservingTemporaryPlan: false)
    }

    private func persistDraft() {
        draft.selectedProfileID = selectedProfileID
        draft.metadata.authors = authorsText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        draft.metadata.keywords = keywordsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        store.updatePublicationArchive(draft)
    }

    private func saveMetadata() {
        draft.metadata.authors = authorsText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        draft.metadata.keywords = keywordsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        draft.matter = PublicationMatterGenerator.regenerating(draft.matter, metadata: draft.metadata)
        persistDraft()
        draft = store.publicationArchive
        refreshPlan(preservingTemporaryPlan: true)
    }

    private func selectProfile(_ id: UUID) {
        guard let profile = draft.profiles.first(where: { $0.id == id }) else { return }
        draft.selectedProfileID = id
        format = profile.preferredFormat
        persistDraft()
        refreshPlan(preservingTemporaryPlan: true)
    }

    private func refreshPlan(preservingTemporaryPlan: Bool) {
        persistDraft()
        do {
            var refreshed = try store.publicationPlan(sources: researchLibrary.sources, profileID: selectedProfileID, format: format)
            if preservingTemporaryPlan, let existing = plan {
                let refreshedByID = Dictionary(uniqueKeysWithValues: refreshed.items.map { ($0.id, $0) })
                var includedIDs: Set<String> = []
                let ordered = existing.items.compactMap { previous -> ExportPlanItem? in
                    guard var item = refreshedByID[previous.id] else { return nil }
                    item.isIncluded = previous.isIncluded && item.exclusionReason != "The Markdown file is missing."
                    includedIDs.insert(item.id)
                    return item
                }
                refreshed.items = ordered + refreshed.items.filter { !includedIDs.contains($0.id) }
            }
            plan = refreshed
            updatePreview()
            preflight = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatePreview() {
        guard let plan, let root = store.rootURL else { previewText = ""; return }
        let rendered = PublicationExporter.preview(plan: plan, root: root)
        previewText = rendered.sections.map { section in
            "# \(section.title)\n\n" + section.blocks.map { block in
                block.kind == .image ? "[Image: \(block.altText.isEmpty ? block.imageURL?.lastPathComponent ?? "image" : block.altText)]" : block.text
            }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }.joined(separator: "\n\n––––––––––––––––––––\n\n")
    }

    private func inclusionBinding(_ id: String) -> Binding<Bool> {
        Binding {
            plan?.items.first(where: { $0.id == id })?.isIncluded ?? false
        } set: { value in
            guard var current = plan, let index = current.items.firstIndex(where: { $0.id == id }) else { return }
            current.items[index].isIncluded = value
            plan = current
            updatePreview()
            preflight = nil
        }
    }

    private func destinationBinding(_ destination: PublicationDestination) -> Binding<Bool> {
        Binding {
            draft.selectedDestinations.contains(destination)
        } set: { selected in
            if selected {
                if !draft.selectedDestinations.contains(destination) {
                    draft.selectedDestinations.append(destination)
                }
            } else {
                draft.selectedDestinations.removeAll { $0 == destination }
            }
            draft.selectedDestinations = PublicationDestination.allCases.filter { draft.selectedDestinations.contains($0) }
            persistDraft()
            refreshPlan(preservingTemporaryPlan: true)
        }
    }

    private func movePlanItems(from offsets: IndexSet, to destination: Int) {
        guard var current = plan else { return }
        current.items.move(fromOffsets: offsets, toOffset: destination)
        plan = current
        updatePreview()
        preflight = nil
    }

    private func savePlanInclusions() {
        guard let plan else { return }
        for item in plan.items {
            guard let id = item.outlineNodeID, var node = store.outlineNode(id: id) else { continue }
            node.metadata.includedInExport = item.isIncluded
            store.updateOutlineNode(node)
        }
        refreshPlan(preservingTemporaryPlan: false)
    }

    private func duplicateSelectedProfile() {
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

    private func applyDestinationPreset() {
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

    private func deleteSelectedProfile() {
        draft.profiles.removeAll { $0.id == selectedProfileID && $0.kind == .custom }
        selectedProfileID = draft.profiles.first?.id ?? UUID()
        persistDraft()
        refreshPlan(preservingTemporaryPlan: false)
    }

    private func chooseCover() {
        persistDraft()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, UTType(filenameExtension: "webp")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.copyPublicationCover(from: url)
        draft = store.publicationArchive
    }

    private func choosePrintCover() {
        persistDraft()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.copyPrintCover(from: url)
        draft = store.publicationArchive
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        outputDirectory = panel.url
    }

    private func runPreflight() {
        refreshPlan(preservingTemporaryPlan: true)
        guard let plan, let root = store.rootURL else { return }
        preflight = PublicationPreflight.run(plan: plan, root: root)
    }

    private func requestExport() {
        runPreflight()
        guard let preflight, preflight.canExport else { return }
        if !preflight.warnings.isEmpty { showingWarningConfirmation = true }
        else { performExport(allowingWarnings: false) }
    }

    private func performExport(allowingWarnings: Bool) {
        guard let plan, let root = store.rootURL, let outputDirectory else { return }
        isExporting = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PublicationExporter.export(plan: plan, root: root, outputDirectory: outputDirectory, allowingWarnings: allowingWarnings)
                }.value
                store.recordPublicationExport(result, plan: plan)
                draft = store.publicationArchive
                lastExportURL = result.packageURL ?? result.outputURL
                lastReportURL = result.reportPDFURL
                preflight = result.preflight
                pane = .history
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func icon(for kind: ExportPlanItemKind) -> String {
        switch kind {
        case .frontMatter: "text.book.closed"
        case .part: "rectangle.stack"
        case .manuscript: "doc.text"
        case .backMatter: "books.vertical"
        }
    }

    private func findingIcon(_ severity: PublicationPreflightSeverity) -> String {
        switch severity { case .error: "xmark.octagon.fill"; case .warning: "exclamationmark.triangle.fill"; case .information: "info.circle.fill" }
    }

    private func findingColor(_ severity: PublicationPreflightSeverity) -> Color {
        switch severity { case .error: .red; case .warning: .orange; case .information: .secondary }
    }
}

private struct ExportProfileEditor: View {
    @Binding var profile: ExportProfile
    let destinations: [PublicationDestination]
    let onApplyDestinationPreset: () -> Void
    let onSave: () -> Void
    let onDuplicate: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Form {
            Section("Destination Preset") {
                LabeledContent("Selected destinations", value: destinations.isEmpty ? "None" : destinations.map(\.shortTitle).joined(separator: ", "))
                Text("Applying the preset chooses the required output format and raises locally checkable minimum settings. It does not replace your trim, typography, or design decisions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Recommended Settings", action: onApplyDestinationPreset)
                    .disabled(destinations.isEmpty)
            }
            Section("Named Profile") {
                TextField("Profile name", text: $profile.name)
                LabeledContent("Starting point", value: profile.kind.title)
                Picker("Preferred format", selection: $profile.preferredFormat) {
                    ForEach(PublicationExportFormat.allCases) { Text($0.title).tag($0) }
                }
                Picker("Citations", selection: $profile.citationMode) {
                    ForEach(PublicationCitationMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Include bibliography", isOn: $profile.includeBibliography)
                Toggle("Include cover", isOn: $profile.includeCover)
                Toggle("Include table of contents", isOn: $profile.includeTableOfContents)
                Toggle("Include front matter", isOn: $profile.includeFrontMatter)
                Toggle("Include back matter", isOn: $profile.includeBackMatter)
            }
            Section("Page & Type") {
                Picker("Page or trim size", selection: $profile.layout.pageSize) {
                    ForEach(PublicationPageSize.allCases) { Text($0.title).tag($0) }
                }
                TextField("Body font", text: $profile.layout.bodyFontName)
                TextField("Heading font", text: $profile.layout.headingFontName)
                TextField("Body size", value: $profile.layout.bodyFontSize, format: .number).frame(maxWidth: 140)
                TextField("Line height", value: $profile.layout.lineHeightMultiple, format: .number).frame(maxWidth: 140)
                TextField("Paragraph spacing", value: $profile.layout.paragraphSpacing, format: .number).frame(maxWidth: 140)
                TextField("First-line indent", value: $profile.layout.firstLineIndent, format: .number).frame(maxWidth: 140)
                Toggle("Hyphenation", isOn: $profile.layout.hyphenationEnabled)
            }
            Section("Margins & Running Matter") {
                TextField("Top margin", value: $profile.layout.topMargin, format: .number).frame(maxWidth: 140)
                TextField("Bottom margin", value: $profile.layout.bottomMargin, format: .number).frame(maxWidth: 140)
                TextField("Inside margin", value: $profile.layout.insideMargin, format: .number).frame(maxWidth: 140)
                TextField("Outside margin", value: $profile.layout.outsideMargin, format: .number).frame(maxWidth: 140)
                Toggle("Running header", isOn: $profile.layout.headerEnabled)
                Toggle("Footer", isOn: $profile.layout.footerEnabled)
                Toggle("Page numbers", isOn: $profile.layout.pageNumbersEnabled)
                Picker("Chapter openings", selection: $profile.layout.chapterOpening) {
                    ForEach(PublicationChapterOpening.allCases) { Text($0.title).tag($0) }
                }
                Picker("Print bleed", selection: $profile.printBleed) {
                    ForEach(PublicationPrintBleed.allCases) { Text($0.title).tag($0) }
                }
                Text("Use bleed only when artwork must reach the top, bottom, or outside trimmed edge. Kistulentz never adds gutter bleed or printer marks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Duplicate as Custom Profile", action: onDuplicate)
                    if let onDelete { Button("Delete Custom Profile", role: .destructive, action: onDelete) }
                    Spacer()
                    Button("Save Profile", action: onSave).buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
    }
}
