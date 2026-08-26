import SwiftUI
import UniformTypeIdentifiers

struct EditorWorkspace: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var referenceLibrary: ReferenceLibraryStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @StateObject private var viewModel = EditorViewModel()
    @StateObject private var undoCoordinator = DocumentUndoCoordinator()
    @State private var showingReplaceConfirmation = false
    @State private var pendingApplyAllPlan: SuggestionApplicationPlan?
    @State private var showingReferenceImporter = false
    @State private var showingReferenceLibrary = false
    @State private var selectedLibraryReferences: Set<String> = []

    private let epubType = UTType(importedAs: "org.idpf.epub-container")

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            HSplitView {
                ReadabilitySidebar(
                    stats: viewModel.analysis.stats,
                    issues: viewModel.visibleLocalIssues,
                    targetGrade: settings.targetGrade,
                    onSelect: viewModel.focus
                )
                .frame(minWidth: 215, idealWidth: 235, maxWidth: 270)

                MarkdownTextView(
                    text: $document.text,
                    issues: viewModel.allIssues,
                    focusRequest: viewModel.focusRequest
                )
                .frame(minWidth: 500)

                ReviewSidebar(
                    issues: viewModel.allIssues,
                    review: viewModel.aiReview,
                    isReviewing: viewModel.isReviewing,
                    provider: settings.provider,
                    hasAPIKey: settings.hasKey(for: settings.provider),
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
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.configureDocument(url: fileURL, text: document.text)
            viewModel.scheduleAnalysis(
                text: document.text,
                targetGrade: settings.targetGrade,
                immediately: true
            )
        }
        .onChange(of: document.text) { _, newValue in
            viewModel.scheduleAnalysis(text: newValue, targetGrade: settings.targetGrade)
        }
        .onChange(of: fileURL) { _, newValue in
            viewModel.configureDocument(url: newValue, text: document.text)
        }
        .onChange(of: settings.targetGrade) { _, newValue in
            viewModel.scheduleAnalysis(text: document.text, targetGrade: newValue, immediately: true)
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
                viewModel.importReference(from: url, draft: document.text)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingReferenceLibrary) {
            ReferenceLibraryView(selectedChoiceIDs: $selectedLibraryReferences) { reference in
                viewModel.useReference(reference, draft: document.text)
            }
            .environmentObject(referenceLibrary)
            .environmentObject(settings)
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Replace this document with the polished draft?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Document", role: .destructive) {
                if let polished = viewModel.aiReview?.polishedText {
                    undoCoordinator.replaceText(
                        with: polished,
                        binding: $document.text,
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

            VStack(alignment: .leading, spacing: 1) {
                Text(fileURL?.lastPathComponent ?? "Untitled.md")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("Markdown document")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
        viewModel.runAIReview(text: document.text, settings: settings)
    }

    private func apply(_ issue: WritingIssue) {
        let plan = SuggestionApplicationPlanner.planSingle(issue: issue, in: document.text)
        guard plan.hasChanges else {
            viewModel.errorMessage = "That passage has changed, so the suggestion can no longer be applied."
            return
        }

        undoCoordinator.replaceText(
            with: plan.resultText,
            binding: $document.text,
            undoManager: undoManager,
            actionName: "Accept Suggestion"
        )
        viewModel.preserveAIReview(afterAccepting: issue, in: plan.resultText)
    }

    private func decline(_ issue: WritingIssue) {
        viewModel.decline(issue, in: document.text)
    }

    private func prepareApplyAll() {
        let plan = SuggestionApplicationPlanner.plan(issues: viewModel.allIssues, in: document.text)
        guard plan.hasChanges else {
            viewModel.errorMessage = plan.conflictCount > 0 || plan.staleCount > 0
                ? "The available replacements overlap or no longer match this draft. Apply them one at a time."
                : "No current suggestions include a concrete replacement."
            return
        }
        pendingApplyAllPlan = plan
    }

    private func applyAll(_ plan: SuggestionApplicationPlan) {
        undoCoordinator.replaceText(
            with: plan.resultText,
            binding: $document.text,
            undoManager: undoManager,
            actionName: "Apply All Suggestions"
        )
        viewModel.clearAIReview()
        pendingApplyAllPlan = nil
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
                            Label("Connect \(provider.title)", systemImage: "key")
                                .font(.caption.weight(.semibold))
                            Text("Local readability and EPUB comparisons work without a key. Connect for grammar corrections and deeper rewrites.")
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
                                : "Local analysis is clear. Add an API key only when you want deeper AI suggestions.")
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
