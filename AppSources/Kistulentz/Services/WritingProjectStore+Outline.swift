import Foundation

extension WritingProjectStore {

    // MARK: - Outline

    var outlineRows: [OutlineFlatRow] { OutlineTree.flattened(outlineNodes) }

    func outlineNode(id: UUID?) -> OutlineNode? {
        guard let id else { return nil }
        return OutlineTree.node(id: id, in: outlineNodes)
    }

    func outlineChildren(of parentID: UUID?) -> [OutlineNode] {
        OutlineTree.children(of: parentID, in: outlineNodes)
    }

    func outlineWordCount(for node: OutlineNode) -> Int {
        let paths = OutlineTree.filePaths(in: [node])
        return chapters.filter { paths.contains($0.relativePath) }.reduce(0) { $0 + $1.wordCount }
    }

    func outlineWarningCount(for node: OutlineNode) -> Int {
        let paths = Set(OutlineTree.filePaths(in: [node]))
        guard let analysis = manuscriptAnalysis else { return 0 }
        return (analysis.continuityChecks + analysis.claimChecks).filter { finding in
            guard let path = finding.chapterPath else { return false }
            return paths.contains(path)
        }.count
    }

    func selectOutlineNode(_ id: UUID) {
        guard let path = outlineNode(id: id)?.relativePath else { return }
        selectChapter(path)
    }

    func updateOutlineNode(_ node: OutlineNode) {
        var updated = node
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.title.isEmpty else { return }
        updated.metadata.modifiedAt = Date()
        guard OutlineTree.update(updated, in: &outlineNodes) else { return }
        scheduleOutlineSave()
    }

