import SwiftUI

struct SystemicRevisionCenterView: View {
    @ObservedObject var store: WritingProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: ResearchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let onNavigate: (SystemicRevisionFinding) -> Void

    @State private var selectedPass: RevisionPass = .structure
    @State private var selectedClassification: RevisionFindingClassification?
    @State private var selectedStatus: RevisionFindingStatus = .open
    @State private var selectedFindingID: UUID?
    @State private var checkedFindingIDs: Set<UUID> = []
    @State private var pendingChangeSet: RevisionChangeSet?
    @State private var pendingAIRequest: AIRequestPreview?
    @State private var isRunningAI = false
    @State private var showingGoalEditor = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                passSidebar.frame(minWidth: 190, idealWidth: 210, maxWidth: 245)
                findingsList.frame(minWidth: 330, idealWidth: 390)
                findingDetail.frame(minWidth: 410)
            }
        }
        .frame(minWidth: 1_020, minHeight: 680)
        .sheet(item: $pendingChangeSet) { set in
            RevisionChangeSetPreviewView(store: store, originalSet: set)
        }
        .sheet(item: $pendingAIRequest) { preview in
            AIRequestPreviewView(preview: preview) { confirmed in
                pendingAIRequest = nil
                runAI(confirmed)
            }
        }
        .sheet(isPresented: $showingGoalEditor) {
            RevisionGoalEditor(defaultPass: selectedPass) { title, notes, pass in
                store.addRevisionGoal(title: title, notes: notes, pass: pass)
            }
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Systemic Revision Center").font(.title2.bold())
                Text(scanSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.runLocalRevisionScan(targetGrade: settings.targetGrade, sources: library.sources)
            } label: {
                if store.isScanningRevisions { ProgressView().controlSize(.small) }
                else { Label("Scan Locally", systemImage: "checklist") }
            }
            .disabled(store.isScanningRevisions)
            Button("Deepen w/ AI…") { prepareAI() }.disabled(isRunningAI || store.isScanningRevisions)
            Button("Preview Selected Changes…") { prepareChanges() }
                .buttonStyle(.borderedProminent)
                .disabled(checkedFindingIDs.isEmpty)
            Button("Done") { dismiss() }
        }.padding()
    }

    private var passSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedPass) {
                Section("Revision Passes") {
                    ForEach(RevisionPass.allCases) { pass in
                        HStack {
                            Label(pass.title, systemImage: pass.systemImage)
                            Spacer()
                            Text("\(openCount(pass))").font(.caption).foregroundStyle(.secondary)
                        }.tag(pass)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Revision Goals").font(.headline)
                    Spacer()
                    Button { showingGoalEditor = true } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                }
                ForEach(store.revisionArchive.goals.filter { $0.revisionPass == selectedPass }) { goal in
                    HStack(alignment: .top) {
                        Button { store.toggleRevisionGoal(goal.id) } label: {
                            Image(systemName: goal.isComplete ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title).strikethrough(goal.isComplete).lineLimit(2)
                            if !goal.notes.isEmpty { Text(goal.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                    }.contextMenu { Button("Remove", role: .destructive) { store.removeRevisionGoal(goal.id) } }
                }
                if store.revisionArchive.goals.allSatisfy({ $0.revisionPass != selectedPass }) {
                    Text("No goals for this pass.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    }

    private var findingsList: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(RevisionFindingStatus.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 105)
                Picker("Class", selection: $selectedClassification) {
                    Text("All classes").tag(RevisionFindingClassification?.none)
                    ForEach(RevisionFindingClassification.allCases) { Text($0.title).tag(Optional($0)) }
                }.labelsHidden()
            }.padding(10)
            Divider()
            List(selection: $selectedFindingID) {
                ForEach(filteredFindings) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { checkedFindingIDs.contains(finding.id) },
                            set: { checked in
                                if checked { checkedFindingIDs.insert(finding.id) }
                                else { checkedFindingIDs.remove(finding.id) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .disabled(finding.replacement == nil || finding.excerpt.isEmpty || finding.chapterPath == nil)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(finding.title).fontWeight(.medium).lineLimit(2)
                            Text(finding.classification.title).font(.caption).foregroundStyle(classificationColor(finding.classification))
                            if let path = finding.chapterPath { Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }.tag(finding.id)
                }
            }
            if filteredFindings.isEmpty {
                Text("No findings match these filters.").font(.caption).foregroundStyle(.secondary).padding()
            }
        }
    }

    @ViewBuilder
    private var findingDetail: some View {
        if let finding = selectedFinding {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(finding.revisionPass.title, systemImage: finding.revisionPass.systemImage)
                        Spacer()
                        Text(finding.origin == .local ? "Local" : "AI · \(finding.provider ?? "Provider")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(finding.title).font(.title3.bold())
                    Text(finding.classification.title).foregroundStyle(classificationColor(finding.classification))
                    Text(finding.detail).textSelection(.enabled)
                    if !finding.excerpt.isEmpty {
                        GroupBox("Manuscript excerpt") {
                            Text(finding.excerpt).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    }
                    if let replacement = finding.replacement {
                        GroupBox("Proposed replacement — not applied") {
                            Text(replacement).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    }
                    HStack {
                        if finding.chapterPath != nil {
                            Button("Show in Manuscript") { onNavigate(finding); dismiss() }
                        }
                        Spacer()
                        if finding.status != .dismissed { Button("Dismiss") { store.setRevisionFindingStatus(finding.id, status: .dismissed) } }
                        if finding.status != .resolved { Button("Mark Resolved") { store.setRevisionFindingStatus(finding.id, status: .resolved) } }
                        if finding.status != .open { Button("Reopen") { store.setRevisionFindingStatus(finding.id, status: .open) } }
                    }
                    if !store.revisionAISummary.isEmpty {
                        Divider()
                        Text("Latest AI summary").font(.headline)
                        Text(store.revisionAISummary).foregroundStyle(.secondary)
                    }
                }.padding(18)
            }
        } else {
            ContentUnavailableView("Select a Finding", systemImage: selectedPass.systemImage)
        }
    }

    private var filteredFindings: [SystemicRevisionFinding] {
        store.revisionArchive.findings.filter {
            $0.revisionPass == selectedPass && $0.status == selectedStatus && (selectedClassification == nil || $0.classification == selectedClassification)
        }
    }

    private var selectedFinding: SystemicRevisionFinding? {
        store.revisionArchive.findings.first { $0.id == selectedFindingID }
    }

    private var scanSummary: String {
        let open = store.revisionArchive.findings.filter { $0.status == .open }.count
        guard let date = store.revisionArchive.lastLocalScanAt else { return "Not scanned yet · all analysis remains local until you choose Deepen w/ AI" }
        return "\(open) open finding\(open == 1 ? "" : "s") · local scan \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func openCount(_ pass: RevisionPass) -> Int {
        store.revisionArchive.findings.filter { $0.revisionPass == pass && $0.status == .open }.count
    }

    private func classificationColor(_ value: RevisionFindingClassification) -> Color {
        switch value {
        case .confirmedProblem: .red
        case .probableProblem: .orange
        case .authorQuestion: .blue
        case .opportunity: .green
        }
    }

    private func prepareChanges() {
        do { pendingChangeSet = try store.makeRevisionChangeSet(findingIDs: checkedFindingIDs) }
        catch { errorMessage = error.localizedDescription }
    }

    private func prepareAI() {
        guard settings.isProviderReady(settings.provider) else {
            errorMessage = settings.provider.requiresAPIKey
                ? "Add your \(settings.provider.title) API key and choose a model in Settings first."
                : "Detect and choose a local Ollama model in Settings first."
            return
        }
        do {
            let context = try store.revisionAIContext(sources: library.sources)
            pendingAIRequest = AIRequestPreview(
                purpose: .systemicRevision(kind: store.projectKind ?? .fiction, passes: [selectedPass]),
                provider: settings.provider,
                model: settings.model(for: settings.provider),
                primaryLabel: "Manuscript, bibliography, and research notes",
                primaryText: context,
                styleGuide: store.styleText,
                includesStyleGuide: !store.styleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                referenceContext: nil,
                includesReferenceContext: false,
                sourceRange: nil,
                sourceText: nil
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func runAI(_ request: AIRequestPreview) {
        isRunningAI = true
        Task {
            defer { isRunningAI = false }
            do {
                let response = try await SystemicRevisionAIService().deepen(
                    request: request,
                    documents: store.revisionDocuments(),
                    apiKey: settings.apiKey(for: request.provider)
                )
                store.addAIRevisionFindings(response.findings, summary: response.summary)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct RevisionGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    let defaultPass: RevisionPass
    let onSave: (String, String, RevisionPass) -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var pass: RevisionPass

    init(defaultPass: RevisionPass, onSave: @escaping (String, String, RevisionPass) -> Void) {
        self.defaultPass = defaultPass
        self.onSave = onSave
        _pass = State(initialValue: defaultPass)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Revision Goal").font(.title2.bold())
            TextField("Goal", text: $title)
            TextField("Notes", text: $notes)
            Picker("Pass", selection: $pass) { ForEach(RevisionPass.allCases) { Text($0.title).tag($0) } }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Add Goal") { onSave(title, notes, pass); dismiss() }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(22).frame(width: 460)
    }
}

private struct RevisionChangeSetPreviewView: View {
    @ObservedObject var store: WritingProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var set: RevisionChangeSet
    @State private var showingConfirmation = false

    init(store: WritingProjectStore, originalSet: RevisionChangeSet) {
        self.store = store
        _set = State(initialValue: originalSet)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Preview Coordinated Changes").font(.title2.bold())
                    Text("Every affected file is snapshotted. Apply registers one macOS Undo action.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Recheck") { revalidate() }
                Button("Cancel") { dismiss() }
                Button("Apply Included Changes…") { showingConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!set.hasChanges || set.hasConflicts)
            }.padding()
            Divider()
            List {
                ForEach($set.changes) { $change in
                    VStack(alignment: .leading, spacing: 9) {
                        Toggle(isOn: $change.isIncluded) {
                            HStack { Text(change.chapterPath).font(.headline); Spacer(); Text(change.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        HStack(alignment: .top) {
                            GroupBox("Before — exact manuscript text") {
                                Text(change.originalText).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                            GroupBox("After — editable proposal") {
                                TextEditor(text: $change.replacementText).frame(minHeight: 70)
                            }
                        }
                        if let conflict = change.conflict { Label(conflict, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    }.padding(.vertical, 6)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear { revalidate() }
        .onChange(of: set.changes) { _, _ in revalidate() }
        .confirmationDialog("Apply these coordinated changes?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Apply \(set.includedChanges.count) Change\(set.includedChanges.count == 1 ? "" : "s")") {
                store.applyRevisionChangeSet(set)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kistulentz will recheck every passage, snapshot every affected file, and stop without writing if any proposal is stale, ambiguous, or overlapping.")
        }
    }

    private func revalidate() {
        let checked = store.validateRevisionChangeSet(set)
        if checked != set { set = checked }
    }
}
