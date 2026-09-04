import AppKit
import SwiftUI

private enum ManuscriptInsightsTab: String, CaseIterable, Identifiable {
    case report = "Report"
    case bible = "Bible"
    case beta = "Beta Readers"

    var id: String { rawValue }
}

struct ManuscriptInsightsView: View {
    @ObservedObject var store: WritingProjectStore
    @ObservedObject var betaReadersStore: BetaReadersStore
    @ObservedObject var styleLearningStore: StyleLearningStore
    let selectedPassage: String?
    let reference: EPUBReference?
    let onShowRevisionHistory: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var tab: ManuscriptInsightsTab = .report
    @State private var selectedReaderID = BetaReaderProfile.builtIns[0].id
    @State private var betaScope: BetaReaderScope = .chapter
    @State private var feedback: [BetaReaderFeedback] = []
    @State private var pendingAIRequest: AIRequestPreview?
    @State private var pendingBetaReader: BetaReaderProfile?
    @State private var pendingBetaScope: BetaReaderScope?
    @State private var isRunningLocalBeta = false
    @State private var isRunningAI = false
    @State private var showingCustomReaderEditor = false
    @State private var editingReader: BetaReaderProfile?
    @State private var errorMessage: String?

    private var allReaders: [BetaReaderProfile] {
        BetaReaderProfile.builtIns + betaReadersStore.customBetaReaders
    }

