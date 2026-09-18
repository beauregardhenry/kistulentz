import Foundation

// Split out of EditorWorkspace.swift: Local Polish, citation insertion, revision/de-stink
// navigation, selection rewrite, and applying/declining suggestions -- the manuscript-editing
// actions the toolbar and sidebars invoke. No behavior change from the move itself.
extension EditorWorkspace {
    // Polish always runs locally, regardless of whether an AI provider is configured -- it used
    // to silently switch to sending the draft to whatever provider was set up (even one configured
    // for an unrelated feature, like Selection Rewrite), which meant a provider being ready
    // elsewhere in Settings could change what this specific action did without the author asking
    // for that. AI-assisted rewriting stays available, but only through actions the author invokes
    // explicitly for that purpose, like Selection Rewrite.
    func runReview() {
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

    func insertCitation(_ source: ResearchSource, locator: String) {
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

    func navigateToRevisionFinding(_ finding: SystemicRevisionFinding) {
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

    var destinkCurrentDocument: ManuscriptDocument {
        ManuscriptDocument(
            relativePath: projectStore.selectedChapterPath ?? fileURL?.lastPathComponent ?? "Untitled.md",
            title: projectStore.isOpen
                ? projectStore.selectedChapterTitle
                : (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"),
            text: activeText
        )
    }

    /// Load the manuscript once, when the review is opened, instead of on every re-render of the
    /// sheet's builder — reading every chapter from disk is main-thread work.
    func presentDestinker() {
        destinkManuscriptDocuments = projectStore.isOpen
            ? (try? projectStore.betaReadersStore.documents(for: .manuscript, selection: nil))
            : nil
        presentation.present(.destinker)
    }

    func navigateToDestinkFinding(_ path: String, range: NSRange) {
        if projectStore.isOpen, path != projectStore.selectedChapterPath {
            projectStore.selectChapter(path)
        }
        Task { @MainActor in
            await Task.yield()
            let source = activeText as NSString
            guard range.location >= 0, NSMaxRange(range) <= source.length else { return }
            editorSelection = range
            viewModel.focus(on: range)
        }
    }

    var selectedPassage: (range: NSRange, text: String)? {
        let source = activeText as NSString
        guard editorSelection.location != NSNotFound,
              editorSelection.length > 0,
              NSMaxRange(editorSelection) <= source.length else { return nil }
        return (editorSelection, source.substring(with: editorSelection))
    }

    func prepareRewrite(_ goal: SelectionRewriteGoal) {
        guard let selectedPassage else {
            viewModel.errorMessage = "Select a passage before choosing a rewrite."
            return
        }
        prepareRewrite(goal, passage: selectedPassage)
    }

    func prepareRewrite(
        _ goal: SelectionRewriteGoal,
        passage selectedPassage: (range: NSRange, text: String)
    ) {
        guard validateSelectedProvider() else { return }
        if goal.kind == .matchReferences, viewModel.referenceBook == nil {
            viewModel.errorMessage = "Choose at least one reference before matching its craft profile."
            return
        }

        let style = projectStore.isOpen ? styleLearningStore.styleText : nil
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

    func prepareRewrite(_ issue: WritingIssue) {
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
             .aiTell, .aiSuggestion, .referenceVoice, .continuity, .avoidedWord:
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

    func validateSelectedProvider() -> Bool {
        let provider = settings.provider
        guard settings.isProviderReady(provider) else {
            viewModel.errorMessage = provider.requiresAPIKey
                ? "Add your \(provider.title) API key and choose a model in Settings first."
                : "Open Settings, detect the Ollama models already on this Mac, and choose one first."
            return false
        }
        return true
    }

    func executeAIRequest(_ request: AIRequestPreview) {
        switch request.purpose {
        case .selectionRewrite:
            viewModel.runSelectionRewrite(request: request, settings: settings)
        case .referenceDeepening, .manuscriptReport, .manuscriptBible, .betaReader, .outlineSynopsis, .systemicRevision:
            break
        }
    }

    func applyRewrite(
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

    func applyPolishedChanges(_ changeIDs: Set<UUID>, from plan: PolishedDraftPlan) {
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
        polishedDraftPlan = nil
    }

    func replaceWithPolishedDraft(from plan: PolishedDraftPlan) {
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
        polishedDraftPlan = nil
    }

    func apply(_ issue: WritingIssue) {
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
        styleLearningStore.recordStyleDecision(action: .accepted, issue: issue)
    }

    func decline(_ issue: WritingIssue) {
        if viewModel.decline(issue, in: activeText) {
            styleLearningStore.recordStyleDecision(action: .declined, issue: issue)
        }
    }

    func prepareApplyAll() {
        let safeIssues = viewModel.allIssues.filter { issue in
            if settings.isPracticeModeEnabled, issue.category.practicePrompt != nil { return false }
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

    func applyAll(_ plan: SuggestionApplicationPlan) {
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
            styleLearningStore.recordStyleDecision(action: .accepted, issue: issue)
        }
        pendingApplyAllPlan = nil
    }

    func applyAllButtonTitle(for plan: SuggestionApplicationPlan) -> String {
        "Apply \(plan.appliedCount) \(plan.appliedCount == 1 ? "Change" : "Changes")"
    }

    func applyAllMessage(for plan: SuggestionApplicationPlan) -> String {
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
