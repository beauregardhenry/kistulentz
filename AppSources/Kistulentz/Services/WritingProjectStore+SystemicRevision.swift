import Foundation

extension WritingProjectStore {

    // MARK: - Systemic Revision

    func runLocalRevisionScan(targetGrade: Int, sources: [ResearchSource]) {
        guard let rootURL, let manifest else { return }
        do {
            saveNow()
            let documents = try manuscriptDocuments()
            let manuscript = manuscriptAnalysis
            let bibliography = researchStore.projectBibliography
            isScanningRevisions = true
            Task { [weak self] in
                let findings = await Task.detached(priority: .utility) {
                    SystemicRevisionAnalyzer.analyze(
                        projectName: manifest.name,
                        kind: manifest.kind,
                        documents: documents,
                        manuscript: manuscript,
                        bibliography: bibliography,
                        sources: sources,
                        targetGrade: targetGrade
                    )
                }.value
                guard let self, self.rootURL == rootURL else { return }
                self.revisionArchive = SystemicRevisionAnalyzer.reconcile(findings, with: self.revisionArchive)
                self.isScanningRevisions = false
                self.saveRevisionArchive()
            }
        } catch {
            isScanningRevisions = false
            errorMessage = error.localizedDescription
        }
    }

    func setRevisionFindingStatus(_ id: UUID, status: RevisionFindingStatus) {
        guard let index = revisionArchive.findings.firstIndex(where: { $0.id == id }) else { return }
        revisionArchive.findings[index].status = status
        saveRevisionArchive()
    }

