import Foundation

extension WritingProjectStore {

    // MARK: - Snapshots

    func createSnapshot(name: String?, reason: String) {
        guard let rootURL, let selectedChapterPath else { return }
        do {
            if let snapshot = try WritingProjectDisk.createSnapshot(
                chapterPath: selectedChapterPath,
                content: text,
                name: name,
                reason: reason,
                at: rootURL
            ) {
                snapshots.insert(snapshot, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareForProgrammaticEdit(reason: String) {
        createSnapshot(name: nil, reason: reason)
        hasCapturedEditingBaseline = true
    }

    func content(for snapshot: ProjectSnapshot) throws -> String {
        guard let rootURL else { return "" }
        return try WritingProjectDisk.snapshotContent(snapshot, at: rootURL)
    }

    func currentContent(for chapterPath: String) throws -> String {
        if chapterPath == ManuscriptProjectDisk.bibleFileName { return bibleText }
        if chapterPath == ManuscriptProjectDisk.reportFileName { return manuscriptReportText }
        if chapterPath == selectedChapterPath { return text }
        guard let rootURL else { return "" }
        return try WritingProjectDisk.readChapter(chapterPath, at: rootURL)
    }

    func restore(_ snapshot: ProjectSnapshot) {
        guard let rootURL else { return }
        do {
            if snapshot.chapterPath == ManuscriptProjectDisk.bibleFileName {
                let restored = try WritingProjectDisk.snapshotContent(snapshot, at: rootURL)
                applyBibleUpdate(
                    restored,
                    reason: "Before restoring \(snapshot.name)",
                    summary: "Restored Bible snapshot “\(snapshot.name)”.",
                    forceSnapshot: true
                )
                return
            }
            if selectedChapterPath != snapshot.chapterPath {
                saveNow()
                try loadChapter(snapshot.chapterPath)
            }
            createSnapshot(name: nil, reason: "Before restoring \(snapshot.name)")
            let restored = try WritingProjectDisk.snapshotContent(snapshot, at: rootURL)
            text = restored
            isDirty = true
            hasCapturedEditingBaseline = true
            updateSelectedChapterStatistics()
            saveNow()
            scheduleManuscriptAnalysis(immediately: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