    private var selectedReader: BetaReaderProfile {
        allReaders.first { $0.id == selectedReaderID } ?? BetaReaderProfile.builtIns[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manuscript Insights").font(.title2.weight(.semibold))
                    Text("Local-first analysis for \(store.projectName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isAnalyzingManuscript {
                    ProgressView().controlSize(.small)
                    Text("Updating locally…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
            }
            .padding(16)

            Picker("View", selection: $tab) {
                ForEach(ManuscriptInsightsTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            switch tab {
            case .report: reportView
            case .bible: bibleView
            case .beta: betaReaderView
            }
        }
        .frame(minWidth: 1_020, minHeight: 700)
        .onAppear { store.attachUndoManager(undoManager) }
        .onDisappear { store.saveBibleNow() }
        .sheet(item: $pendingAIRequest) { preview in
            AIRequestPreviewView(preview: preview) { confirmed in
                pendingAIRequest = nil
                runAI(confirmed)
            }
        }
        .sheet(isPresented: $showingCustomReaderEditor) {
            CustomBetaReaderEditor(reader: editingReader) { reader in
                if editingReader == nil {
                    betaReadersStore.addCustomBetaReader(name: reader.name, focus: reader.focus, audience: reader.audience)
                    selectedReaderID = betaReadersStore.customBetaReaders.last?.id ?? selectedReaderID
                } else {
                    betaReadersStore.updateCustomBetaReader(reader)
                    selectedReaderID = reader.id
                }
            }
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var reportView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Automatic local manuscript report", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Show Markdown File") { reveal(store.reportFileURL) }
                Button(action: prepareReportDeepening) {
                    if isRunningAI {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Deepen w/ AI", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningAI || store.isAnalyzingManuscript)
            }
            .padding(14)
            Divider()
            ScrollView {
                Text(store.manuscriptReportText.isEmpty ? "The local report is being prepared." : store.manuscriptReportText)
                    .font(.system(size: 13.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var bibleView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Editable project Bible", systemImage: "book.pages")
                        .font(.headline)
                    Text("Generated facts update locally; your corrections and notes are preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if undoManager?.canUndo == true {
                    Button("Undo Last Change") { undoManager?.undo() }
                }
                Button("Revision History") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onShowRevisionHistory()
                    }
                }
                Button("Show Markdown File") { reveal(store.bibleFileURL) }
                Button(action: prepareBibleDeepening) {
                    if isRunningAI {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Deepen w/ AI", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningAI || store.isAnalyzingManuscript)
            }
            .padding(14)

            if let update = store.lastBibleUpdate {
                DisclosureGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(update.diff.prefix(160))) { line in
                                Text("\(diffSymbol(line.kind)) \(line.text)")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(diffColor(line.kind))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                } label: {
                    Text(update.summary)
                        .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider()
            TextEditor(text: Binding(
                get: { store.bibleText },
                set: { store.updateBibleText($0) }
            ))
            .font(.system(size: 13.5, design: .monospaced))
            .padding(10)
        }
    }

    private var betaReaderView: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedReaderID) {
                    Section("Built-in") {
                        ForEach(BetaReaderProfile.builtIns) { reader in
                            readerLabel(reader).tag(reader.id)
                        }
                    }
                    if !betaReadersStore.customBetaReaders.isEmpty {
                        Section("Custom") {
                            ForEach(betaReadersStore.customBetaReaders) { reader in
                                readerLabel(reader).tag(reader.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                HStack {
                    Button {
                        editingReader = nil
                        showingCustomReaderEditor = true
                    } label: {
                        Label("Reader", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    if !selectedReader.isBuiltIn {
                        Button {
                            editingReader = selectedReader
                            showingCustomReaderEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            let reader = selectedReader
                            selectedReaderID = BetaReaderProfile.builtIns[0].id
                            betaReadersStore.removeCustomBetaReader(reader)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
            }
            .frame(minWidth: 230, idealWidth: 250, maxWidth: 290)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(selectedReader.name).font(.headline)
                            Text(selectedReader.audience.title)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(selectedReader.focus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Scope", selection: $betaScope) {
                        ForEach(BetaReaderScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .frame(width: 190)
                    Button(action: runLocalBeta) {
                        if isRunningLocalBeta {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Run Locally", systemImage: "macbook")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningLocalBeta || !scopeIsAvailable)
                    Button(action: prepareAIBeta) {
                        Label("Deepen w/ AI", systemImage: "sparkles")
                    }
                    .disabled(isRunningAI || !scopeIsAvailable)
                }
                .padding(14)
                Divider()

                if feedback.isEmpty {
                    ContentUnavailableView(
                        "No beta feedback this session",
                        systemImage: "person.2.wave.2",
                        description: Text("Choose a reader and scope. Local feedback stays on this screen only; custom reader definitions are saved inside the project.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(feedback) { item in
                                BetaFeedbackCard(feedback: item)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(minWidth: 650)
        }
    }

    private var scopeIsAvailable: Bool {
        betaScope != .selection || selectedPassage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func readerLabel(_ reader: BetaReaderProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reader.name)
            Text(reader.focus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func runLocalBeta() {
        do {
            let documents = try betaReadersStore.documents(for: betaScope, selection: selectedPassage)
            let reader = selectedReader
            let scope = betaScope
            let projectName = store.projectName
            let kind = store.projectKind ?? .fiction
            let targetGrade = settings.targetGrade
            isRunningLocalBeta = true
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    BetaReaderEngine.read(
                        profile: reader,
                        scope: scope,
                        projectName: projectName,
                        kind: kind,
                        documents: documents,
                        targetGrade: targetGrade
                    )
                }.value
                feedback.insert(result, at: 0)
                isRunningLocalBeta = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareReportDeepening() {
        guard validateProvider() else { return }
        do {
            pendingAIRequest = makeAIRequest(
                purpose: .manuscriptReport(kind: store.projectKind ?? .fiction),
                label: "Manuscript report and sampled manuscript",
                primary: try store.manuscriptAIContext()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareBibleDeepening() {
        guard validateProvider() else { return }
        do {
            pendingAIRequest = makeAIRequest(
                purpose: .manuscriptBible(kind: store.projectKind ?? .fiction),
                label: "Project Bible and sampled manuscript",
                primary: try store.manuscriptAIContext()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareAIBeta() {
        guard validateProvider() else { return }
        do {
            let documents = try betaReadersStore.documents(for: betaScope, selection: selectedPassage)
            let context = ManuscriptAnalyzer.context(
                documents: documents,
                report: store.manuscriptReportText,
                bible: store.bibleText
            )
            pendingBetaReader = selectedReader
            pendingBetaScope = betaScope
            pendingAIRequest = makeAIRequest(
                purpose: .betaReader(
                    readerName: selectedReader.name,
                    focus: selectedReader.focus,
                    scope: betaScope,
                    kind: store.projectKind ?? .fiction
                ),
                label: "\(betaScope.title) and project context",
                primary: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeAIRequest(purpose: AIRequestPurpose, label: String, primary: String) -> AIRequestPreview {
        let referenceContext = reference.map {
            WritingAIService.referenceContext($0, relevantTo: primary, maxCharacters: 14_000)
        }
        return AIRequestPreview(
            purpose: purpose,
            provider: settings.provider,
            model: settings.model(for: settings.provider),
            primaryLabel: label,
            primaryText: primary,
            styleGuide: styleLearningStore.styleText,
            includesStyleGuide: !styleLearningStore.styleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            referenceContext: referenceContext,
            includesReferenceContext: referenceContext != nil,
            sourceRange: nil,
            sourceText: nil
        )
    }

    private func runAI(_ request: AIRequestPreview) {
        isRunningAI = true
        Task {
            defer { isRunningAI = false }
            do {
                let service = ManuscriptAIService()
                switch request.purpose {
                case .manuscriptReport:
                    let response = try await service.deepenMarkdown(request: request, apiKey: settings.apiKey(for: request.provider))
                    store.applyAIReport(response, provider: request.provider, model: request.model)
                case .manuscriptBible:
                    let response = try await service.deepenMarkdown(request: request, apiKey: settings.apiKey(for: request.provider))
                    store.applyAIBible(response, provider: request.provider, model: request.model)
                case .betaReader:
                    guard let reader = pendingBetaReader, let scope = pendingBetaScope else { return }
                    let result = try await service.betaRead(
                        request: request,
                        profile: reader,
                        scope: scope,
                        apiKey: settings.apiKey(for: request.provider)
                    )
                    feedback.insert(result, at: 0)
                default:
                    break
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            pendingBetaReader = nil
            pendingBetaScope = nil
        }
    }

    private func validateProvider() -> Bool {
        guard settings.isProviderReady(settings.provider) else {
            errorMessage = settings.provider.requiresAPIKey
                ? "Add your \(settings.provider.title) API key and choose a model in Settings first."
                : "Open Settings, detect the Ollama models already on this Mac, and choose one first."
            return false
        }
        return true
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func diffSymbol(_ kind: RevisionDiffKind) -> String {
        switch kind {
        case .unchanged: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private func diffColor(_ kind: RevisionDiffKind) -> Color {
        switch kind {
        case .unchanged: .secondary
        case .added: .green
        case .removed: .red
        }
    }
}

private struct BetaFeedbackCard: View {
    let feedback: BetaReaderFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedback.reader.name).font(.headline)
                    Text("\(feedback.scope.title) · \(feedback.source.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            Text(feedback.summary).font(.callout)
            Text(feedback.reaction)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            feedbackSection("Strengths", items: feedback.strengths, color: .green)
            feedbackSection("Concerns", items: feedback.concerns, color: .orange)
            feedbackSection("Questions", items: feedback.questions, color: .blue)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
    }

    private func feedbackSection(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(color)
            if items.isEmpty {
                Text("No local signal in this category.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)").font(.callout)
                }
            }
        }
    }

    private var markdown: String {
        var lines = [
            "## \(feedback.reader.name)",
            "",
            "*\(feedback.scope.title) · \(feedback.source.title)*",
            "",
            feedback.summary,
            "",
            feedback.reaction
        ]
        for section in [("Strengths", feedback.strengths), ("Concerns", feedback.concerns), ("Questions", feedback.questions)] {
            lines += ["", "### \(section.0)", ""]
            lines += section.1.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}

private struct CustomBetaReaderEditor: View {
    let reader: BetaReaderProfile?
    let onSave: (BetaReaderProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var focus: String
    @State private var audience: BetaReaderAudience

    init(reader: BetaReaderProfile?, onSave: @escaping (BetaReaderProfile) -> Void) {
        self.reader = reader
        self.onSave = onSave
        _name = State(initialValue: reader?.name ?? "")
        _focus = State(initialValue: reader?.focus ?? "")
        _audience = State(initialValue: reader?.audience ?? .general)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(reader == nil ? "New Custom Beta Reader" : "Edit Custom Beta Reader")
                .font(.headline)
            TextField("Reader name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("What should this reader pay attention to?")
                .font(.caption.weight(.semibold))
            TextEditor(text: $focus)
                .font(.body)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            Picker("Best for", selection: $audience) {
                ForEach(BetaReaderAudience.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(BetaReaderProfile(
                        id: reader?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        focus: focus.trimmingCharacters(in: .whitespacesAndNewlines),
                        audience: audience
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