    func addRevisionGoal(title: String, notes: String, pass: RevisionPass) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        revisionArchive.goals.append(RevisionGoal(title: clean, notes: notes, revisionPass: pass))
        saveRevisionArchive()
    }

    func toggleRevisionGoal(_ id: UUID) {
        guard let index = revisionArchive.goals.firstIndex(where: { $0.id == id }) else { return }
        revisionArchive.goals[index].isComplete.toggle()
        saveRevisionArchive()
    }

    func removeRevisionGoal(_ id: UUID) {
        revisionArchive.goals.removeAll { $0.id == id }
        saveRevisionArchive()
    }

    func revisionDocuments() throws -> [ManuscriptDocument] {
        saveNow()
        return try manuscriptDocuments()
    }

    func revisionAIContext(sources: [ResearchSource]) throws -> String {
        let documents = try revisionDocuments()
        let projectSources = sources.filter { researchStore.projectBibliography.sourceIDs.contains($0.id) }
        let bibliography = CitationFormatter.bibliography(projectSources, style: researchStore.projectBibliography.style)
        let manuscript = documents.map {
            "<chapter path=\"\($0.relativePath)\">\n\(String($0.text.prefix(18_000)))\n</chapter>"
        }.joined(separator: "\n\n")
        return """
        <project_research_notes>
        \(String(researchStore.researchNotesText.prefix(10_000)))
        </project_research_notes>

        <project_bibliography>
        \(bibliography)
        </project_bibliography>

        <manuscript>
        \(String(manuscript.prefix(90_000)))
        </manuscript>
        """
    }

    func addAIRevisionFindings(_ findings: [SystemicRevisionFinding], summary: String) {
        var bySignature = Dictionary(uniqueKeysWithValues: revisionArchive.findings.map { ($0.signature, $0) })
        for finding in findings {
            if let previous = bySignature[finding.signature] {
                var updated = finding
                updated.id = previous.id
                updated.status = previous.status
                updated.createdAt = previous.createdAt
                bySignature[finding.signature] = updated
            } else {
                bySignature[finding.signature] = finding
            }
        }
        revisionArchive.findings = Array(bySignature.values).sorted {
            if $0.classification.rank != $1.classification.rank { return $0.classification.rank < $1.classification.rank }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        revisionAISummary = summary
        saveRevisionArchive()
    }

    func makeRevisionChangeSet(findingIDs: Set<UUID>) throws -> RevisionChangeSet {
        try RevisionChangePlanner.changes(from: revisionArchive.findings.filter { findingIDs.contains($0.id) })
    }

    func validateRevisionChangeSet(_ set: RevisionChangeSet) -> RevisionChangeSet {
        do { return RevisionChangePlanner.validate(set, documents: try documentsByPath(for: Set(set.includedChanges.map(\.chapterPath)))) }
        catch { errorMessage = error.localizedDescription; return set }
    }

    @discardableResult
    func applyRevisionChangeSet(_ set: RevisionChangeSet) -> Bool {
        guard let rootURL else { return false }
        do {
            saveNow()
            let paths = Set(set.includedChanges.map(\.chapterPath))
            let before = try documentsByPath(for: paths)
            let checked = RevisionChangePlanner.validate(set, documents: before)
            guard checked.hasChanges else { throw SystemicRevisionError.noConcreteChanges }
            guard !checked.hasConflicts else { throw SystemicRevisionError.stalePassage(checked.includedChanges.first(where: { $0.conflict != nil })?.chapterPath ?? "the manuscript") }
            let after = try RevisionChangePlanner.applying(checked, to: before)

            for path in paths {
                guard let content = before[path] else { continue }
                if let snapshot = try WritingProjectDisk.createSnapshot(
                    chapterPath: path,
                    content: content,
                    name: nil,
                    reason: "Before systemic revision",
                    at: rootURL
                ) { snapshots.insert(snapshot, at: 0) }
            }
            do {
                for path in paths.sorted() {
                    guard let content = after[path] else { continue }
                    try WritingProjectDisk.writeChapter(content, relativePath: path, at: rootURL)
                }
            } catch {
                for (path, content) in before { try? WritingProjectDisk.writeChapter(content, relativePath: path, at: rootURL) }
                throw error
            }
            for id in checked.includedChanges.compactMap(\.findingID) {
                if let index = revisionArchive.findings.firstIndex(where: { $0.id == id }) { revisionArchive.findings[index].status = .resolved }
            }
            saveRevisionArchive()
            try refreshProjectAfterRevision(preferredSelection: selectedChapterPath)
            registerRevisionUndo(expected: after, replacement: before, resolvedFindingIDs: checked.includedChanges.compactMap(\.findingID), undoing: true)
            scheduleManuscriptAnalysis(immediately: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func documentsByPath(for paths: Set<String>) throws -> [String: String] {
        guard let rootURL else { return [:] }
        var values: [String: String] = [:]
        let known = Set(chapters.map(\.relativePath))
        for path in paths {
            guard known.contains(path) else { throw SystemicRevisionError.stalePassage(path) }
            values[path] = try WritingProjectDisk.readChapter(path, at: rootURL)
        }
        return values
    }

    private func refreshProjectAfterRevision(preferredSelection: String?) throws {
        guard let rootURL, let manifest else { return }
        chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: manifest)
        if let preferredSelection, chapters.contains(where: { $0.relativePath == preferredSelection }) {
            try loadChapter(preferredSelection)
        }
        snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
    }

    private func registerRevisionUndo(
        expected: [String: String],
        replacement: [String: String],
        resolvedFindingIDs: [UUID],
        undoing: Bool
    ) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.performRevisionUndo(expected: expected, replacement: replacement, findingIDs: resolvedFindingIDs, undoing: undoing)
        }
        projectUndoManager?.setActionName(undoing ? "Apply Systemic Revision" : "Undo Systemic Revision")
    }

    private func performRevisionUndo(
        expected: [String: String],
        replacement: [String: String],
        findingIDs: [UUID],
        undoing: Bool
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            for (path, content) in expected {
                guard try WritingProjectDisk.readChapter(path, at: rootURL) == content else { throw SystemicRevisionError.filesChanged }
            }
            for (path, content) in replacement { try WritingProjectDisk.writeChapter(content, relativePath: path, at: rootURL) }
            for id in findingIDs {
                if let index = revisionArchive.findings.firstIndex(where: { $0.id == id }) {
                    revisionArchive.findings[index].status = undoing ? .open : .resolved
                }
            }
            saveRevisionArchive()
            try refreshProjectAfterRevision(preferredSelection: selectedChapterPath)
            registerRevisionUndo(expected: replacement, replacement: expected, resolvedFindingIDs: findingIDs, undoing: !undoing)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRevisionArchive() {
        guard let rootURL else { return }
        do { try SystemicRevisionDisk.save(revisionArchive, at: rootURL) }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Project Polish Inputs

    func projectPolishInputs() throws -> (
        documents: [ManuscriptDocument],
        styleDecisions: [ProjectStyleDecision]
    ) {
        guard let rootURL else { throw SystemicRevisionError.filesChanged }
        saveNow()
        guard !isDirty else { throw SystemicRevisionError.filesChanged }
        let documents = try chapters.map { chapter in
            ManuscriptDocument(
                relativePath: chapter.relativePath,
                title: chapter.title,
                text: try WritingProjectDisk.readChapter(chapter.relativePath, at: rootURL)
            )
        }
        return (
            documents,
            try ProjectStyleManager.loadDecisions(at: rootURL)
        )
    }
}
