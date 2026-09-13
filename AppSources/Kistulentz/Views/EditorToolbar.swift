import SwiftUI

struct EditorToolbarActions {
    let chooseDocumentForImport: () -> Void
    let showProjectImportAssistant: () -> Void
    let createProject: () -> Void
    let openProject: () -> Void
    let showNewChapter: () -> Void
    let showStyleEditor: () -> Void
    let showNamedSnapshot: () -> Void
    let showRevisionHistory: () -> Void
    let showManuscriptInsights: () -> Void
    let presentDestinker: () -> Void
    let showProjectOrganization: () -> Void
    let showProjectResearch: () -> Void
    let showProjectPolish: () -> Void
    let showRevisionCenter: () -> Void
    let showPublishExport: () -> Void
    let closeProject: () -> Void
    let showToneRequest: () -> Void
    let prepareRewrite: (SelectionRewriteGoal) -> Void
    let showResearchLibrary: () -> Void
    let showReferenceLibrary: () -> Void
    let showReferenceImporter: () -> Void
    let runReview: () -> Void
}

struct EditorToolbar: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var projectStore: WritingProjectStore
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isWriteMode: Bool
    let activeFileURL: URL?
    let isImportingDocument: Bool
    let hasSelectedPassage: Bool
    let actions: EditorToolbarActions

    var body: some View {
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

            Menu {
                Button {
                    actions.chooseDocumentForImport()
                } label: {
                    Label("Import Document…", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(isImportingDocument)

                Button {
                    actions.showProjectImportAssistant()
                } label: {
                    Label("Project Import Assistant…", systemImage: "square.stack.3d.up.badge.a")
                }

                Divider()

                Button {
                    actions.createProject()
                } label: {
                    Label("New Project…", systemImage: "folder.badge.plus")
                }
                Button {
                    actions.openProject()
                } label: {
                    Label("Open Project…", systemImage: "folder")
                }

                if projectStore.isOpen {
                    Divider()
                    Button("New Chapter…") { actions.showNewChapter() }
                    Button("Edit Kistulentz Style…") { actions.showStyleEditor() }
                    Button("Create Snapshot…") { actions.showNamedSnapshot() }
                    Button("Revision History…") { actions.showRevisionHistory() }
                    Button("Manuscript Insights…") { actions.showManuscriptInsights() }
                    Button("De-stink Review…") { actions.presentDestinker() }
                    Button("Project Organization…") { actions.showProjectOrganization() }
                    Button("Project Research…") { actions.showProjectResearch() }
                    Button("Polish Project…") { actions.showProjectPolish() }
                    Button("Systemic Revision Center…") { actions.showRevisionCenter() }
                    Button("Publish & Export…") { actions.showPublishExport() }
                    Divider()
                    Button("Close Project", action: actions.closeProject)
                }
            } label: {
                if isImportingDocument {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: projectStore.isOpen ? "folder.fill" : "folder")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(projectStore.isOpen ? projectStore.projectName : "Projects")
            .accessibilityLabel(projectStore.isOpen ? "Project: \(projectStore.projectName)" : "Projects")

            VStack(alignment: .leading, spacing: 1) {
                Text(activeFileURL?.lastPathComponent ?? "Untitled.md")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(projectStore.isOpen
                    ? "\(projectStore.projectName) · \(projectStore.projectKind?.title ?? "Project")"
                    : "Markdown document")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    isWriteMode.toggle()
                } label: {
                    Label(isWriteMode ? "Exit Write Mode" : "Enter Write Mode", systemImage: isWriteMode ? "sidebar.left" : "text.page")
                }
                Divider()
                Text("Visible highlights")
                ForEach(IssueCategory.allCases) { category in
                    Button {
                        settings.toggleHighlight(category)
                    } label: {
                        if settings.isHighlightVisible(category) {
                            Label(category.title, systemImage: "checkmark")
                        } else {
                            Text(category.title)
                        }
                    }
                }
            } label: {
                Image(systemName: isWriteMode ? "text.page.fill" : "highlighter")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(isWriteMode ? "Exit Write Mode" : "Writing view and highlights")
            .accessibilityLabel(isWriteMode ? "Exit Write Mode" : "Writing view and highlights")

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
                ForEach(SelectionRewriteKind.allCases) { kind in
                    Button {
                        if kind == .adjustTone {
                            actions.showToneRequest()
                        } else {
                            actions.prepareRewrite(SelectionRewriteGoal(kind: kind, requestedTone: nil))
                        }
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                    .disabled(kind == .matchReferences && viewModel.referenceBook == nil)
                }
            } label: {
                if viewModel.isRewriting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Rewrite", systemImage: "text.badge.star")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!hasSelectedPassage || viewModel.isRewriting)
            .help(!hasSelectedPassage ? "Select a passage to rewrite" : "Rewrite the selected passage")

            Button {
                actions.presentDestinker()
            } label: {
                Label("De-stink", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            // Every other icon control in this toolbar is a Menu styled .borderlessButton, which
            // macOS tints in the accent color by default; a plain Button's .borderless style does
            // not pick that up on its own and renders in the muted label color instead, standing
            // out against its siblings. This is the only single-action (non-menu) control in the
            // row, so it needs its tint set explicitly to match.
            .tint(.accentColor)
            .help("Check this prose locally for stock phrasing and structural writing tics")

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
                    actions.showResearchLibrary()
                } label: {
                    Label("Research Library…", systemImage: "doc.text.magnifyingglass")
                }
                if projectStore.isOpen {
                    Button {
                        actions.showProjectResearch()
                    } label: {
                        Label("Project Research & Citations…", systemImage: "quote.opening")
                    }
                }
                Divider()
                Button {
                    actions.showReferenceLibrary()
                } label: {
                    Label("Reference Library…", systemImage: "books.vertical.fill")
                }
                Button {
                    actions.showReferenceImporter()
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
            .accessibilityIdentifier("ReferenceMenu")
            .accessibilityValue(viewModel.referenceBook?.title ?? "No reference selected")

            Button(action: actions.runReview) {
                if viewModel.isReviewing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Polish", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isReviewing)
            .help(settings.isProviderReady(settings.provider)
                ? "Review with \(settings.provider.title) (⇧⌘R)"
                : "Polish locally on this Mac (⇧⌘R)")
        }
        .padding(.horizontal, 16)
        .frame(height: 55)
    }
}
