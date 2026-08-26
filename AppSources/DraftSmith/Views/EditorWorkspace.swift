import SwiftUI
import UniformTypeIdentifiers

private enum ProjectFolderAction {
    case createInParent
    case openExisting
}

private struct PendingProjectConfiguration: Identifiable {
    enum Mode {
        case createInParent
        case prepareExisting
    }

    let id = UUID()
    let url: URL
    let initialName: String
    let mode: Mode
}

struct EditorWorkspace: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var referenceLibrary: ReferenceLibraryStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @StateObject private var viewModel = EditorViewModel()
    @StateObject private var undoCoordinator = DocumentUndoCoordinator()
    @StateObject private var projectStore = WritingProjectStore()
    @State private var showingReplaceConfirmation = false
    @State private var pendingApplyAllPlan: SuggestionApplicationPlan?
    @State private var showingReferenceImporter = false
    @State private var showingReferenceLibrary = false
    @State private var selectedLibraryReferences: Set<String> = []
    @State private var isWriteMode = false
    @State private var showingProjectFolderImporter = false
    @State private var projectFolderAction: ProjectFolderAction = .openExisting
    @State private var pendingProjectConfiguration: PendingProjectConfiguration?
    @State private var showingNewChapter = false
    @State private var showingStyleEditor = false
    @State private var showingRevisionHistory = false
    @State private var showingNamedSnapshot = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var pendingAIRequest: AIRequestPreview?
    @State private var showingToneRequest = false

    private let epubType = UTType(importedAs: "org.idpf.epub-container")

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if isWriteMode {
                MarkdownTextView(
                    text: activeTextBinding,
                    selection: $editorSelection,
                    issues: [],
                    focusRequest: viewModel.focusRequest
                )
                .frame(minWidth: 600)
            } else {
                HSplitView {
                    if projectStore.isOpen {
                        ProjectSidebar(
                            store: projectStore,
                            onSelectSearchResult: selectSearchResult,
                            onNewChapter: { showingNewChapter = true },
                            onEditStyle: { showingStyleEditor = true },
                            onShowHistory: { showingRevisionHistory = true },
                            onCreateSnapshot: { showingNamedSnapshot = true },
                            onCloseProject: closeProject
                        )
                        .frame(minWidth: 205, idealWidth: 225, maxWidth: 275)
                    }

                    ReadabilitySidebar(
                        stats: viewModel.analysis.stats,
                        issues: visibleLocalHighlightIssues,
                        targetGrade: settings.targetGrade,
                        onSelect: viewModel.focus
                    )
                    .frame(minWidth: 205, idealWidth: 225, maxWidth: 260)

                    MarkdownTextView(
                        text: activeTextBinding,
                        selection: $editorSelection,
                        issues: visibleHighlightIssues,
                        focusRequest: viewModel.focusRequest
                    )
                    .frame(minWidth: 450)

                    ReviewSidebar(
                        issues: viewModel.allIssues,
                        review: viewModel.aiReview,
                        isReviewing: viewModel.isReviewing,
                        provider: settings.provider,
                        hasAPIKey: settings.isProviderReady(settings.provider),
                        reference: viewModel.referenceBook,
                        alignment: viewModel.referenceAlignment,
                        isLoadingReference: viewModel.isLoadingReference,
                        onRunReview: runReview,
                        onOpenSettings: { openSettings() },
                        onChooseReference: { showingReferenceLibrary = true },
                        onRemoveReference: viewModel.clearReference,
                        onSelect: viewModel.focus,
                        onApply: apply,
                        onDecline: decline,
                        onApplyAll: prepareApplyAll,
                        onUsePolishedDraft: { showingReplaceConfirmation = true }
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(projectStore.isOpen ? projectStore.projectName : (fileURL?.lastPathComponent ?? "Untitled.md"))
        .onAppear {
            viewModel.configureDocument(url: activeFileURL, text: activeText)
            viewModel.scheduleAnalysis(
                text: activeText,
                targetGrade: settings.targetGrade,
                immediately: true
            )
        }
        .onChange(of: document.text) { _, newValue in
            if !projectStore.isOpen {
                viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
            }
        }
        .onChange(of: projectStore.text) { _, newValue in
            if projectStore.isOpen {
                viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
            }
        }
        .onChange(of: projectStore.selectedFileURL) { _, newValue in
            guard projectStore.isOpen else { return }
            editorSelection = NSRange(location: 0, length: 0)
            undoManager?.removeAllActions()
            viewModel.clearAIReview()
            viewModel.configureDocument(url: newValue, text: projectStore.text)
            viewModel.scheduleAnalysis(
                text: projectStore.text,
                targetGrade: settings.targetGrade,
                immediately: true
            )
        }
        .onChange(of: fileURL) { _, newValue in
            if !projectStore.isOpen {
                viewModel.configureDocument(url: newValue, text: document.text)
            }
        }
        .onChange(of: settings.targetGrade) { _, newValue in
            viewModel.scheduleAnalysis(text: activeText, targetGrade: newValue, immediately: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .runAIReview)) { _ in
            runReview()
        }
        .fileImporter(
            isPresented: $showingReferenceImporter,
            allowedContentTypes: [epubType],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.importReference(from: url, draft: activeText)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingReferenceLibrary) {
            ReferenceLibraryView(selectedChoiceIDs: $selectedLibraryReferences) { reference in
                viewModel.useReference(reference, draft: activeText)
            }
            .environmentObject(referenceLibrary)
            .environmentObject(settings)
        }
        .fileImporter(
            isPresented: $showingProjectFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleProjectFolderResult(result)
        }
        .sheet(item: $pendingProjectConfiguration) { configuration in
            ProjectConfigurationSheet(
                title: configuration.mode == .createInParent ? "New Kistulentz Project" : "Set Up Project Folder",
                initialName: configuration.initialName,
                allowsNameEditing: configuration.mode == .createInParent
            ) { name, kind in
                configureProject(configuration, name: name, kind: kind)
            }
        }
        .sheet(isPresented: $showingNewChapter) {
            NewChapterSheet { projectStore.createChapter(named: $0) }
        }
        .sheet(isPresented: $showingStyleEditor) {
            ProjectStyleEditorView(store: projectStore)
        }
        .sheet(isPresented: $showingRevisionHistory) {
            RevisionHistoryView(store: projectStore)
                .onDisappear { undoManager?.removeAllActions() }
        }
        .sheet(isPresented: $showingNamedSnapshot) {
            NamedSnapshotSheet(chapterTitle: projectStore.selectedChapterTitle) { name in
                projectStore.createSnapshot(name: name, reason: "Named snapshot")
            }
        }
        .sheet(item: $pendingAIRequest) { preview in
            AIRequestPreviewView(preview: preview) { confirmed in
                pendingAIRequest = nil
                executeAIRequest(confirmed)
            }
        }
        .sheet(isPresented: $showingToneRequest) {
            ToneRequestView { tone in
                showingToneRequest = false
                Task { @MainActor in
                    await Task.yield()
                    prepareRewrite(SelectionRewriteGoal(kind: .adjustTone, requestedTone: tone))
                }
            }
        }
        .sheet(item: $viewModel.rewritePresentation) { presentation in
            SelectionRewriteResultView(presentation: presentation) { alternative in
                applyRewrite(alternative, presentation: presentation)
            }
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { viewModel.errorMessage != nil || projectStore.errorMessage != nil },
            set: {
                if !$0 {
                    viewModel.errorMessage = nil
                    projectStore.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? projectStore.errorMessage ?? "")
        }
        .confirmationDialog(
            "Replace this document with the polished draft?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Document", role: .destructive) {
                if let polished = viewModel.aiReview?.polishedText {
                    projectStore.prepareForProgrammaticEdit(reason: "Before polished draft")
                    undoCoordinator.replaceText(
                        with: polished,
                        binding: activeTextBinding,
                        undoManager: undoManager,
                        actionName: "Use Polished Draft"
                    )
                    viewModel.clearAIReview()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can use Undo to restore the current version.")
        }
        .confirmationDialog(
            "Apply all safe suggestions?",
            isPresented: Binding(
                get: { pendingApplyAllPlan != nil },
                set: { if !$0 { pendingApplyAllPlan = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let plan = pendingApplyAllPlan {
                Button(applyAllButtonTitle(for: plan)) {
                    applyAll(plan)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingApplyAllPlan = nil
            }
        } message: {
            if let plan = pendingApplyAllPlan {
                Text(applyAllMessage(for: plan))
            }
        }
    }

    private var activeText: String {
        projectStore.isOpen ? projectStore.text : document.text
    }

    private var activeTextBinding: Binding<String> {
        if projectStore.isOpen {
            return Binding(
                get: { projectStore.text },
                set: { projectStore.updateText($0) }
            )
        }
        return $document.text
    }

    private var activeFileURL: URL? {
        projectStore.isOpen ? projectStore.selectedFileURL : fileURL
    }

    private var visibleHighlightIssues: [WritingIssue] {
        viewModel.allIssues.filter { settings.isHighlightVisible($0.category) }
    }

    private var visibleLocalHighlightIssues: [WritingIssue] {
        viewModel.visibleLocalIssues.filter { settings.isHighlightVisible($0.category) }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor)
                        .frame(width: 29, height: 29)
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Kistulentz")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }

            Divider().frame(height: 20)

            Menu {
                Button {
                    projectFolderAction = .createInParent
                    showingProjectFolderImporter = true
                } label: {
                    Label("New Project…", systemImage: "folder.badge.plus")
                }
                Button {
                    projectFolderAction = .openExisting
                    showingProjectFolderImporter = true
                } label: {
                    Label("Open Project…", systemImage: "folder")
                }

                if projectStore.isOpen {
                    Divider()
                    Button("New Chapter…") { showingNewChapter = true }
                    Button("Edit Kistulentz Style…") { showingStyleEditor = true }
                    Button("Create Snapshot…") { showingNamedSnapshot = true }
                    Button("Revision History…") { showingRevisionHistory = true }
                    Divider()
                    Button("Close Project", action: closeProject)
                }
            } label: {
                Image(systemName: projectStore.isOpen ? "folder.fill" : "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(projectStore.isOpen ? projectStore.projectName : "Projects")

            VStack(alignment: .leading, spacing: 1) {
                Text(activeFileURL?.lastPathComponent ?? "Untitled.md")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(projectStore.isOpen
                    ? "\(projectStore.projectName) · \(projectStore.projectKind?.title ?? "Project")"
                    : "Markdown document")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    isWriteMode.toggle()
                } label: {
                    Label(isWriteMode ? "Exit Write Mode" : "Enter Write Mode", systemImage: isWriteMode ? "sidebar.left" : "text.page")
                }
                Divider()
                Text("Visible highlights")
                ForEach(IssueCategory.allCases) { category in
                    Button {
                        settings.toggleHighlight(category)
                    } label: {
                        if settings.isHighlightVisible(category) {
                            Label(category.title, systemImage: "checkmark")
                        } else {
                            Text(category.title)
                        }
                    }
                }
            } label: {
                Image(systemName: isWriteMode ? "text.page.fill" : "highlighter")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(isWriteMode ? "Exit Write Mode" : "Writing view and highlights")

            Menu {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        settings.provider = provider
                    } label: {
                        if provider == settings.provider {
                            Label(provider.title, systemImage: "checkmark")
                        } else {
                            Text(provider.title)
                        }
                    }
                }
            } label: {
                Label(settings.provider.title, systemImage: "sparkles")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(SelectionRewriteKind.allCases) { kind in
                    Button {
                        if kind == .adjustTone {
                            showingToneRequest = true
                        } else {
                            prepareRewrite(SelectionRewriteGoal(kind: kind, requestedTone: nil))
                        }
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                    .disabled(kind == .matchReferences && viewModel.referenceBook == nil)
                }
            } label: {
                if viewModel.isRewriting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Rewrite", systemImage: "text.badge.star")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(selectedPassage == nil || viewModel.isRewriting)
            .help(selectedPassage == nil ? "Select a passage to rewrite" : "Rewrite the selected passage")

            Menu {
                ForEach([5, 6, 7, 8, 9, 10, 11, 12], id: \.self) { grade in
                    Button("Grade \(grade)") { settings.targetGrade = grade }
                }
            } label: {
                Label("Grade \(settings.targetGrade)", systemImage: "target")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button {
                    showingReferenceLibrary = true
                } label: {
                    Label("Reference Library…", systemImage: "books.vertical.fill")
                }
                Button {
                    showingReferenceImporter = true
                } label: {
                    Label("Quick EPUB Reference…", systemImage: "book.closed")
                }
            } label: {
                if viewModel.isLoadingReference {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        viewModel.referenceBook?.title ?? "Reference",
                        systemImage: viewModel.referenceBook == nil ? "books.vertical" : "books.vertical.fill"
                    )
                    .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(viewModel.isLoadingReference)
            .frame(maxWidth: 170)
            .help("Choose one or more writing references")

            Button(action: runReview) {
                if viewModel.isReviewing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Polish", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isReviewing)
            .help("Review with \(settings.provider.title) (⇧⌘R)")
        }
        .padding(.horizontal, 16)
        .frame(height: 55)
    }

    private func runReview() {
        guard validateSelectedProvider() else { return }
        let style = projectStore.isOpen ? projectStore.styleText : nil
        let reference = viewModel.referenceBook.map {
            WritingAIService.referenceContext($0, relevantTo: activeText)
        }
        pendingAIRequest = AIRequestPreview(
            purpose: .polish(targetGrade: settings.targetGrade),
            provider: settings.provider,
            model: settings.model(for: settings.provider),
            primaryLabel: "Markdown draft",
            primaryText: activeText,
            styleGuide: style,
            includesStyleGuide: style?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            referenceContext: reference,
            includesReferenceContext: reference != nil,
            sourceRange: nil,
            sourceText: activeText
        )
    }

    private var selectedPassage: (range: NSRange, text: String)? {
        let source = activeText as NSString
        guard editorSelection.location != NSNotFound,
              editorSelection.length > 0,
              NSMaxRange(editorSelection) <= source.length else { return nil }
        return (editorSelection, source.substring(with: editorSelection))
    }

    private func prepareRewrite(_ goal: SelectionRewriteGoal) {
        guard let selectedPassage else {
            viewModel.errorMessage = "Select a passage before choosing a rewrite."
            return
        }
        guard validateSelectedProvider() else { return }
        if goal.kind == .matchReferences, viewModel.referenceBook == nil {
            viewModel.errorMessage = "Choose at least one reference before matching its craft profile."
            return
        }

        let style = projectStore.isOpen ? projectStore.styleText : nil
        let reference = viewModel.referenceBook.map {
            WritingAIService.referenceContext($0, relevantTo: selectedPassage.text, maxCharacters: 16_000)
        }
        pendingAIRequest = AIRequestPreview(
            purpose: .selectionRewrite(goal: goal, targetGrade: settings.targetGrade),
            provider: settings.provider,
            model: settings.model(for: settings.provider),
            primaryLabel: "Selected Markdown",
            primaryText: selectedPassage.text,
            styleGuide: style,
            includesStyleGuide: style?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            referenceContext: reference,
            includesReferenceContext: reference != nil,
            sourceRange: selectedPassage.range,
            sourceText: selectedPassage.text
        )
    }

    private func validateSelectedProvider() -> Bool {
        let provider = settings.provider
        guard settings.isProviderReady(provider) else {
            viewModel.errorMessage = provider.requiresAPIKey
                ? "Add your \(provider.title) API key and choose a model in Settings first."
                : "Open Settings, detect the Ollama models already on this Mac, and choose one first."
            return false
        }
        return true
    }

    private func executeAIRequest(_ request: AIRequestPreview) {
        switch request.purpose {
        case .polish:
            viewModel.runAIReview(request: request, matching: activeText, settings: settings)
        case .selectionRewrite:
            viewModel.runSelectionRewrite(request: request, settings: settings)
        case .referenceDeepening:
            break
        }
    }

    private func applyRewrite(
        _ alternative: RewriteAlternative,
        presentation: SelectionRewritePresentation
    ) {
        guard let result = SelectionReplacementPlanner.replace(
            in: activeText,
            range: presentation.sourceRange,
            expected: presentation.sourceText,
            with: alternative.text
        ) else {
            viewModel.errorMessage = "That passage changed after the alternatives were created. Select it again and rerun the rewrite."
            viewModel.rewritePresentation = nil
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before selection rewrite")
        undoCoordinator.replaceText(
            with: result,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: presentation.goal.title
        )
        let replacementRange = NSRange(
            location: presentation.sourceRange.location,
            length: (alternative.text as NSString).length
        )
        editorSelection = replacementRange
        viewModel.focus(on: replacementRange)
        viewModel.rewritePresentation = nil
    }

    private func apply(_ issue: WritingIssue) {
        let plan = SuggestionApplicationPlanner.planSingle(issue: issue, in: activeText)
        guard plan.hasChanges else {
            viewModel.errorMessage = "That passage has changed, so the suggestion can no longer be applied."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before accepting suggestion")
        undoCoordinator.replaceText(
            with: plan.resultText,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: "Accept Suggestion"
        )
        projectStore.recordStyleDecision(action: .accepted, issue: issue)
        viewModel.preserveAIReview(afterAccepting: issue, in: plan.resultText)
    }

    private func decline(_ issue: WritingIssue) {
        if viewModel.decline(issue, in: activeText) {
            projectStore.recordStyleDecision(action: .declined, issue: issue)
        }
    }

    private func prepareApplyAll() {
        let plan = SuggestionApplicationPlanner.plan(issues: viewModel.allIssues, in: activeText)
        guard plan.hasChanges else {
            viewModel.errorMessage = plan.conflictCount > 0 || plan.staleCount > 0
                ? "The available replacements overlap or no longer match this draft. Apply them one at a time."
                : "No current suggestions include a concrete replacement."
            return
        }
        pendingApplyAllPlan = plan
    }

    private func applyAll(_ plan: SuggestionApplicationPlan) {
        let appliedIDs = Set(plan.appliedIssueIDs)
        let appliedIssues = viewModel.allIssues.filter { appliedIDs.contains($0.id) }
        projectStore.prepareForProgrammaticEdit(reason: "Before applying all suggestions")
        undoCoordinator.replaceText(
            with: plan.resultText,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: "Apply All Suggestions"
        )
        for issue in appliedIssues {
            projectStore.recordStyleDecision(action: .accepted, issue: issue)
        }
        viewModel.clearAIReview()
        pendingApplyAllPlan = nil
    }

    private func handleProjectFolderResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch projectFolderAction {
            case .createInParent:
                pendingProjectConfiguration = PendingProjectConfiguration(
                    url: url,
                    initialName: "Untitled Project",
                    mode: .createInParent
                )
            case .openExisting:
                if WritingProjectDisk.hasManifest(at: url) {
                    do {
                        try projectStore.openProject(at: url)
                        activateProject()
                    } catch {
                        projectStore.errorMessage = error.localizedDescription
                    }
                } else {
                    pendingProjectConfiguration = PendingProjectConfiguration(
                        url: url,
                        initialName: url.lastPathComponent,
                        mode: .prepareExisting
                    )
                }
            }
        case .failure(let error):
            projectStore.errorMessage = error.localizedDescription
        }
    }

    private func configureProject(
        _ configuration: PendingProjectConfiguration,
        name: String,
        kind: WritingProjectKind
    ) {
        do {
            switch configuration.mode {
            case .createInParent:
                try projectStore.createProject(in: configuration.url, name: name, kind: kind)
            case .prepareExisting:
                try projectStore.prepareAndOpenProject(at: configuration.url, name: name, kind: kind)
            }
            activateProject()
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }

    private func activateProject() {
        undoManager?.removeAllActions()
        viewModel.clearAIReview()
        viewModel.configureDocument(url: projectStore.selectedFileURL, text: projectStore.text)
        viewModel.scheduleAnalysis(
            text: projectStore.text,
            targetGrade: settings.targetGrade,
            immediately: true
        )
    }

    private func closeProject() {
        projectStore.closeProject()
        undoManager?.removeAllActions()
        viewModel.clearAIReview()
        viewModel.configureDocument(url: fileURL, text: document.text)
        viewModel.scheduleAnalysis(
            text: document.text,
            targetGrade: settings.targetGrade,
            immediately: true
        )
    }

    private func selectSearchResult(_ result: ProjectSearchResult) {
        projectStore.selectChapter(result.chapterPath)
        Task { @MainActor in
            await Task.yield()
            viewModel.focus(on: result.range)
        }
    }

    private func applyAllButtonTitle(for plan: SuggestionApplicationPlan) -> String {
        "Apply \(plan.appliedCount) \(plan.appliedCount == 1 ? "Change" : "Changes")"
    }

    private func applyAllMessage(for plan: SuggestionApplicationPlan) -> String {
        var parts = [
            "Kistulentz will apply \(plan.appliedCount) concrete, non-overlapping \(plan.appliedCount == 1 ? "change" : "changes") as one edit."
        ]
        if plan.conflictCount > 0 {
            parts.append("\(plan.conflictCount) overlapping \(plan.conflictCount == 1 ? "suggestion" : "suggestions") will be skipped.")
        }
        if plan.staleCount > 0 {
            parts.append("\(plan.staleCount) changed \(plan.staleCount == 1 ? "passage" : "passages") will be skipped.")
        }
        if plan.advisoryCount > 0 {
            parts.append("Advisory highlights without replacement text will remain.")
        }
        parts.append("You can undo the entire edit with Command-Z.")
        return parts.joined(separator: " ")
    }
}

private struct ReadabilitySidebar: View {
    let stats: WritingStats
    let issues: [WritingIssue]
    let targetGrade: Int
    let onSelect: (WritingIssue) -> Void

    private let categories: [IssueCategory] = [
        .adverb, .passiveVoice, .complexPhrase, .hardSentence, .veryHardSentence
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("READABILITY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    Text("Make every sentence earn its place.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.14), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(stats.readabilityScore) / 100)
                            .stroke(
                                stats.gradeLevel <= Double(targetGrade) + 1 ? Color.green : Color.orange,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: -1) {
                            Text(stats.gradeLevel, format: .number.precision(.fractionLength(1)))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("GRADE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 82, height: 82)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(stats.gradeLevel <= Double(targetGrade) + 1 ? "On target" : "Revise for clarity")
                            .font(.headline)
                        Text("Goal: grade \(targetGrade)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Score \(stats.readabilityScore)/100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 0) {
                    StatCell(value: "\(stats.words)", label: "WORDS")
                    StatCell(value: "\(stats.sentences)", label: "SENTENCES")
                    StatCell(value: "\(stats.readingMinutes)m", label: "READ")
                }
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text("HIGHLIGHTS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    ForEach(categories) { category in
                        let matches = issues.filter { $0.category == category }
                        Button {
                            if let first = matches.first { onSelect(first) }
                        } label: {
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(category.color)
                                    .frame(width: 11, height: 11)
                                Text(category.shortLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(matches.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(matches.isEmpty)
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.68))
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReviewSidebar: View {
    let issues: [WritingIssue]
    let review: AIReview?
    let isReviewing: Bool
    let provider: AIProvider
    let hasAPIKey: Bool
    let reference: EPUBReference?
    let alignment: ReferenceAlignment
    let isLoadingReference: Bool
    let onRunReview: () -> Void
    let onOpenSettings: () -> Void
    let onChooseReference: () -> Void
    let onRemoveReference: () -> Void
    let onSelect: (WritingIssue) -> Void
    let onApply: (WritingIssue) -> Void
    let onDecline: (WritingIssue) -> Void
    let onApplyAll: () -> Void
    let onUsePolishedDraft: () -> Void

    private var hasApplicableSuggestions: Bool {
        issues.contains { $0.replacement != nil && $0.replacement != $0.excerpt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions")
                        .font(.headline)
                    Text("\(issues.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasApplicableSuggestions {
                    Button("Apply All", action: onApplyAll)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Apply concrete, non-overlapping changes")
                }
                Button(action: onRunReview) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isReviewing || !hasAPIKey)
                .help("Run a new AI review")
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ReferenceCard(
                        reference: reference,
                        alignment: alignment,
                        isLoading: isLoadingReference,
                        onChoose: onChooseReference,
                        onRemove: onRemoveReference
                    )

                    if isReviewing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("\(provider.title) is polishing your draft…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    } else if !hasAPIKey {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                provider.requiresAPIKey ? "Connect \(provider.title)" : "Choose a local model",
                                systemImage: provider.requiresAPIKey ? "key" : "desktopcomputer"
                            )
                                .font(.caption.weight(.semibold))
                            Text(provider.requiresAPIKey
                                ? "Local readability and EPUB comparisons work without a key. Connect for grammar corrections and deeper rewrites."
                                : "Kistulentz found no selected Ollama model. Open Settings to detect models already installed on this Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Settings", action: onOpenSettings)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(12)
                        .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))
                    } else if let review {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("AI review", systemImage: "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                                Text("Grade \(review.gradeEstimate, format: .number.precision(.fractionLength(1)))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(review.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Use polished draft", action: onUsePolishedDraft)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    } else {
                        Button(action: onRunReview) {
                            Label("Polish with \(provider.title)", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 4)
                    }

                    ForEach(issues) { issue in
                        IssueCard(
                            issue: issue,
                            onSelect: onSelect,
                            onApply: onApply,
                            onDecline: onDecline
                        )
                    }

                    if issues.isEmpty {
                        ContentUnavailableView(
                            "No local flags",
                            systemImage: "checkmark.circle",
                            description: Text(hasAPIKey
                                ? "Run an AI review for deeper grammar and rewriting suggestions."
                                : (provider.requiresAPIKey
                                    ? "Local analysis is clear. Add an API key only when you want deeper AI suggestions."
                                    : "Local analysis is clear. Choose an installed Ollama model for deeper local suggestions."))
                        )
                        .padding(.top, 12)
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }
}

private struct ReferenceCard: View {
    let reference: EPUBReference?
    let alignment: ReferenceAlignment
    let isLoading: Bool
    let onChoose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyzing EPUB locally…")
                            .font(.callout.weight(.semibold))
                        Text("Finding voice, tone, characters, and tempo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let reference {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                        if let author = reference.author {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(alignment.score)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("MATCH")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { profileBadges(reference.profile) }
                    VStack(alignment: .leading, spacing: 5) { profileBadges(reference.profile) }
                }

                ForEach(Array(alignment.notes.prefix(3))) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: note.isAligned ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(note.isAligned ? Color.green : Color.orange)
                        Text("\(note.title): \(note.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !reference.profile.characters.isEmpty {
                    Text("Characters: \(reference.profile.characters.prefix(8).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(reference.sourceCount == 1
                    ? "The reference stays local. Selected excerpts are sent only when you run Polish."
                    : "\(reference.sourceCount) books are combined locally. Selected excerpts are sent only when you run Polish.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Choose References", action: onChoose)
                        .controlSize(.small)
                    Button("Remove", role: .destructive, action: onRemove)
                        .controlSize(.small)
                }
            } else {
                Label("Writing references", systemImage: "books.vertical")
                    .font(.callout.weight(.semibold))
                Text("Compare this draft with a book’s voice, vocabulary, tone, characters, continuity, and tempo. The first analysis runs entirely on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Reference Library", action: onChoose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.purple.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func profileBadges(_ profile: ReferenceProfile) -> some View {
        ReferenceBadge(text: profile.voice.capitalized)
        ReferenceBadge(text: profile.tempo.capitalized)
        ReferenceBadge(text: "Grade \(profile.gradeLevel.formatted(.number.precision(.fractionLength(1))))")
    }
}

private struct ReferenceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.background.opacity(0.75), in: Capsule())
    }
}

private struct IssueCard: View {
    let issue: WritingIssue
    let onSelect: (WritingIssue) -> Void
    let onApply: (WritingIssue) -> Void
    let onDecline: (WritingIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onSelect(issue)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Circle()
                            .fill(issue.category.color)
                            .frame(width: 8, height: 8)
                        Text(issue.category.title)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if issue.source == .ai {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(issue.excerpt)
                        .font(.system(size: 13, design: .rounded))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let replacement = issue.replacement {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(replacement)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(3)
                }
            }

            HStack(spacing: 7) {
                Spacer()
                Button("Decline") { onDecline(issue) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                if issue.replacement != nil {
                    Button("Accept") { onApply(issue) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
            }
        }
        .padding(11)
        .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(issue.category.color)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
    }
}
