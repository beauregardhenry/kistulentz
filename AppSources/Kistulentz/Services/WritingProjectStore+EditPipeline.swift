import Foundation

extension WritingProjectStore: ManuscriptEditPipelineHost {

    // MARK: - ManuscriptEditPipelineHost

    func snapshotBeforeEdit(reason: String) {
        createSnapshot(name: nil, reason: reason)
    }

    func snapshotBibleBeforeEdit(reason: String) {
        createBibleSnapshot(content: bibleText, reason: reason)
    }

    func persistCurrentChapter() {
        saveNow()
    }

    func persistBible() {
        saveBibleNow()
    }
}
