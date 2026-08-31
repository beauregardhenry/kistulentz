import AppKit
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
    @EnvironmentObject private var beneparPack: BeneparLanguagePackManager
    @EnvironmentObject private var referenceLibrary: ReferenceLibraryStore
    @EnvironmentObject private var researchLibrary: ResearchLibraryStore
    @EnvironmentObject private var draftRecovery: DraftRecoveryManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = EditorViewModel()
    @StateObject private var undoCoordinator = DocumentUndoCoordinator()
    @StateObject private var projectStore = WritingProjectStore()
    @StateObject private var draftRecoveryCoordinator = DraftRecoveryCoordinator()
    @State private var polishedDraftPlan: PolishedDraftPlan?
    @State private var pendingApplyAllPlan: SuggestionApplicationPlan?
    @State private var showingReferenceImporter = false
    @State private var showingReferenceLibrary = false
    @State private var showingResearchLibrary = false
    @State private var showingProjectResearch = false
    @State private var showingRevisionCenter = false
    @State private var showingProjectPolish = false
    @State private var showingPublishExport = false
    @State private var selectedLibraryReferences: Set<String> = []
    @State private var isWriteMode = false
    @State private var showingProjectFolderImporter = false
    @State private var projectFolderAction: ProjectFolderAction = .openExisting
    @State private var pendingProjectConfiguration: PendingProjectConfiguration?
    @State private var showingNewChapter = false
    @State private var showingStyleEditor = false
    @State private var showingRevisionHistory = false
    @State private var showingManuscriptInsights = false
    @State private var showingProjectOrganization = false
    @State private var showingNamedSnapshot = false
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var pendingAIRequest: AIRequestPreview?
    @State private var showingToneRequest = false
    @State private var pendingDocumentImport: DocumentImportDraft?
    @State private var isImportingDocument = false
    @State private var showingProjectImportAssistant = false
    @State private var showingWelcome = false
    @State private var showingEnglishPackPrompt = false
    @State private var showingDraftRecovery = false
    @State private var didPresentStartup = false

    private let epubType = UTType(importedAs: "org.idpf.epub-container")

    private var editorLayout: some View {
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
                            onShowManuscriptInsights: { showingManuscriptInsights = true },
                            onShowOrganization: { showingProjectOrganization = true },
                            onShowResearch: { showingProjectResearch = true },
                            onShowProjectPolish: { showingProjectPolish = true },
                            onShowRevisionCenter: { showingRevisionCenter = true },
                            onShowPublish: { showingPublishExport = true },
                            onCloseProject: closeProject
                        )
                        .frame(minWidth: 205, idealWidth: 225, maxWidth: 275)
                    }

                    ReadabilitySidebar(
                        stats: viewModel.analysis.stats,
                        issues: visibleLocalHighlightIssues,
                        targetGrade: settings.targetGrade,
                        isUsingBenepar: viewModel.isUsingBenepar,
                        isAnalyzingStructure: viewModel.isAnalyzingStructure,
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
                        blockedAISuggestionCount: viewModel.blockedAISuggestionCount,
                        isReviewing: viewModel.isReviewing,
                        isRewriting: viewModel.isRewriting,
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
                        onRewrite: prepareRewrite,
                        onApplyAll: prepareApplyAll,
                        onReviewPolishedDraft: preparePolishedDraftReview
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                }
            }
        }
    }

    private var lifecycleConfiguredView: some View {
        editorLayout
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(projectStore.isOpen ? projectStore.projectName : (fileURL?.lastPathComponent ?? "Untitled.md"))
        .onAppear {
            projectStore.attachUndoManager(undoManager)
            viewModel.configureDocument(url: activeFileURL, text: activeText)
            configureDraftRecovery()
            viewModel.scheduleAnalysis(
                text: activeText,
                targetGrade: settings.targetGrade,
                immediately: true
            )
            presentStartupIfNeeded()
        }
        .onChange(of: document.text) { _, newValue in
            if !projectStore.isOpen {
                viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
                draftRecoveryCoordinator.schedule(text: newValue)
            }
        }
        .onChange(of: projectStore.text) { _, newValue in
            if projectStore.isOpen {
                viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
                draftRecoveryCoordinator.schedule(text: newValue)
            }
        }
        .onChange(of: projectStore.selectedFileURL) { _, newValue in
            guard projectStore.isOpen else { return }
            editorSelection = NSRange(location: 0, length: 0)
            if !projectStore.preservesUndoAcrossFileRelocation {
                undoManager?.removeAllActions()
            }
            viewModel.clearAIReview()
            viewModel.configureDocument(url: newValue, text: projectStore.text)
            viewModel.scheduleAnalysis(
                text: projectStore.text,
                targetGrade: settings.targetGrade,
                immediately: true
            )
            Task { @MainActor in
                await Task.yield()
                configureDraftRecovery()
            }
        }
        .onChange(of: fileURL) { _, newValue in
            if !projectStore.isOpen {
                viewModel.configureDocument(url: newValue, text: document.text)
                configureDraftRecovery()
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active { draftRecoveryCoordinator.flush() }
        }
        .onChange(of: settings.targetGrade) { _, newValue in
            viewModel.scheduleAnalysis(text: activeText, targetGrade: newValue, immediately: true)
        }
        .onChange(of: beneparPack.isInstalled) { _, isInstalled in
            guard isInstalled else { return }
            viewModel.scheduleAnalysis(
                text: activeText,
                targetGrade: settings.targetGrade,
                immediately: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .runAIReview)) { _ in
            runReview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKistulentzWelcome)) { _ in
            showingWelcome = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDraftRecovery)) { _ in
            draftRecovery.reloadPendingEntries()
            showingDraftRecovery = true
        }
        .onDisappear {
            draftRecoveryCoordinator.flush()
            if projectStore.isOpen {
                projectStore.saveNow()
                if !projectStore.hasUnsavedChapterChanges {
                    draftRecoveryCoordinator.close()
                }
            } else {
                draftRecoveryCoordinator.close()
            }
        }
    }

    private var libraryConfiguredView: some View {
        lifecycleConfiguredView.fileImporter(
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
        .sheet(isPresented: $showingResearchLibrary) {
            ResearchLibraryView()
                .environmentObject(researchLibrary)
        }
        .sheet(isPresented: $showingProjectResearch) {
            ProjectResearchView(
                projectStore: projectStore,
                selectionText: selectedPassage?.text,
                onInsertCitation: insertCitation
            )
            .environmentObject(researchLibrary)
        }
        .sheet(isPresented: $showingRevisionCenter) {
            SystemicRevisionCenterView(store: projectStore, onNavigate: navigateToRevisionFinding)
                .environmentObject(settings)
                .environmentObject(researchLibrary)
        }
        .sheet(isPresented: $showingProjectPolish) {
            ProjectPolishView(store: projectStore)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingPublishExport) {
            PublishExportView(store: projectStore)
                .environmentObject(researchLibrary)
        }
    }

    private var importConfiguredView: some View {
        libraryConfiguredView.sheet(item: $pendingDocumentImport) { draft in
            DocumentImportPreviewView(
                draft: draft,
                onCancel: { pendingDocumentImport = nil },
                onSave: { decisions in saveImportedDocument(draft, decisions: decisions) }
            )
        }
        .sheet(isPresented: $showingProjectImportAssistant) {
            ProjectImportAssistantView(
                currentProjectName: projectStore.isOpen ? projectStore.projectName : nil,
                addToCurrentProject: projectStore.isOpen ? { conversions, decisions in
                    try projectStore.importProjectDocuments(conversions, decisions: decisions)
                } : nil,
                onComplete: completeProjectImport,
                onCancel: { showingProjectImportAssistant = false }
            )
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeView(
                onCreateProject: beginProjectFromWelcome,
                onOpenDocument: openDocumentFromWelcome,
                onImportDocuments: beginImportFromWelcome,
                onOpenSample: createSampleProject,
                onContinue: completeWelcome
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingEnglishPackPrompt) {
            EnglishPackPromptView(
                onNotNow: finishEnglishPackPrompt,
                onInstalled: finishEnglishPackPrompt
            )
            .environmentObject(beneparPack)
        }
        .sheet(isPresented: $showingDraftRecovery, onDismiss: presentWelcomeAfterRecovery) {
            DraftRecoveryView(manager: draftRecovery) {
                showingDraftRecovery = false
            }
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
    }

    private var projectConfiguredView: some View {
        importConfiguredView.sheet(isPresented: $showingNewChapter) {
            NewChapterSheet { projectStore.createChapter(named: $0) }
        }
        .sheet(isPresented: $showingStyleEditor) {
            ProjectStyleEditorView(store: projectStore)
        }
        .sheet(isPresented: $showingRevisionHistory) {
            RevisionHistoryView(store: projectStore)
                .onDisappear { undoManager?.removeAllActions() }
        }
        .sheet(isPresented: $showingManuscriptInsights) {
            ManuscriptInsightsView(
                store: projectStore,
                selectedPassage: selectedPassage?.text,
                reference: viewModel.referenceBook,
                onShowRevisionHistory: { showingRevisionHistory = true }
            )
            .environmentObject(settings)
        }
        .sheet(isPresented: $showingProjectOrganization) {
            ProjectOrganizationView(store: projectStore, reference: viewModel.referenceBook)
                .environmentObject(settings)
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
        .sheet(item: $projectStore.recoveryRequest) { request in
            ProjectRecoveryView(
                request: request,
                onRestore: { backup in
                    do {
                        try projectStore.restoreProject(from: backup)
                        activateProject()
                    } catch {
                        projectStore.errorMessage = error.localizedDescription
                    }
                },
                onCancel: projectStore.dismissRecovery
            )
        }
        .sheet(item: $viewModel.rewritePresentation) { presentation in
            SelectionRewriteResultView(presentation: presentation) { alternative in
                applyRewrite(alternative, presentation: presentation)
            }
        }
        .sheet(item: $polishedDraftPlan) { plan in
            PolishedDraftReviewView(
                plan: plan,
                onApplySelected: { applyPolishedChanges($0, from: plan) },
                onReplaceAll: { replaceWithPolishedDraft(from: plan) }
            )
        }
    }

    var body: some View {
        projectConfiguredView.alert("Kistulentz", isPresented: Binding(
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
                    chooseDocumentForImport()
                } label: {
                    Label("Import Document…", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(isImportingDocument)

                Button {
                    showingProjectImportAssistant = true
                } label: {
                    Label("Project Import Assistant…", systemImage: "square.stack.3d.up.badge.a")
                }

                Divider()

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
                    Button("Manuscript Insights…") { showingManuscriptInsights = true }
                    Button("Project Organization…") { showingProjectOrganization = true }
                    Button("Project Research…") { showingProjectResearch = true }
                    Button("Polish Project…") { showingProjectPolish = true }
                    Button("Systemic Revision Center…") { showingRevisionCenter = true }
                    Button("Publish & Export…") { showingPublishExport = true }
                    Divider()
                    Button("Close Project", action: closeProject)
                }
            } label: {
                if isImportingDocument {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: projectStore.isOpen ? "folder.fill" : "folder")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(projectStore.isOpen ? projectStore.projectName : "Projects")
            .accessibilityLabel(projectStore.isOpen ? "Project: \(projectStore.projectName)" : "Projects")

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
            .accessibilityLabel(isWriteMode ? "Exit Write Mode" : "Writing view and highlights")

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
                    showingResearchLibrary = true
                } label: {
                    Label("Research Library…", systemImage: "doc.text.magnifyingglass")
                }
                if projectStore.isOpen {
                    Button {
                        showingProjectResearch = true
                    } label: {
                        Label("Project Research & Citations…", systemImage: "quote.opening")
                    }
                }
                Divider()
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
            .accessibilityIdentifier("ReferenceMenu")

            Button(action: runReview) {
                if viewModel.isReviewing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Polish", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isReviewing)
            .help(settings.isProviderReady(settings.provider)
                ? "Review with \(settings.provider.title) (⇧⌘R)"
                : "Polish locally on this Mac (⇧⌘R)")
        }
        .padding(.horizontal, 16)
        .frame(height: 55)
    }

    private func configureDraftRecovery() {
        draftRecoveryCoordinator.configure(
            title: activeFileURL?.lastPathComponent ?? "Untitled.md",
            fileURL: activeFileURL,
            projectRootURL: projectStore.rootURL,
            text: activeText
        )
    }

    private func presentStartupIfNeeded() {
        guard !didPresentStartup else { return }
        didPresentStartup = true
        if !draftRecovery.pendingEntries.isEmpty {
            showingDraftRecovery = true
        } else {
            presentNextStartupStep()
        }
    }

    private func presentWelcomeAfterRecovery() {
        presentNextStartupStep()
    }

    private func presentNextStartupStep() {
        beneparPack.refresh()
        if !beneparPack.isInstalled, settings.claimEnglishPackPrompt() {
            showingEnglishPackPrompt = true
        } else if !settings.hasCompletedOnboarding {
            showingWelcome = true
        }
    }

    private func finishEnglishPackPrompt() {
        settings.acknowledgeEnglishPackPrompt()
        showingEnglishPackPrompt = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if !settings.hasCompletedOnboarding { showingWelcome = true }
        }
    }

    private func completeWelcome() {
        settings.completeOnboarding()
        showingWelcome = false
    }

    private func beginProjectFromWelcome() {
        completeWelcome()
        projectFolderAction = .createInParent
        showingProjectFolderImporter = true
    }

    private func openDocumentFromWelcome() {
        completeWelcome()
        let panel = NSOpenPanel()
        panel.title = "Open a Markdown Document"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.markdownDocument, .plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImportedMarkdown(url)
    }

    private func beginImportFromWelcome() {
        completeWelcome()
        showingProjectImportAssistant = true
    }

    private func createSampleProject(_ kind: WritingProjectKind) {
        completeWelcome()
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder for the \(kind.title) Sample"
        panel.message = "Kistulentz will create a new editable sample-project folder here without replacing existing files."
        panel.prompt = "Create Sample Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        do {
            let root = try SampleProjectBuilder.create(in: parent, kind: kind)
            try projectStore.openProject(at: root)
            activateProject()
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }

    private func chooseDocumentForImport() {
        let panel = NSOpenPanel()
        panel.title = "Import a Document"
        panel.message = "Choose a plain-text, Word, RTF, RTFD, HTML, or OpenDocument file. Kistulentz will create a separate Markdown copy."
        panel.prompt = "Import"
        panel.allowedContentTypes = DocumentImportFormat.importableContentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImportingDocument = true
        Task { @MainActor in
            do {
                let draft = try await Task.detached(priority: .userInitiated) {
                    try DocumentImportService.load(from: url)
                }.value
                pendingDocumentImport = draft
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
            isImportingDocument = false
        }
    }

    private func saveImportedDocument(
        _ draft: DocumentImportDraft,
        decisions: [UUID: DocumentTrackedChangeDecision]
    ) {
        pendingDocumentImport = nil
        Task { @MainActor in
            await Task.yield()
            let panel = NSSavePanel()
            panel.title = "Save Markdown Copy"
            panel.message = "The original \(draft.format.title) document will remain unchanged."
            panel.prompt = "Save Copy"
            panel.allowedContentTypes = [.markdownDocument]
            panel.nameFieldStringValue = draft.suggestedMarkdownFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            guard panel.runModal() == .OK, let outputURL = panel.url else { return }
            isImportingDocument = true
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try DocumentImportService.save(draft, decisions: decisions, to: outputURL)
                }.value
                openImportedMarkdown(result.markdownURL)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
            isImportingDocument = false
        }
    }

    private func openImportedMarkdown(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                Task { @MainActor in viewModel.errorMessage = error.localizedDescription }
            }
        }
    }

    private func completeProjectImport(_ completion: ProjectImportCompletion) {
        showingProjectImportAssistant = false
        switch completion {
        case .markdown(let url):
            openImportedMarkdown(url)
        case .project(let root):
            do {
                if projectStore.rootURL?.standardizedFileURL != root.standardizedFileURL {
                    try projectStore.openProject(at: root)
                }
                activateProject()
            } catch {
                projectStore.errorMessage = error.localizedDescription
            }
        }
    }

    private func runReview() {
        guard settings.isProviderReady(settings.provider) else {
            runLocalPolish()
            return
        }
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

    private func runLocalPolish() {
        let styleDecisions = projectStore.rootURL.flatMap {
            try? ProjectStyleManager.loadDecisions(at: $0)
        } ?? []
        let result = LocalPolishService.polish(
            text: activeText,
            targetGrade: settings.targetGrade,
            issues: viewModel.visibleLocalIssues,
            styleDecisions: styleDecisions
        )
        guard let plan = result.plan else {
            let advisory = result.advisoryCount == 0
                ? "No local correction is needed."
                : "\(result.advisoryCount) advisory highlight\(result.advisoryCount == 1 ? " remains" : "s remain") for your judgment."
            viewModel.errorMessage = "Local Polish found no concrete change it could make safely. \(advisory) Set up Ollama for private generative rewriting, or connect OpenAI or Anthropic for cloud rewriting."
            return
        }
        polishedDraftPlan = plan
    }

    private func insertCitation(_ source: ResearchSource, locator: String) {
        let citation = CitationFormatter.markdownCitation(for: source, locator: locator)
        let current = activeText as NSString
        let selectionStart = editorSelection.location == NSNotFound
            ? current.length
            : min(max(0, editorSelection.location), current.length)
        let selectionLength = min(max(0, editorSelection.length), current.length - selectionStart)
        let safeLocation = selectionStart + selectionLength
        let range = NSRange(location: safeLocation, length: 0)
        let updated = current.replacingCharacters(in: range, with: citation)
        if projectStore.isOpen { projectStore.prepareForProgrammaticEdit(reason: "Before inserting citation") }
        undoCoordinator.replaceText(
            with: updated,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: "Insert Citation"
        )
        editorSelection = NSRange(location: safeLocation + (citation as NSString).length, length: 0)
    }

    private func navigateToRevisionFinding(_ finding: SystemicRevisionFinding) {
        guard let path = finding.chapterPath else { return }
        projectStore.selectChapter(path)
        Task { @MainActor in
            await Task.yield()
            let source = projectStore.text as NSString
            guard !finding.excerpt.isEmpty else { return }
            let range = source.range(of: finding.excerpt)
            guard range.location != NSNotFound else { return }
            editorSelection = range
            viewModel.focus(on: range)
        }
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
        prepareRewrite(goal, passage: selectedPassage)
    }

    private func prepareRewrite(
        _ goal: SelectionRewriteGoal,
        passage selectedPassage: (range: NSRange, text: String)
    ) {
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

    private func prepareRewrite(_ issue: WritingIssue) {
        let source = activeText as NSString
        let range: NSRange
        if issue.range.location != NSNotFound,
           NSMaxRange(issue.range) <= source.length,
           source.substring(with: issue.range) == issue.excerpt {
            range = issue.range
        } else {
            let relocated = source.range(of: issue.excerpt)
            guard relocated.location != NSNotFound,
                  source.range(of: issue.excerpt, options: [], range: NSRange(
                    location: NSMaxRange(relocated),
                    length: source.length - NSMaxRange(relocated)
                  )).location == NSNotFound else {
                viewModel.errorMessage = "That passage changed, so Kistulentz cannot rewrite it safely."
                return
            }
            range = relocated
        }

        let kind: SelectionRewriteKind
        switch issue.category {
        case .spelling, .grammar:
            kind = .correct
        case .adverb, .passiveVoice:
            kind = .strengthenVerbs
        case .referenceVoice where viewModel.referenceBook != nil:
            kind = .matchReferences
        case .hardSentence, .veryHardSentence, .structuralComplexity, .complexPhrase,
             .aiSuggestion, .referenceVoice, .continuity:
            kind = .simplify
        }

        editorSelection = range
        viewModel.focus(on: range)
        prepareRewrite(
            SelectionRewriteGoal(
                kind: kind,
                requestedTone: nil,
                issueInstruction: issue.message
            ),
            passage: (range, source.substring(with: range))
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
        case .referenceDeepening, .manuscriptReport, .manuscriptBible, .betaReader, .outlineSynopsis, .systemicRevision:
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
        let localConflicts = SuggestionRuleValidator.introducedCategories(
            replacing: presentation.sourceRange,
            in: activeText,
            with: alternative.text,
            targetGrade: settings.targetGrade
        )
        let documentConflicts = SuggestionRuleValidator.introducedCategories(
            original: activeText,
            replacement: result,
            targetGrade: settings.targetGrade
        )
        let conflicts = IssueCategory.allCases.filter { category in
            localConflicts.contains(category) || documentConflicts.contains(category)
        }
        guard conflicts.isEmpty else {
            viewModel.errorMessage = "That alternative introduces a new local flag (\(conflicts.map(\.title).joined(separator: ", "))), so Kistulentz did not apply it."
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

    private func preparePolishedDraftReview() {
        guard let review = viewModel.aiReview else { return }
        let plan = PolishedDraftPlanner.plan(
            original: activeText,
            polished: review.polishedText,
            targetGrade: settings.targetGrade
        )
        guard !plan.changes.isEmpty else {
            viewModel.errorMessage = "The polished draft already matches this document."
            return
        }
        polishedDraftPlan = plan
    }

    private func applyPolishedChanges(_ changeIDs: Set<UUID>, from plan: PolishedDraftPlan) {
        guard activeText == plan.sourceText else {
            polishedDraftPlan = nil
            viewModel.errorMessage = "The document changed while the polished draft was open. Reopen it to review an updated comparison."
            return
        }
        guard !changeIDs.isEmpty, let result = plan.applying(changeIDs: changeIDs) else {
            viewModel.errorMessage = "Select at least one safe passage to apply."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before applying polished passages")
        undoCoordinator.replaceText(
            with: result,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: changeIDs.count == 1 ? "Apply Polished Passage" : "Apply Polished Passages"
        )
        viewModel.preserveAIReview(afterApplying: result)
        polishedDraftPlan = nil
    }

    private func replaceWithPolishedDraft(from plan: PolishedDraftPlan) {
        guard activeText == plan.sourceText else {
            polishedDraftPlan = nil
            viewModel.errorMessage = "The document changed while the polished draft was open. Reopen it to review an updated comparison."
            return
        }
        guard plan.isFullReplacementSafe else {
            viewModel.errorMessage = "Resolve or decline the passages that conflict with local rules before replacing the document."
            return
        }

        projectStore.prepareForProgrammaticEdit(reason: "Before polished draft")
        undoCoordinator.replaceText(
            with: plan.polishedText,
            binding: activeTextBinding,
            undoManager: undoManager,
            actionName: plan.origin == .local ? "Use Local Polish" : "Use Polished Draft"
        )
        viewModel.preserveAIReview(afterApplying: plan.polishedText)
        polishedDraftPlan = nil
    }

    private func apply(_ issue: WritingIssue) {
        if let replacement = issue.replacement {
            let conflicts = SuggestionRuleValidator.introducedCategories(
                original: issue.excerpt,
                replacement: replacement,
                targetGrade: settings.targetGrade
            )
            guard conflicts.isEmpty else {
                viewModel.errorMessage = "That suggestion now conflicts with a local rule, so Kistulentz did not apply it."
                return
            }
        }
        let plan = SuggestionApplicationPlanner.planSingle(issue: issue, in: activeText)
        guard plan.hasChanges else {
            viewModel.errorMessage = "That passage has changed, so the suggestion can no longer be applied."
            return
        }
        guard SuggestionRuleValidator.isSafe(
            original: activeText,
            replacement: plan.resultText,
            targetGrade: settings.targetGrade
        ) else {
            viewModel.errorMessage = "That suggestion creates a new local flag in its surrounding passage, so Kistulentz did not apply it."
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
        let safeIssues = viewModel.allIssues.filter { issue in
            guard let replacement = issue.replacement else { return true }
            return SuggestionRuleValidator.isSafe(
                original: issue.excerpt,
                replacement: replacement,
                targetGrade: settings.targetGrade
            )
        }
        let plan = SuggestionApplicationPlanner.plan(issues: safeIssues, in: activeText)
        guard plan.hasChanges else {
            viewModel.errorMessage = plan.conflictCount > 0 || plan.staleCount > 0
                ? "The available replacements overlap or no longer match this draft. Apply them one at a time."
                : "No current suggestions include a concrete replacement."
            return
        }
        guard SuggestionRuleValidator.isSafe(
            original: activeText,
            replacement: plan.resultText,
            targetGrade: settings.targetGrade
        ) else {
            viewModel.errorMessage = "Applying those suggestions together would create a new local flag. Apply them one at a time instead."
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
        viewModel.preserveAIReview(afterApplying: plan.resultText)
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
                        if projectStore.recoveryRequest == nil {
                            projectStore.errorMessage = error.localizedDescription
                        }
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
    let isUsingBenepar: Bool
    let isAnalyzingStructure: Bool
    let onSelect: (WritingIssue) -> Void

    private let categories: [IssueCategory] = [
        .adverb, .passiveVoice, .structuralComplexity, .complexPhrase, .hardSentence, .veryHardSentence
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

                if isAnalyzingStructure {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Checking sentence structure locally…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if isUsingBenepar {
                    Label("Benepar structural analysis active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                GradeComparisonCard(
                    gradeLevel: stats.gradeLevel,
                    targetGrade: targetGrade
                )

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

private struct GradeComparisonCard: View {
    let gradeLevel: Double
    let targetGrade: Int

    private let maximumGrade = 18.0

    private var isOnTarget: Bool {
        gradeLevel <= Double(targetGrade) + 1
    }

    private var statusColor: Color {
        isOnTarget ? .green : .orange
    }

    private var statusTitle: String {
        isOnTarget ? "On target" : "Revise for clarity"
    }

    private var differenceDescription: String {
        let difference = gradeLevel - Double(targetGrade)
        let magnitude = abs(difference)

        guard magnitude >= 0.05 else { return "Matches target grade" }

        let amount = magnitude.formatted(.number.precision(.fractionLength(1)))
        let unit = abs(magnitude - 1) < 0.05 ? "grade" : "grades"
        return "\(amount) \(unit) \(difference > 0 ? "above" : "below") target"
    }

    private var accessibilitySummary: String {
        let current = gradeLevel.formatted(.number.precision(.fractionLength(1)))
        return "Current grade \(current). Target grade \(targetGrade). \(statusTitle). \(differenceDescription)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(gradeLevel, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("CURRENT GRADE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    Text(differenceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 10, 0)
                let currentX = 5 + plotWidth * gradeFraction(gradeLevel)
                let targetX = 5 + plotWidth * gradeFraction(Double(targetGrade))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 4)
                        .position(x: proxy.size.width / 2, y: 8)

                    Rectangle()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: 16)
                        .position(x: targetX, y: 8)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                        .position(x: currentX, y: 8)
                }
            }
            .frame(height: 16)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text("Current \(gradeLevel.formatted(.number.precision(.fractionLength(1))))")
                }
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: 10)
                    Text("Target \(targetGrade)")
                }
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Text("0")
                Spacer()
                Text("Grade level")
                Spacer()
                Text("18")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readability grade")
        .accessibilityValue(accessibilitySummary)
    }

    private func gradeFraction(_ grade: Double) -> CGFloat {
        CGFloat(max(0, min(maximumGrade, grade)) / maximumGrade)
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
    let blockedAISuggestionCount: Int
    let isReviewing: Bool
    let isRewriting: Bool
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
    let onRewrite: (WritingIssue) -> Void
    let onApplyAll: () -> Void
    let onReviewPolishedDraft: () -> Void

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
                .disabled(isReviewing)
                .help(hasAPIKey ? "Run a new AI review" : "Run a safe local polish")
                .accessibilityLabel(hasAPIKey ? "Run a new AI review" : "Run a safe local polish")
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
                            Label("Local Polish is ready", systemImage: "checkmark.shield")
                                .font(.caption.weight(.semibold))
                            Text("Kistulentz can review and apply concrete built-in corrections without sending text anywhere. Advisory changes that require rewriting stay as highlights.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Polish Locally", action: onRunReview)
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                Button("Set Up Deeper AI…", action: onOpenSettings)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
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
                            if blockedAISuggestionCount > 0 {
                                Label(
                                    "Kistulentz withheld \(blockedAISuggestionCount) AI suggestion\(blockedAISuggestionCount == 1 ? "" : "s") that conflicted with local rules.",
                                    systemImage: "shield.checkered"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                            Button("Review polished draft…", action: onReviewPolishedDraft)
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
                            canRewrite: hasAPIKey && !isRewriting,
                            onSelect: onSelect,
                            onApply: onApply,
                            onDecline: onDecline,
                            onRewrite: onRewrite
                        )
                    }

                    if issues.isEmpty {
                        ContentUnavailableView(
                            "No local flags",
                            systemImage: "checkmark.circle",
                            description: Text(hasAPIKey
                                ? "Run an AI review for deeper grammar and rewriting suggestions."
                                : "Local analysis is clear. Set up Ollama or a cloud provider only when you want generative rewriting.")
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
                    ? "The reference stays local. Selected excerpts are sent only when you confirm an AI-backed Polish."
                    : "\(reference.sourceCount) books are combined locally. Selected excerpts are sent only when you confirm an AI-backed Polish.")
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
    let canRewrite: Bool
    let onSelect: (WritingIssue) -> Void
    let onApply: (WritingIssue) -> Void
    let onDecline: (WritingIssue) -> Void
    let onRewrite: (WritingIssue) -> Void

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
                } else {
                    Button("Rewrite…") { onRewrite(issue) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .disabled(!canRewrite)
                        .help(canRewrite
                            ? "Create three alternatives that address this card"
                            : "Connect or choose an AI provider to create alternatives")
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

private enum PolishedDraftDecision {
    case accepted
    case declined
}

private struct PolishedDraftReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: PolishedDraftPlan
    let onApplySelected: (Set<UUID>) -> Void
    let onReplaceAll: () -> Void

    @State private var decisions: [UUID: PolishedDraftDecision] = [:]
    @State private var showingReplaceAllConfirmation = false

    private var acceptedIDs: Set<UUID> {
        Set(decisions.compactMap { $0.value == .accepted ? $0.key : nil })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.origin == .local ? "Review Local Polish" : "Review Polished Draft")
                        .font(.title2.weight(.semibold))
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !plan.isFullReplacementSafe {
                        let conflictCount = max(
                            plan.unsafeChanges.count,
                            plan.introducedDocumentRuleCategories.count
                        )
                        Label(
                            "Kistulentz blocked \(conflictCount) polished change\(conflictCount == 1 ? "" : "s") that would introduce new local flags.",
                            systemImage: "shield.lefthalf.filled.badge.checkmark"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(Array(plan.changes.enumerated()), id: \.element.id) { index, change in
                        PolishedDraftChangeCard(
                            number: index + 1,
                            change: change,
                            decision: decisions[change.id],
                            onAccept: { decisions[change.id] = .accepted },
                            onDecline: { decisions[change.id] = .declined }
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Text(acceptedIDs.isEmpty
                    ? "No passages selected"
                    : "\(acceptedIDs.count) passage\(acceptedIDs.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Replace All") {
                    showingReplaceAllConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(!plan.isFullReplacementSafe)
                .help(plan.isFullReplacementSafe
                    ? "Replace the document with the complete polished draft"
                    : "Replace All is unavailable because some passages conflict with local rules")
                Button("Apply Selected") {
                    onApplySelected(acceptedIDs)
                }
                .buttonStyle(.borderedProminent)
                .disabled(acceptedIDs.isEmpty)
            }
            .padding(16)
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 580, idealHeight: 720)
        .confirmationDialog(
            "Replace the entire document with the polished draft?",
            isPresented: $showingReplaceAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace All", role: .destructive, action: onReplaceAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(plan.origin == .local
                ? "The complete local replacement will be one normal Undo action. No writing was sent anywhere."
                : "The complete replacement will be one normal Undo action. Your AI review will remain available.")
        }
    }

    private var summary: String {
        let count = plan.changes.count
        let source = plan.origin == .local
            ? "Built-in rules created these changes entirely on this Mac."
            : "The selected AI provider created these changes."
        return "\(source) Compare \(count) changed passage\(count == 1 ? "" : "s"). Accept individual changes, or replace the whole document after confirmation."
    }
}

private struct PolishedDraftChangeCard: View {
    let number: Int
    let change: PolishedDraftChange
    let decision: PolishedDraftDecision?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Passage \(number)")
                    .font(.caption.weight(.semibold))
                if !change.isSafe {
                    Label("Blocked", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if decision == .accepted {
                    Label("Accepted", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if decision == .declined {
                    Label("Declined", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                passageColumn(title: "CURRENT", text: change.originalText, color: .red)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 25)
                passageColumn(title: "POLISHED", text: change.replacementText, color: .green)
            }

            if let message = change.safetyMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Spacer()
                decisionButton(
                    title: "Decline",
                    systemImage: "xmark",
                    isSelected: decision == .declined,
                    color: .secondary,
                    action: onDecline
                )
                decisionButton(
                    title: "Accept",
                    systemImage: "checkmark",
                    isSelected: decision == .accepted,
                    color: .accentColor,
                    action: onAccept
                )
                .disabled(!change.isSafe)
            }
        }
        .padding(14)
        .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(change.isSafe ? Color.secondary.opacity(0.15) : Color.orange.opacity(0.45))
        }
    }

    private func passageColumn(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func decisionButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : color)
                .background(isSelected ? color : Color.clear, in: Capsule())
                .overlay {
                    Capsule().stroke(color.opacity(isSelected ? 0 : 0.45))
                }
        }
        .buttonStyle(.plain)
    }
}
