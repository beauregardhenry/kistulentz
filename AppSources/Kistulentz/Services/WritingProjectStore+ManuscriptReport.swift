import Foundation

extension WritingProjectStore {

    // MARK: - Manuscript AI & Report

    func manuscriptAIContext() throws -> String {
        ManuscriptAnalyzer.context(
            documents: try manuscriptDocuments(),
            report: manuscriptReportText,
            bible: bibleText
        )
    }

    func applyAIReport(_ response: AIManuscriptMarkdownResponse, provider: AIProvider, model: String) {
        guard let rootURL, let manifest else { return }
        do {
            let ai = """
            ## AI-Deepened Editorial Notes

            > Generated on request with \(provider.title) · \(model). \(response.summary)

            \(response.markdown.trimmingCharacters(in: .whitespacesAndNewlines))
            """
            manuscriptCache.aiReportMarkdown = ai
            try ManuscriptProjectDisk.saveCache(manuscriptCache, at: rootURL)
            let current = (try? ManuscriptProjectDisk.loadReport(at: rootURL)) ?? manuscriptReportText
            let local = manuscriptAnalysis?.reportMarkdown ?? "## Local Analysis\n\nWaiting for the next local analysis."
            manuscriptReportText = ManuscriptReportManager.compose(
                current: current,
                localReport: local,
                aiMarkdown: ai,
                projectName: manifest.name,
                kind: manifest.kind
            )
            try ManuscriptProjectDisk.saveReport(manuscriptReportText, at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyAIBible(_ response: AIManuscriptMarkdownResponse, provider: AIProvider, model: String) {
        let updated = ManuscriptBibleManager.addingAIDeepening(
            response.markdown,
            to: bibleText,
            provider: provider.title,
            model: model
        )
        applyBibleUpdate(updated, reason: "Before AI Bible deepening", summary: response.summary, forceSnapshot: true)
    }

    func scheduleManuscriptAnalysis(immediately: Bool = false) {
        manuscriptAnalysisTask?.cancel()
        guard let rootURL, let manifest else { return }
        let chapterSnapshot = chapters
        let selectedPathSnapshot = selectedChapterPath
        let selectedTextSnapshot = text
        isAnalyzingManuscript = true
        manuscriptAnalysisTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(1_400)) }
            guard let self, !Task.isCancelled, self.rootURL == rootURL else { return }
            let loaded = await Task.detached(priority: .utility) {
                Result {
                    let documents = try Self.loadManuscriptDocuments(
                        chapters: chapterSnapshot,
                        selectedPath: selectedPathSnapshot,
                        selectedText: selectedTextSnapshot,
                        rootURL: rootURL
                    )
                    let analysis = ManuscriptAnalyzer.analyze(
                        projectName: manifest.name,
                        kind: manifest.kind,
                        documents: documents
                    )
                    let wordCount = documents.reduce(0) {
                        $0 + WritingProjectDisk.wordCount(in: $1.text)
                    }
                    return (
                        analysis: analysis,
                        wordCount: wordCount,
                        structuralSample: ManuscriptStructuralSampler.text(from: documents)
                    )
                }
            }.value
            guard !Task.isCancelled, self.rootURL == rootURL else { return }
            var analysis: ManuscriptAnalysis
            let wordCount: Int
            let structuralSample: String
            switch loaded {
            case .success(let work):
                analysis = work.analysis
                wordCount = work.wordCount
                structuralSample = work.structuralSample
            case .failure(let error):
                self.isAnalyzingManuscript = false
                self.errorMessage = error.localizedDescription
                return
            }
            // Publish the native result before waiting for an optional external
            // language pack to start. A cold Benepar worker can take seconds,
            // but it must never delay Kistulentz's built-in report and Bible.
            self.applyLocalManuscriptAnalysis(analysis)
            guard !Task.isCancelled, self.rootURL == rootURL else { return }
            let shouldRefreshStructure = immediately
                || self.manuscriptCache.structuralProfile == nil
                || abs(wordCount - self.lastStructuralAnalysisWordCount) >= 100
                || self.lastStructuralAnalysisAt.map { Date().timeIntervalSince($0) >= 60 } != false
            if shouldRefreshStructure,
               let structure = await BeneparService.shared.analyzeIfAvailable(
                   text: structuralSample,
                   maximumSentences: 160,
                   includeIssues: false
               ) {
                guard !Task.isCancelled, self.rootURL == rootURL else { return }
                self.manuscriptCache.structuralProfile = structure.metrics
                self.lastStructuralAnalysisAt = Date()
                self.lastStructuralAnalysisWordCount = wordCount
            }
            if let structure = self.manuscriptCache.structuralProfile {
                analysis = ManuscriptAnalyzer.addingStructuralProfile(structure, to: analysis)
                guard !Task.isCancelled, self.rootURL == rootURL else { return }
                self.applyLocalManuscriptAnalysis(analysis)
            }
        }
    }

    private func applyLocalManuscriptAnalysis(_ analysis: ManuscriptAnalysis) {
        guard let rootURL, let manifest else { return }
        do {
            manuscriptAnalysis = analysis
            let currentReport = (try? ManuscriptProjectDisk.loadReport(at: rootURL)) ?? manuscriptReportText
            manuscriptReportText = ManuscriptReportManager.compose(
                current: currentReport,
                localReport: analysis.reportMarkdown,
                aiMarkdown: manuscriptCache.aiReportMarkdown,
                projectName: manifest.name,
                kind: manifest.kind
            )
            try ManuscriptProjectDisk.saveReport(manuscriptReportText, at: rootURL)

            let updatedBible = ManuscriptBibleManager.merge(
                currentBible: bibleText,
                previousGeneratedBlock: manuscriptCache.generatedBibleBlock,
                newGeneratedBlock: analysis.generatedBibleBlock,
                projectName: manifest.name,
                kind: manifest.kind
            )
            if updatedBible != bibleText {
                applyBibleUpdate(
                    updatedBible,
                    reason: "Before automatic Bible update",
                    summary: bibleChangeSummary(old: bibleText, new: updatedBible),
                    forceSnapshot: !hasCapturedBibleAutomaticBaseline
                )
                hasCapturedBibleAutomaticBaseline = true
            }
            manuscriptCache.generatedBibleBlock = analysis.generatedBibleBlock
            try ManuscriptProjectDisk.saveCache(manuscriptCache, at: rootURL)
            isAnalyzingManuscript = false
        } catch {
            isAnalyzingManuscript = false
            errorMessage = error.localizedDescription
        }
    }

    func manuscriptDocuments() throws -> [ManuscriptDocument] {
        guard let rootURL else { return [] }
        return try Self.loadManuscriptDocuments(
            chapters: chapters,
            selectedPath: selectedChapterPath,
            selectedText: text,
            rootURL: rootURL
        )
    }

    nonisolated private static func loadManuscriptDocuments(
        chapters: [ProjectChapter],
        selectedPath: String?,
        selectedText: String,
        rootURL: URL
    ) throws -> [ManuscriptDocument] {
        try chapters.map { chapter in
            let chapterText = chapter.relativePath == selectedPath
                ? selectedText
                : try WritingProjectDisk.readChapter(chapter.relativePath, at: rootURL)
            return ManuscriptDocument(
                relativePath: chapter.relativePath,
                title: chapter.title,
                text: chapterText
            )
        }
    }
}
