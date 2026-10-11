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
            onDidSaveChapter?("\(rootURL.path)#\(selectedChapterPath)", WritingProjectDisk.wordCount(in: text))
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
        // `manifest` is guarded alongside `rootURL` here (not just `rootURL` alone) so the
        // load below never needs to force-unwrap it: `rootURL` and `manifest` are always set and
        // cleared together by `install`/`closeProject`, but nothing in the type system enforces
        // that invariant, so a future change to either could otherwise turn this into a crash.
        guard let rootURL, var updatedManifest = manifest else { return }
        do {
            saveNow()
            let path = try WritingProjectDisk.createChapter(named: name, at: rootURL)
            updatedManifest.chapterOrder.append(path)
            try WritingProjectDisk.saveManifest(updatedManifest, at: rootURL)
            manifest = updatedManifest
            chapters = try WritingProjectDisk.loadChapters(at: rootURL, manifest: updatedManifest)
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

}
