import SwiftUI

/// Enforces a single editor-owned sheet at a time. A stale dismissal from an
/// outgoing sheet cannot clear a newer presentation request.
@MainActor
final class EditorWorkspacePresentation: ObservableObject {
    enum Sheet: String, CaseIterable, Identifiable {
        case referenceLibrary
        case researchLibrary
        case projectResearch
        case revisionCenter
        case projectPolish
        case destinker
        case publishExport
        case projectImportAssistant
        case welcome
        case whatsNew
        case englishPackPrompt
        case draftRecovery
        case newChapter
        case styleEditor
        case revisionHistory
        case manuscriptInsights
        case projectOrganization
        case namedSnapshot
        case toneRequest
        case writingGrowth

        var id: String { rawValue }
    }

    @Published private(set) var activeSheet: Sheet?

    func present(_ sheet: Sheet) {
        activeSheet = sheet
    }

    func dismiss(_ sheet: Sheet) {
        guard activeSheet == sheet else { return }
        activeSheet = nil
    }

    func isPresenting(_ sheet: Sheet) -> Bool {
        activeSheet == sheet
    }

    func binding(for sheet: Sheet) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.activeSheet == sheet },
            set: { [weak self] isPresented in
                guard let self else { return }
                if isPresented {
                    self.present(sheet)
                } else {
                    self.dismiss(sheet)
                }
            }
        )
    }
}
