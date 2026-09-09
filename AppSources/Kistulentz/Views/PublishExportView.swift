import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PublishExportView: View {
    @ObservedObject var store: WritingProjectStore
    @ObservedObject var publicationStore: PublicationStore
    @EnvironmentObject private var researchLibrary: ResearchLibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: PublishExportViewModel

    init(store: WritingProjectStore, publicationStore: PublicationStore) {
        _store = ObservedObject(wrappedValue: store)
        _publicationStore = ObservedObject(wrappedValue: publicationStore)
        _model = StateObject(wrappedValue: PublishExportViewModel(
            store: store,
            publicationStore: publicationStore
        ))
    }

    var body: some View {
        NavigationSplitView {
            List(PublicationWorkspacePane.allCases, selection: $model.pane) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("Publish")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(model.draft.metadata.title.isEmpty ? store.projectName : model.draft.metadata.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(model.format.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
        } detail: {
            Group {
                switch model.pane ?? .plan {
                case .plan: planPane
                case .setup: setupPane
                case .matter: matterPane
                case .profile: profilePane
                case .preflight: preflightPane
                case .history: historyPane
                }
            }
            .navigationTitle(model.pane?.rawValue ?? "Publish")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { model.persistDraft(); dismiss() }
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 720)
        .accessibilityIdentifier("PublishExportView")
        .onAppear { model.load(sources: researchLibrary.sources) }
        .onChange(of: researchLibrary.sources) { _, sources in model.updateSources(sources) }
        .onDisappear {
            model.persistDraft()
            model.cancelExport()
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "Export with preflight warnings?",
            isPresented: $model.showingWarningConfirmation,
            titleVisibility: .visible
        ) {
            Button("Export Anyway") { model.performExport(allowingWarnings: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Blocking errors are resolved. The remaining warnings will be recorded in export history.")
        }
    }

    private var planPane: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Profile", selection: $model.selectedProfileID) {
                        ForEach(model.draft.profiles) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: model.selectedProfileID) { _, newValue in model.selectProfile(newValue) }
                    Picker("Format", selection: $model.format) {
                        ForEach(PublicationExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: model.format) { _, _ in model.refreshPlan(preservingTemporaryPlan: true) }
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
                    if let plan = model.plan {
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
                        .onMove(perform: model.movePlanItems)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Button("Reset Temporary Plan") { model.refreshPlan(preservingTemporaryPlan: false) }
                    Button("Save Inclusions to Project Organization") { model.savePlanInclusions() }
                    Spacer()
                    Text("\(model.plan?.includedItems.count ?? 0) included")
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
                    Text(model.previewText.isEmpty ? "Nothing is included yet." : model.previewText)
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
                TextField("Title", text: $model.draft.metadata.title)
                TextField("Subtitle", text: $model.draft.metadata.subtitle)
                TextField("Authors (one per line)", text: $model.authorsText, axis: .vertical).lineLimit(2...5)
                TextField("Language", text: $model.draft.metadata.language)
                TextField("ISBN or identifier", text: $model.draft.metadata.identifier)
                TextField("Publisher", text: $model.draft.metadata.publisher)
                TextField("Publication date", text: $model.draft.metadata.publicationDate)
                TextField("Edition", text: $model.draft.metadata.edition)
                TextField("Rights", text: $model.draft.metadata.rights, axis: .vertical).lineLimit(2...4)
                TextField("Description", text: $model.draft.metadata.description, axis: .vertical).lineLimit(3...8)
                TextField("Keywords (comma separated)", text: $model.keywordsText)
            }
            Section("Cover") {
                LabeledContent("Digital cover") { Text(model.draft.metadata.coverImageRelativePath ?? "Not selected").foregroundStyle(.secondary) }
                TextField("Cover alternative text", text: $model.draft.metadata.coverAltText)
                HStack {
                    Button("Choose Cover Image…", action: chooseCover)
                    if model.draft.metadata.coverImageRelativePath != nil {
                        Button("Remove") {
                            model.draft.metadata.coverImageRelativePath = nil
                            model.saveMatter()
                        }
                    }
                }
                LabeledContent("Separate print-cover PDF") { Text(model.draft.metadata.printCoverPDFRelativePath ?? "Optional").foregroundStyle(.secondary) }
                HStack {
                    Button("Choose Print-Cover PDF…", action: choosePrintCover)
                    if model.draft.metadata.printCoverPDFRelativePath != nil {
                        Button("Remove") {
                            model.draft.metadata.printCoverPDFRelativePath = nil
                            model.saveMatter()
                        }
                    }
                }
                Text("Kistulentz generates the print interior. It keeps a supplied print-cover PDF alongside the project without calculating a vendor-specific spine or wrap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Save Publication Setup") { model.saveMetadata() }.buttonStyle(.borderedProminent)
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
                Button("Regenerate Safe Pages") { model.regenerateSafeMatter() }
                Button("Save Matter") { model.saveMatter() }
                    .buttonStyle(.borderedProminent)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($model.draft.matter) { $item in
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
                                    .accessibilityLabel(item.isLocked ? "Unlock \(item.title)" : "Lock \(item.title)")
                                    .accessibilityHint("Locked generated matter is preserved when publication matter is regenerated.")
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
        if let index = model.draft.profiles.firstIndex(where: { $0.id == model.selectedProfileID }) {
            ExportProfileEditor(
                profile: profileBinding(at: index),
                destinations: model.draft.selectedDestinations,
                onApplyDestinationPreset: { model.applyDestinationPreset() },
                onSave: { model.saveMatter() },
                onDuplicate: { model.duplicateSelectedProfile() },
                onDelete: model.draft.profiles[index].kind == .custom
                    ? { model.deleteSelectedProfile() }
                    : nil
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
                Button("Run Preflight") { model.runPreflight() }
            }
            if let preflight = model.preflight {
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
                    Text(model.outputDirectory?.path ?? "Choose where finished files should go")
                        .lineLimit(1).truncationMode(.middle)
                    if let lastExportURL = model.lastExportURL {
                        Text("Last export: \(lastExportURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Choose Output Folder…", action: chooseOutputFolder)
                if let lastExportURL = model.lastExportURL {
                    Button("Reveal Last Export") { NSWorkspace.shared.activateFileViewerSelecting([lastExportURL]) }
                }
                if let lastReportURL = model.lastReportURL {
                    Button("Open Readiness Report") { NSWorkspace.shared.open(lastReportURL) }
                }
                if model.isExporting {
                    Button("Cancel Export", role: .cancel) { model.cancelExport() }
                }
                Button(model.isExporting ? "Exporting…" : "Export \(model.format.title)") { model.requestExport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExporting || model.outputDirectory == nil || model.preflight?.canExport != true)
            }
            if model.isExporting { ProgressView().progressViewStyle(.linear) }
        }
        .padding(18)
    }

    private var historyPane: some View {
        List {
            ForEach(model.draft.history) { record in
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
            if model.draft.history.isEmpty { ContentUnavailableView("No exports yet", systemImage: "shippingbox") }
        }
    }

    private func inclusionBinding(_ id: String) -> Binding<Bool> {
        Binding {
            model.plan?.items.first(where: { $0.id == id })?.isIncluded ?? false
        } set: { value in
            model.setInclusion(value, for: id)
        }
    }

    private func profileBinding(at index: Int) -> Binding<ExportProfile> {
        Binding {
            model.draft.profiles[index]
        } set: { profile in
            guard model.draft.profiles.indices.contains(index) else { return }
            model.draft.profiles[index] = profile
        }
    }

    private func destinationBinding(_ destination: PublicationDestination) -> Binding<Bool> {
        Binding {
            model.draft.selectedDestinations.contains(destination)
        } set: { selected in
            model.setDestination(destination, isSelected: selected)
        }
    }

    private func chooseCover() {
        model.persistDraft()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, UTType(filenameExtension: "webp")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        publicationStore.copyPublicationCover(from: url)
        model.publicationAssetDidChange()
    }

    private func choosePrintCover() {
        model.persistDraft()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        publicationStore.copyPrintCover(from: url)
        model.publicationAssetDidChange()
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        model.outputDirectory = panel.url
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
