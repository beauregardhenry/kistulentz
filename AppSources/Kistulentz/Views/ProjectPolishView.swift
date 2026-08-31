import SwiftUI

struct ProjectPolishView: View {
    @ObservedObject var store: WritingProjectStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var report: ProjectPolishReport?
    @State private var scanTask: Task<Void, Never>?
    @State private var processedDocumentCount = 0
    @State private var totalDocumentCount = 0
    @State private var currentDocumentTitle = ""
    @State private var enabledStages = Set(ProjectPolishStage.allCases)
    @State private var errorMessage: String?
    @State private var pendingChangeSet: RevisionChangeSet?
    @State private var showingApplyConfirmation = false
    @State private var isStopping = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 940, minHeight: 680)
        .onAppear { startScan() }
        .onDisappear { scanTask?.cancel() }
        .confirmationDialog(
            "Apply the selected project changes?",
            isPresented: $showingApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Included Changes") { applyPendingChanges() }
            Button("Cancel", role: .cancel) { pendingChangeSet = nil }
        } message: {
            Text("Kistulentz will recheck every exact passage, snapshot every affected file, and register one macOS Undo action. If any included passage is stale, ambiguous, or overlapping, no file will be changed.")
        }
        .alert("Project Polish", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Polish Project")
                    .font(.title2.bold())
                Text("Review local corrections passage by passage and apply one or more stages across the whole project.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if scanTask != nil {
            VStack(spacing: 16) {
                ProgressView(
                    value: Double(processedDocumentCount),
                    total: Double(max(totalDocumentCount, 1))
                )
                .frame(maxWidth: 440)
                Text(isStopping
                    ? "Stopping after the current document…"
                    : "Checking \(currentDocumentTitle.isEmpty ? "the project" : currentDocumentTitle)…")
                    .font(.headline)
                Text("\(processedDocumentCount) of \(totalDocumentCount) documents completed")
                    .foregroundStyle(.secondary)
                Button("Cancel Scan", role: .cancel) {
                    isStopping = true
                    scanTask?.cancel()
                }
                .disabled(isStopping)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else if let report {
            reportView(report)
        } else {
            ContentUnavailableView(
                "Project Polish could not start",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage ?? "Open a Kistulentz project and try again.")
            )
        }
    }

    private func reportView(_ report: ProjectPolishReport) -> some View {
        VStack(spacing: 0) {
            stageControls(report)
            Divider()
            if report.changes.isEmpty {
                ContentUnavailableView(
                    report.wasCancelled ? "Scan cancelled" : "No safe automatic changes",
                    systemImage: report.wasCancelled ? "stop.circle" : "checkmark.circle",
                    description: Text(emptyReportDescription(report))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if report.wasCancelled || !report.failures.isEmpty {
                        scanNotes(report)
                    }
                    ForEach(ProjectPolishStage.allCases) { stage in
                        let stageChanges = report.changes.filter { $0.stage == stage }
                        if !stageChanges.isEmpty {
                            Section {
                                ForEach(stageChanges) { change in
                                    ProjectPolishChangeRow(change: changeBinding(change.id))
                                }
                            } header: {
                                Label(
                                    "\(stage.title) · \(stageChanges.count)",
                                    systemImage: stage.systemImage
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func stageControls(_ report: ProjectPolishReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Apply in stages")
                    .font(.headline)
                Spacer()
                Text("\(includedChangeCount) included of \(report.changes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                ForEach(ProjectPolishStage.allCases) { stage in
                    Toggle(isOn: stageBinding(stage)) {
                        Label(stage.shortTitle, systemImage: stage.systemImage)
                    }
                    .toggleStyle(.checkbox)
                }
                Spacer()
                Button("Include All") { setAllChangesIncluded(true) }
                Button("Clear All") { setAllChangesIncluded(false) }
            }
            Text("Disable a stage to leave it untouched now. You can run Project Polish again later for the remaining stages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func scanNotes(_ report: ProjectPolishReport) -> some View {
        Section("Scan notes") {
            if report.wasCancelled {
                Label(
                    "The scan stopped after \(report.completedDocumentCount) of \(report.totalDocumentCount) documents. Completed results remain reviewable.",
                    systemImage: "stop.circle"
                )
            }
            ForEach(report.failures) { failure in
                Label {
                    VStack(alignment: .leading) {
                        Text(failure.chapterTitle).font(.headline)
                        Text(failure.message).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let report {
                Text("\(report.advisoryCount) advisory item\(report.advisoryCount == 1 ? "" : "s") and \(report.skippedCount) unsafe or ambiguous change\(report.skippedCount == 1 ? "" : "s") were not made automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Scan Again") { startScan() }
                .disabled(scanTask != nil)
            Button("Recheck Included") { recheckIncludedChanges(showErrors: true) }
                .disabled(scanTask != nil || includedChangeCount == 0)
            Button("Apply Included Changes…") { prepareApply() }
                .buttonStyle(.borderedProminent)
                .disabled(scanTask != nil || includedChangeCount == 0)
        }
        .padding()
    }

    private var includedChangeCount: Int {
        report?.changes.filter {
            $0.isIncluded && enabledStages.contains($0.stage)
        }.count ?? 0
    }

    private func startScan() {
        scanTask?.cancel()
        report = nil
        errorMessage = nil
        processedDocumentCount = 0
        currentDocumentTitle = ""
        isStopping = false
        let inputs: (documents: [ManuscriptDocument], styleDecisions: [ProjectStyleDecision])
        do {
            inputs = try store.projectPolishInputs()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        totalDocumentCount = inputs.documents.count
        scanTask = Task {
            let result = await ProjectPolishService().scan(
                documents: inputs.documents,
                targetGrade: settings.targetGrade,
                styleDecisions: inputs.styleDecisions
            ) { completed, total, title in
                processedDocumentCount = completed
                totalDocumentCount = total
                currentDocumentTitle = title
            }
            report = result
            scanTask = nil
            isStopping = false
            recheckIncludedChanges(showErrors: false)
        }
    }

    private func stageBinding(_ stage: ProjectPolishStage) -> Binding<Bool> {
        Binding(
            get: { enabledStages.contains(stage) },
            set: { enabled in
                if enabled { enabledStages.insert(stage) }
                else { enabledStages.remove(stage) }
            }
        )
    }

    private func changeBinding(_ id: UUID) -> Binding<ProjectPolishChange> {
        Binding(
            get: {
                report?.changes.first(where: { $0.id == id })
                    ?? ProjectPolishChange(
                        id: id,
                        chapterPath: "",
                        chapterTitle: "",
                        stage: .correctness,
                        categoryTitle: "",
                        originalText: "",
                        replacementText: "",
                        explanation: ""
                    )
            },
            set: { updated in
                guard let index = report?.changes.firstIndex(where: { $0.id == id }) else { return }
                report?.changes[index] = updated
                report?.changes[index].conflict = nil
            }
        )
    }

    private func setAllChangesIncluded(_ included: Bool) {
        guard var report else { return }
        for index in report.changes.indices { report.changes[index].isIncluded = included }
        self.report = report
    }

    @discardableResult
    private func recheckIncludedChanges(showErrors: Bool) -> RevisionChangeSet? {
        guard var report else { return nil }
        let set = report.changeSet(including: enabledStages)
        guard set.hasChanges else {
            if showErrors { errorMessage = SystemicRevisionError.noConcreteChanges.localizedDescription }
            return nil
        }
        let checked = store.validateRevisionChangeSet(set)
        report.mergeValidation(checked)
        self.report = report
        if checked.hasConflicts {
            if showErrors {
                errorMessage = "One or more included passages changed, occur more than once, or overlap another proposal. Review the marked cards; Kistulentz has not changed any file."
            }
            return nil
        }
        return checked
    }

    private func prepareApply() {
        guard let checked = recheckIncludedChanges(showErrors: true) else { return }
        pendingChangeSet = checked
        showingApplyConfirmation = true
    }

    private func applyPendingChanges() {
        guard let pendingChangeSet else { return }
        if store.applyRevisionChangeSet(pendingChangeSet) {
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? "Kistulentz left every file unchanged."
        }
        self.pendingChangeSet = nil
    }

    private func emptyReportDescription(_ report: ProjectPolishReport) -> String {
        if report.wasCancelled {
            return "No completed document produced a safe correction before the scan stopped."
        }
        if !report.failures.isEmpty {
            return "Kistulentz continued past \(report.failures.count) failed document\(report.failures.count == 1 ? "" : "s"), but found no safe automatic correction in the remaining files."
        }
        return "The local spelling, grammar, readability, and learned-style checks found nothing they could change without introducing a new rule violation."
    }
}

private struct ProjectPolishChangeRow: View {
    @Binding var change: ProjectPolishChange

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $change.isIncluded) {
                HStack {
                    Text(change.chapterTitle).font(.headline)
                    Text(change.chapterPath).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(change.categoryTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                GroupBox("Before — exact manuscript passage") {
                    ScrollView {
                        Text(change.originalText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 84, maxHeight: 170)
                }
                GroupBox("After — editable proposal") {
                    TextEditor(text: $change.replacementText)
                        .frame(minHeight: 84, maxHeight: 170)
                }
            }
            Text(change.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let conflict = change.conflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 7)
    }
}
