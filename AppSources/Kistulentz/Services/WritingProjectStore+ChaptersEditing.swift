import Foundation

extension WritingProjectStore {

    // MARK: - Chapters & Editing

    func updateText(_ newValue: String) {
        guard isOpen, newValue != text else { return }
        text = newValue
        isDirty = true
        updateSelectedChapterStatistics()
        editCoordinator.editLanded(.liveTyping)
    }

    func saveNow() {
        guard isDirty,
              let rootURL,
              let selectedChapterPath else { return }
        do {
            try WritingProjectDisk.writeChapter(text, relativePath: selectedChapterPath, at: rootURL)
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectChapter(_ relativePath: String) {
        guard relativePath != selectedChapterPath else { return }
        do {
            saveNow()
            try loadChapter(relativePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createChapter(named name: String) {
        guard let rootURL else { return }
        do {
            saveNow()
            let path = try WritingProjectDisk.createChapter(named: name, at: rootURL)
            var updatedManifest = manifest
            updatedManifest?.chapterOrder.append(path)
            if let updatedManifest {
                try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
                manifest = updatedManifest
            }
            chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: manifest!)
            let nodeTitle = chapters.first(where: { $0.relativePath == path })?.title
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let node = OutlineNode(title: nodeTitle, kind: .chapter, relativePath: path)
            _ = OutlineTree.append(node, to: nil, in: &outlineNodes)
            saveOutlineNow()
            try loadChapter(path)
            editCoordinator.editLanded(.externalChange)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveChapters(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = chapters
        let moving = fromOffsets.sorted().map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) { reordered.remove(at: index) }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = max(0, min(reordered.count, toOffset - removedBeforeDestination))
        reordered.insert(contentsOf: moving, at: destination)
        chapters = reordered
        let flatOutline = outlineNodes.allSatisfy { $0.relativePath != nil && $0.children.isEmpty }
        if flatOutline {
            let byPath = Dictionary(uniqueKeysWithValues: outlineNodes.compactMap { node in
                node.relativePath.map { ($0, node) }
            })
            let reorderedOutline = chapters.compactMap { byPath[$0.relativePath] }
            if reorderedOutline.count == outlineNodes.count {
                outlineNodes = reorderedOutline
                saveOutlineNow()
            }
        }
        persistChapterOrder()
    }

    func loadChapter(_ relativePath: String?) throws {
        guard let relativePath,
              chapters.contains(where: { $0.relativePath == relativePath }),
              let rootURL else { throw WritingProjectError.noMarkdownFiles }
        selectedChapterPath = relativePath
        text = try WritingProjectDisk.readChapter(relativePath, at: rootURL)
        isDirty = false
        editCoordinator.resetEditingBaseline()
        var updatedManifest = manifest
        updatedManifest?.lastOpenedChapter = relativePath
        if let updatedManifest {
            try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
            manifest = updatedManifest
        }
    }

    func updateSelectedChapterStatistics() {
        guard let selectedChapterPath,
              let index = chapters.firstIndex(where: { $0.relativePath == selectedChapterPath }) else { return }
        let fallback = URL(fileURLWithPath: selectedChapterPath).deletingPathExtension().lastPathComponent
        let title = text.components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") })?
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(2)
        chapters[index] = ProjectChapter(
            relativePath: selectedChapterPath,
            title: title.map(String.init).flatMap { $0.isEmpty ? nil : $0 } ?? fallback,
            wordCount: WritingProjectDisk.wordCount(in: text)
        )
    }

    private func persistChapterOrder() {
        guard let rootURL else { return }
        do {
            var updatedManifest = manifest
            updatedManifest?.chapterOrder = chapters.map(\.relativePath)
            if let updatedManifest {
                try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
                manifest = updatedManifest
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
