import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReferenceLibraryView: View {
    @EnvironmentObject private var library: ReferenceLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedChoiceIDs: Set<String>
    let onUseReference: (EPUBReference) -> Void

    @State private var kind: LibraryReferenceKind = .book
    @State private var search = ""
    @State private var focusedBookID: UUID?
    @State private var pendingAIRequest: AIRequestPreview?

    var body: some View {
        Group {
            if library.rootURL == nil {
                welcome
            } else {
                libraryWorkspace
            }
        }
        .frame(minWidth: 880, minHeight: 610)
        .alert("Reference Library", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
        .sheet(item: $pendingAIRequest) { preview in
            AIRequestPreviewView(preview: preview) { confirmed in
                pendingAIRequest = nil
                library.deepen(
                    choiceIDs: selectedChoiceIDs,
                    settings: settings,
                    preparedInput: confirmed.input
                )
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Create a Reference Library", systemImage: "books.vertical.fill")
        } description: {
            Text("Choose a folder for Kistulentz’s Markdown knowledge base. EPUB analysis remains local unless you explicitly choose Deepen w/ AI.")
        } actions: {
            Button("Choose Library Folder", action: chooseLibraryFolder)
                .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
        }
    }

    private var libraryWorkspace: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                choicesPane
                    .frame(minWidth: 300, idealWidth: 330, maxWidth: 400)

                detailPane
                    .frame(minWidth: 520)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reference Library")
                    .font(.title3.weight(.semibold))
                Text(library.rootURL?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()

            if library.isSaving {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Saving Markdown…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Menu {
                Button("Add EPUB Files…", action: addEPUBFiles)
                Button("Add EPUB Folder…", action: addEPUBFolder)
                Divider()
                Button("Choose Different Library Folder…", action: chooseLibraryFolder)
            } label: {
                Label("Import", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var choicesPane: some View {
        VStack(spacing: 0) {
            Picker("Profile type", selection: $kind) {
                ForEach(LibraryReferenceKind.allCases) { value in
                    Label(value.title, systemImage: value.systemImage).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            TextField("Search \(kind.title.lowercased())", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Divider()

            List {
                ForEach(library.choices(kind: kind, search: search)) { choice in
                    Button {
                        toggle(choice)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedChoiceIDs.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedChoiceIDs.contains(choice.id) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.title)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(choice.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Text("\(selectedChoiceIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    selectedChoiceIDs.removeAll()
                    focusedBookID = nil
                }
                .buttonStyle(.borderless)
                .disabled(selectedChoiceIDs.isEmpty)
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statistics

                if library.isImporting {
                    importProgress
                }

                selectionActions

                if let focusedBookID, let book = library.book(id: focusedBookID) {
                    BookMetadataEditor(book: book)
                        .environmentObject(library)
                        .id(book.id)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Manual corrections", systemImage: "pencil")
                            .font(.headline)
                        Text("Choose the Books tab and select a single book to correct its title, author, or genres inside Kistulentz.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }

                if !library.importFailures.isEmpty {
                    DisclosureGroup("\(library.importFailures.count) files could not be imported") {
                        ForEach(library.importFailures, id: \.self) { failure in
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                        }
                    }
                    .foregroundStyle(Color.orange)
                }
            }
            .padding(18)
        }
    }

    private var statistics: some View {
        HStack(spacing: 0) {
            LibraryStat(value: "\(library.books.count)", label: "BOOKS")
            LibraryStat(value: "\(library.authorsCount)", label: "AUTHORS")
            LibraryStat(value: "\(library.genresCount)", label: "GENRES")
            LibraryStat(value: "\(library.insights.count)", label: "AI INSIGHTS")
        }
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var importProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView(value: Double(library.importCompleted), total: Double(max(library.importTotal, 1)))
                Text("\(library.importCompleted)/\(library.importTotal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel", action: library.cancelImport)
                    .controlSize(.small)
            }
            Text(library.currentImportName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectionActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use combined references")
                        .font(.headline)
                    Text("Overlapping book, author, and genre selections are deduplicated automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let reference = library.reference(for: selectedChoiceIDs) {
                        onUseReference(reference)
                        dismiss()
                    }
                } label: {
                    Label("Use Selected", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedChoiceIDs.isEmpty)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optional provider analysis")
                        .font(.callout.weight(.semibold))
                    Text(settings.provider.isLocal
                        ? "Deepen uses the selected Ollama model on this Mac. You will preview the combined profile and excerpts first."
                        : "Local import never calls a provider. You will preview the combined profile and selected short excerpts before Deepen sends them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    prepareDeepeningPreview()
                } label: {
                    if library.isDeepening {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Deepen w/ AI", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(selectedChoiceIDs.isEmpty || library.isDeepening)

                Button("Open Markdown", action: library.openKnowledgeBase)
                    .buttonStyle(.bordered)
                    .disabled(library.isSaving)
            }
        }
        .padding(14)
        .background(Color.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggle(_ choice: LibraryReferenceChoice) {
        if selectedChoiceIDs.contains(choice.id) {
            selectedChoiceIDs.remove(choice.id)
        } else {
            selectedChoiceIDs.insert(choice.id)
        }
        if choice.kind == .book, let id = choice.bookIDs.first {
            focusedBookID = id
        } else {
            focusedBookID = nil
        }
    }

    private func prepareDeepeningPreview() {
        let provider = settings.provider
        guard settings.isProviderReady(provider) else {
            library.errorMessage = provider.requiresAPIKey
                ? "Add your \(provider.title) API key and choose a model in Settings first."
                : "Open Settings, detect the Ollama models already on this Mac, and choose one first."
            return
        }
        guard let reference = library.reference(for: selectedChoiceIDs) else {
            library.errorMessage = "Select at least one book, author, or genre to deepen."
            return
        }
        pendingAIRequest = AIRequestPreview(
            purpose: .referenceDeepening,
            provider: provider,
            model: settings.model(for: provider),
            primaryLabel: "Combined profile and selected excerpts",
            primaryText: ReferenceDeepeningService.input(for: reference),
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: nil,
            sourceText: nil
        )
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Reference Library Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            library.setLocation(url)
        }
    }

    private func addEPUBFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add EPUB Files"
        panel.prompt = "Import"
        panel.allowedContentTypes = [UTType(importedAs: "org.idpf.epub-container")]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            library.importEPUBs(from: panel.urls)
        }
    }

    private func addEPUBFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add a Folder of EPUB Files"
        panel.prompt = "Scan Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            library.importEPUBs(from: panel.urls)
        }
    }
}

private struct LibraryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BookMetadataEditor: View {
    @EnvironmentObject private var library: ReferenceLibraryStore

    let book: LibraryBook
    @State private var title: String
    @State private var author: String
    @State private var genres: String

    init(book: LibraryBook) {
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _genres = State(initialValue: book.genres.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Correct book metadata", systemImage: "pencil")
                    .font(.headline)
                Spacer()
                Button("Save Corrections") {
                    library.updateBook(
                        id: book.id,
                        title: title,
                        author: author,
                        genres: genres.components(separatedBy: ",")
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            LabeledContent("Title") {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Author") {
                TextField("Author", text: $author)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Genres") {
                TextField("Comma-separated genres", text: $genres)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Local profile")
                    .font(.caption.weight(.semibold))
                Text("\(book.profile.voice), \(book.profile.tempo), grade \(book.profile.gradeLevel.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(book.excerpts.count) short attributed excerpts retained in the Markdown knowledge base.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