    @discardableResult
    func addOutlineItem(kind: OutlineNodeKind, title: String, parentID: UUID?) -> UUID? {
        guard let rootURL else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let parentKind = parentID.flatMap { OutlineTree.node(id: $0, in: outlineNodes)?.kind }
        guard OutlineTree.canPlace(kind, under: parentKind) else {
            errorMessage = ProjectOutlineError.invalidHierarchy.localizedDescription
            return nil
        }

        do {
            var relativePath: String?
            if kind != .part {
                let fileName = WritingProjectDisk.uniqueMarkdownFileName(for: cleanTitle, at: rootURL)
                relativePath = try WritingProjectDisk.createMarkdownFile(named: fileName, at: rootURL)
                try WritingProjectDisk.writeChapter("# \(cleanTitle)\n\n", relativePath: relativePath!, at: rootURL)
            }
            var metadata = OutlineNodeMetadata()
            metadata.status = .planned
            let node = OutlineNode(
                title: cleanTitle,
                kind: kind,
                relativePath: relativePath,
                metadata: metadata
            )
            guard OutlineTree.append(node, to: parentID, in: &outlineNodes) else {
                throw ProjectOutlineError.invalidHierarchy
            }
            saveOutlineNow()
            try syncChaptersWithOutline(preferredSelection: relativePath ?? selectedChapterPath)
            scheduleManuscriptAnalysis(immediately: true)
            return node.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func moveOutlineNode(_ nodeID: UUID, onto targetID: UUID) {
        var updated = outlineNodes
        guard OutlineTree.move(nodeID: nodeID, onto: targetID, in: &updated) else {
            errorMessage = ProjectOutlineError.invalidHierarchy.localizedDescription
            return
        }
        outlineNodes = updated
        do {
            saveOutlineNow()
            try syncChaptersWithOutline(preferredSelection: selectedChapterPath)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveOutlineNode(_ nodeID: UUID, toParent parentID: UUID?) {
        var updated = outlineNodes
        guard OutlineTree.move(nodeID: nodeID, toParent: parentID, in: &updated) else {
            errorMessage = ProjectOutlineError.invalidHierarchy.localizedDescription
            return
        }
        outlineNodes = updated
        do {
            saveOutlineNow()
            try syncChaptersWithOutline(preferredSelection: selectedChapterPath)
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func suggestSynopsisLocally(for nodeID: UUID) {
        do {
            guard var node = outlineNode(id: nodeID) else { throw ProjectOutlineError.missingNode }
            node.metadata.suggestedSynopsis = OutlineSynopsisGenerator.suggest(from: try outlineText(for: nodeID))
            node.metadata.modifiedAt = Date()
            updateOutlineNode(node)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySuggestedSynopsis(_ synopsis: String, to nodeID: UUID) {
        guard var node = outlineNode(id: nodeID) else { return }
        node.metadata.suggestedSynopsis = synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        updateOutlineNode(node)
    }

    func outlineText(for nodeID: UUID) throws -> String {
        guard let node = outlineNode(id: nodeID), let rootURL else { throw ProjectOutlineError.missingNode }
        return try OutlineTree.filePaths(in: [node]).map { path in
            if path == selectedChapterPath { return text }
            return try WritingProjectDisk.readChapter(path, at: rootURL)
        }.joined(separator: "\n\n")
    }

    func outlineAIContext(for nodeID: UUID) throws -> String {
        guard let node = outlineNode(id: nodeID) else { throw ProjectOutlineError.missingNode }
        let passage = try outlineText(for: nodeID)
        return """
        <outline_item type="\(node.kind.rawValue)" title="\(node.title)">
        \(String(passage.prefix(50_000)))
        </outline_item>

        <project_bible>
        \(String(bibleText.prefix(14_000)))
        </project_bible>
        """
    }

    func fileOrganizationPlan() -> OutlineFileOrganizationPlan? {
        guard let rootURL else { return nil }
        return ProjectFileOrganizer.plan(nodes: outlineNodes, at: rootURL)
    }

    func validateFileOrganizationPlan(_ plan: OutlineFileOrganizationPlan) -> OutlineFileOrganizationPlan {
        guard let rootURL else { return plan }
        return ProjectFileOrganizer.validate(plan, at: rootURL)
    }

    func organizeFiles(_ plan: OutlineFileOrganizationPlan) {
        guard let rootURL else { return }
        saveNow()
        let checked = ProjectFileOrganizer.validate(plan, at: rootURL)
        guard checked.hasChanges, !checked.hasConflicts else {
            if checked.hasConflicts { errorMessage = "Resolve every destination conflict before organizing files." }
            return
        }

        let beforeNodes = outlineNodes
        let beforeSelection = selectedChapterPath
        do {
            for move in checked.includedMoves where move.sourcePath != move.destinationPath {
                let content = try WritingProjectDisk.readChapter(move.sourcePath, at: rootURL)
                if let snapshot = try WritingProjectDisk.createSnapshot(
                    chapterPath: move.sourcePath,
                    content: content,
                    name: nil,
                    reason: "Before organizing files",
                    at: rootURL
                ) {
                    snapshots.insert(snapshot, at: 0)
                }
            }

            let completed = try ProjectFileOrganizer.execute(checked, at: rootURL)
            var afterNodes = beforeNodes
            for move in completed {
                _ = OutlineTree.updatePath(nodeID: move.nodeID, path: move.destinationPath, in: &afterNodes)
            }
            let forwardMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.sourcePath, $0.destinationPath) })
            do {
                try WritingProjectDisk.rewriteSnapshotPaths(forwardMap, at: rootURL)
                outlineNodes = afterNodes
                saveOutlineNow()
                let selectedAfter = beforeSelection.flatMap { forwardMap[$0] } ?? beforeSelection
                preserveUndoForFileRelocation()
                try syncChaptersWithOutline(preferredSelection: selectedAfter)
                snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
                registerFileOrganizationUndo(
                    moves: completed,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes,
                    selectionBefore: beforeSelection,
                    selectionAfter: selectedAfter
                )
                scheduleManuscriptAnalysis(immediately: true)
            } catch {
                try? ProjectFileOrganizer.undo(completed, at: rootURL)
                let reverseMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.destinationPath, $0.sourcePath) })
                try? WritingProjectDisk.rewriteSnapshotPaths(reverseMap, at: rootURL)
                outlineNodes = beforeNodes
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func headingSplitPlan(for nodeID: UUID) throws -> HeadingSplitPlan {
        guard let node = outlineNode(id: nodeID), let rootURL else { throw ProjectOutlineError.missingNode }
        let markdown = node.relativePath == selectedChapterPath
            ? text
            : try WritingProjectDisk.readChapter(node.relativePath ?? "", at: rootURL)
        var plan = try HeadingSplitPlanner.plan(node: node, markdown: markdown)
        let directory = (plan.chapterPath as NSString).deletingLastPathComponent
        var reserved: Set<String> = []
        for index in plan.sections.indices {
            let base = URL(fileURLWithPath: plan.sections[index].fileName).deletingPathExtension().lastPathComponent
            var candidate = "\(base).md"
            var suffix = 2
            func relative(_ file: String) -> String {
                directory == "." ? file : "\(directory)/\(file)"
            }
            while reserved.contains(candidate.lowercased())
                || FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(relative(candidate)).path) {
                candidate = "\(base) \(suffix).md"
                suffix += 1
            }
            plan.sections[index].fileName = candidate
            reserved.insert(candidate.lowercased())
        }
        return plan
    }

    func applyHeadingSplit(_ plan: HeadingSplitPlan) {
        guard let rootURL,
              let manifest,
              let node = outlineNode(id: plan.nodeID) else { return }
        saveNow()
        let included = plan.includedSections
        guard !included.isEmpty else { return }
        let directory = (plan.chapterPath as NSString).deletingLastPathComponent
        func relativePath(_ fileName: String) -> String {
            directory == "." ? fileName : "\(directory)/\(fileName)"
        }
        do {
            var destinations: Set<String> = []
            for section in included {
                guard section.fileName == URL(fileURLWithPath: section.fileName).lastPathComponent,
                      section.fileName.lowercased().hasSuffix(".md"),
                      !section.fileName.contains(":"),
                      section.fileName.lowercased() != ".md" else {
                    throw ProjectOutlineError.invalidDestination(section.fileName)
                }
                let destination = relativePath(section.fileName)
                guard destinations.insert(destination.lowercased()).inserted else {
                    throw ProjectOutlineError.fileConflict(destination)
                }
                guard !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(destination).path) else {
                    throw ProjectOutlineError.fileConflict(destination)
                }
            }

            let original = try WritingProjectDisk.readChapter(plan.chapterPath, at: rootURL)
            if let snapshot = try WritingProjectDisk.createSnapshot(
                chapterPath: plan.chapterPath,
                content: original,
                name: nil,
                reason: "Before splitting headings",
                at: rootURL
            ) {
                snapshots.insert(snapshot, at: 0)
            }
            let beforeNodes = outlineNodes
            var afterNodes = beforeNodes
            var updatedNode = node
            let childKind: OutlineNodeKind = manifest.kind == .fiction ? .scene : .section
            let newChildren = included.map { section in
                var metadata = OutlineNodeMetadata()
                metadata.status = .drafting
                return OutlineNode(
                    title: section.title,
                    kind: childKind,
                    relativePath: relativePath(section.fileName),
                    metadata: metadata
                )
            }
            updatedNode.children.append(contentsOf: newChildren)
            guard OutlineTree.update(updatedNode, in: &afterNodes) else { throw ProjectOutlineError.missingNode }

            var createdPaths: [String] = []
            do {
                try WritingProjectDisk.writeChapter(plan.resultingChapterMarkdown, relativePath: plan.chapterPath, at: rootURL)
                for section in included {
                    let path = relativePath(section.fileName)
                    try section.markdown.write(
                        to: rootURL.appendingPathComponent(path),
                        atomically: true,
                        encoding: .utf8
                    )
                    createdPaths.append(path)
                }
                outlineNodes = afterNodes
                saveOutlineNow()
                try syncChaptersWithOutline(preferredSelection: plan.chapterPath)
                registerHeadingSplitUndo(
                    plan: plan,
                    originalMarkdown: original,
                    createdPaths: createdPaths,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes
                )
                scheduleManuscriptAnalysis(immediately: true)
            } catch {
                try? WritingProjectDisk.writeChapter(original, relativePath: plan.chapterPath, at: rootURL)
                for path in createdPaths { try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(path)) }
                outlineNodes = beforeNodes
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleOutlineSave() {
        outlineSaveTask?.cancel()
        outlineSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveOutlineNow()
        }
    }

    func saveOutlineNow() {
        outlineSaveTask?.cancel()
        guard let rootURL else { return }
        do {
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: outlineNodes), at: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncChaptersWithOutline(preferredSelection: String?) throws {
        guard let rootURL, var updatedManifest = manifest else { return }
        let discovered = try WritingProjectDisk.loadChapters(at: rootURL, manifest: updatedManifest)
        let discoveredPaths = discovered.map(\.relativePath)
        let known = Set(discoveredPaths)
        var ordered = OutlineTree.filePaths(in: outlineNodes).filter(known.contains)
        ordered.append(contentsOf: discoveredPaths.filter { !ordered.contains($0) })
        updatedManifest.chapterOrder = ordered
        let selection = preferredSelection.flatMap { known.contains($0) ? $0 : nil }
            ?? updatedManifest.lastOpenedChapter.flatMap { known.contains($0) ? $0 : nil }
            ?? ordered.first
        updatedManifest.lastOpenedChapter = selection
        try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
        manifest = updatedManifest
        chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: updatedManifest)
        if let selection { try loadChapter(selection) }
    }

    private func registerFileOrganizationUndo(
        moves: [OutlineFileMove],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode],
        selectionBefore: String?,
        selectionAfter: String?
    ) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.undoFileOrganization(
                moves: moves,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes,
                selectionBefore: selectionBefore,
                selectionAfter: selectionAfter
            )
        }
        projectUndoManager?.setActionName("Organize Project Files")
    }

    private func undoFileOrganization(
        moves: [OutlineFileMove],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode],
        selectionBefore: String?,
        selectionAfter: String?
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            try ProjectFileOrganizer.undo(moves, at: rootURL)
            let reverseMap = Dictionary(uniqueKeysWithValues: moves.map { ($0.destinationPath, $0.sourcePath) })
            try WritingProjectDisk.rewriteSnapshotPaths(reverseMap, at: rootURL)
            outlineNodes = beforeNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: beforeNodes), at: rootURL)
            preserveUndoForFileRelocation()
            try syncChaptersWithOutline(preferredSelection: selectionBefore)
            snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
            projectUndoManager?.registerUndo(withTarget: self) { target in
                target.redoFileOrganization(
                    moves: moves,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes,
                    selectionBefore: selectionBefore,
                    selectionAfter: selectionAfter
                )
            }
            projectUndoManager?.setActionName("Organize Project Files")
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func redoFileOrganization(
        moves: [OutlineFileMove],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode],
        selectionBefore: String?,
        selectionAfter: String?
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            let completed = try ProjectFileOrganizer.execute(OutlineFileOrganizationPlan(moves: moves), at: rootURL)
            let forwardMap = Dictionary(uniqueKeysWithValues: completed.map { ($0.sourcePath, $0.destinationPath) })
            try WritingProjectDisk.rewriteSnapshotPaths(forwardMap, at: rootURL)
            outlineNodes = afterNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: afterNodes), at: rootURL)
            preserveUndoForFileRelocation()
            try syncChaptersWithOutline(preferredSelection: selectionAfter)
            snapshots = try WritingProjectDisk.loadSnapshots(at: rootURL)
            registerFileOrganizationUndo(
                moves: moves,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes,
                selectionBefore: selectionBefore,
                selectionAfter: selectionAfter
            )
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func preserveUndoForFileRelocation() {
        preservesUndoAcrossFileRelocation = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.preservesUndoAcrossFileRelocation = false
        }
    }

    private func registerHeadingSplitUndo(
        plan: HeadingSplitPlan,
        originalMarkdown: String,
        createdPaths: [String],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode]
    ) {
        projectUndoManager?.registerUndo(withTarget: self) { target in
            target.undoHeadingSplit(
                plan: plan,
                originalMarkdown: originalMarkdown,
                createdPaths: createdPaths,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes
            )
        }
        projectUndoManager?.setActionName("Split Chapter Headings")
    }

    private func undoHeadingSplit(
        plan: HeadingSplitPlan,
        originalMarkdown: String,
        createdPaths: [String],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode]
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            guard try WritingProjectDisk.readChapter(plan.chapterPath, at: rootURL) == plan.resultingChapterMarkdown else {
                throw ProjectOutlineError.filesChanged
            }
            for (path, section) in zip(createdPaths, plan.includedSections) {
                guard try WritingProjectDisk.readChapter(path, at: rootURL) == section.markdown else {
                    throw ProjectOutlineError.filesChanged
                }
            }
            try WritingProjectDisk.writeChapter(originalMarkdown, relativePath: plan.chapterPath, at: rootURL)
            for path in createdPaths { try FileManager.default.removeItem(at: rootURL.appendingPathComponent(path)) }
            outlineNodes = beforeNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: beforeNodes), at: rootURL)
            try syncChaptersWithOutline(preferredSelection: plan.chapterPath)
            projectUndoManager?.registerUndo(withTarget: self) { target in
                target.redoHeadingSplit(
                    plan: plan,
                    originalMarkdown: originalMarkdown,
                    createdPaths: createdPaths,
                    beforeNodes: beforeNodes,
                    afterNodes: afterNodes
                )
            }
            projectUndoManager?.setActionName("Split Chapter Headings")
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func redoHeadingSplit(
        plan: HeadingSplitPlan,
        originalMarkdown: String,
        createdPaths: [String],
        beforeNodes: [OutlineNode],
        afterNodes: [OutlineNode]
    ) {
        guard let rootURL else { return }
        do {
            saveNow()
            guard try WritingProjectDisk.readChapter(plan.chapterPath, at: rootURL) == originalMarkdown,
                  createdPaths.allSatisfy({ !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent($0).path) }) else {
                throw ProjectOutlineError.filesChanged
            }
            try WritingProjectDisk.writeChapter(plan.resultingChapterMarkdown, relativePath: plan.chapterPath, at: rootURL)
            for (path, section) in zip(createdPaths, plan.includedSections) {
                try section.markdown.write(to: rootURL.appendingPathComponent(path), atomically: true, encoding: .utf8)
            }
            outlineNodes = afterNodes
            try ProjectOutlineDisk.save(ProjectOutlineArchive(nodes: afterNodes), at: rootURL)
            try syncChaptersWithOutline(preferredSelection: plan.chapterPath)
            registerHeadingSplitUndo(
                plan: plan,
                originalMarkdown: originalMarkdown,
                createdPaths: createdPaths,
                beforeNodes: beforeNodes,
                afterNodes: afterNodes
            )
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
