import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResearchLibraryView: View {
    @EnvironmentObject private var store: ResearchLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSourceID: UUID?
    @State private var draft: ResearchSource?
    @State private var showingRecordImporter = false
    @State private var showingAttachmentImporter = false
    @State private var showingLookup = false
    @State private var attachmentStorage = ResearchAttachmentStorage.managedCopy
    @State private var pendingDeletion: ResearchSource?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Research Library").font(.title2.bold())
                    Text(store.rootURL?.path ?? "Choose a folder to keep the shared library")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Choose Folder…") { Task { await chooseLibraryFolder() } }
                if store.rootURL != nil {
                    Button("Show Markdown") { store.revealKnowledgeBase() }
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close Research Library")
                    .help("Close the Research Library without changing its folder")
            }
            .padding()
            Divider()

            if store.rootURL == nil {
                ContentUnavailableView {
                    Label("Choose a Research Library", systemImage: "books.vertical")
                } description: {
                    Text("Kistulentz keeps citation records, managed attachments, and local text indexes in a folder you choose.")
                } actions: {
                    Button("Choose Folder…") { Task { await chooseLibraryFolder() } }
                        .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                }
            } else {
                HSplitView {
                    sourceList
                        .frame(minWidth: 245, idealWidth: 285)
                    if let source = draft {
                        ResearchSourceEditor(
                            source: Binding(get: { source }, set: { draft = $0 }),
                            attachmentStorage: $attachmentStorage,
                            isIndexing: { store.indexingAttachmentIDs.contains($0) },
                            onSave: saveDraft,
                            onAddAttachment: { showingAttachmentImporter = true },
                            onRemoveAttachment: { attachment in
                                do {
                                    try store.removeAttachment(attachment.id, sourceID: source.id)
                                    select(source.id)
                                } catch { store.errorMessage = error.localizedDescription }
                            },
                            onOpenAttachment: { attachment in
                                if let url = store.attachmentURL(attachment) { NSWorkspace.shared.open(url) }
                            }
                        )
                        .id(source.id)
                        .frame(minWidth: 540)
                    } else {
                        ContentUnavailableView("Select a Source", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .onExitCommand { dismiss() }
        .fileImporter(isPresented: $showingRecordImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() { _ = try store.importSources(from: url) }
                if selectedSourceID == nil { select(store.sources.first?.id) }
            } catch { store.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingAttachmentImporter, allowedContentTypes: [.data, .image, .pdf, .plainText], allowsMultipleSelection: true) { result in
            guard let sourceID = selectedSourceID else { return }
            do {
                for url in try result.get() {
                    Task { await store.addAttachment(from: url, sourceID: sourceID, storage: attachmentStorage); select(sourceID) }
                }
            } catch { store.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showingLookup) {
            ResearchMetadataLookupView { source in
                do {
                    let id = try store.addSource(source)
                    select(id)
                } catch { store.errorMessage = error.localizedDescription }
            }
            .environmentObject(store)
        }
        .alert("Remove source?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Remove", role: .destructive) {
                guard let id = pendingDeletion?.id else { return }
                do { try store.removeSource(id); select(store.sources.first?.id) }
                catch { store.errorMessage = error.localizedDescription }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Managed attachment copies and their local indexes will also be removed. Linked originals will not be deleted.")
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "") }
    }

    @MainActor
    private func chooseLibraryFolder() async {
        guard let url = await MacFilePanel.chooseFolder(startingAt: store.rootURL) else { return }
        do {
            try store.open(at: url)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private var sourceList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search sources and indexed text", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    Button("Manual Source") { addManualSource() }
                    Button("Look Up DOI or ISBN…") { showingLookup = true }
                    Button("Import BibTeX, RIS, or CSL-JSON…") { showingRecordImporter = true }
                    Divider()
                    Button("Export All as BibTeX…") { export(format: "bib") }
                    Button("Export All as RIS…") { export(format: "ris") }
                    Button("Export All as CSL-JSON…") { export(format: "json") }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Add, look up, import, or export research sources")
            }
            .padding(10)
            List(selection: $selectedSourceID) {
                ForEach(store.filteredSources) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title).lineLimit(2)
                        Text("\(source.primaryCreatorName) · \(source.issuedYear.map(String.init) ?? "n.d.") · @\(source.citeKey)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(source.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) { pendingDeletion = source }
                    }
                }
            }
            .onChange(of: selectedSourceID) { _, value in select(value) }
        }
    }

    private func select(_ id: UUID?) {
        selectedSourceID = id
        draft = store.sources.first { $0.id == id }
    }

    private func addManualSource() {
        do {
            let id = try store.addSource()
            select(id)
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func saveDraft() {
        guard let draft else { return }
        do { try store.updateSource(draft); select(draft.id) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func export(format: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Kistulentz Research Library.\(format)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(store.sources, format: format, to: url) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct ResearchSourceEditor: View {
    @Binding var source: ResearchSource
    @Binding var attachmentStorage: ResearchAttachmentStorage
    let isIndexing: (UUID) -> Bool
    let onSave: () -> Void
    let onAddAttachment: () -> Void
    let onRemoveAttachment: (ResearchAttachment) -> Void
    let onOpenAttachment: (ResearchAttachment) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Source Record").font(.headline)
                Spacer()
                Button("Save Changes", action: onSave).buttonStyle(.borderedProminent)
            }.padding()
            Divider()
            Form {
                Section("Identity") {
                    TextField("Title", text: $source.title)
                    TextField("Subtitle", text: $source.subtitle)
                    Picker("Type", selection: $source.type) {
                        ForEach(ResearchSourceType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Citation key", text: $source.citeKey)
                }
                Section("Creators") {
                    ForEach($source.creators) { $creator in
                        HStack {
                            Picker("", selection: $creator.role) {
                                ForEach(ResearchCreatorRole.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 105)
                            TextField("Given", text: $creator.givenName)
                            TextField("Family", text: $creator.familyName)
                            TextField("Organization or literal name", text: $creator.literalName)
                            Button(role: .destructive) {
                                source.creators.removeAll { $0.id == creator.id }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove creator")
                        }
                    }
                    Button("Add Creator") { source.creators.append(ResearchCreator()) }
                }
                Section("Publication") {
                    HStack {
                        TextField("Year", value: $source.issuedYear, format: .number).frame(width: 110)
                        TextField("Full date", text: $source.issuedDate)
                    }
                    TextField("Container or journal", text: $source.containerTitle)
                    TextField("Publisher", text: $source.publisher)
                    TextField("Place", text: $source.publisherPlace)
                    HStack {
                        TextField("Volume", text: $source.volume)
                        TextField("Issue", text: $source.issue)
                        TextField("Edition", text: $source.edition)
                        TextField("Pages", text: $source.pages)
                    }
                    TextField("DOI", text: $source.DOI)
                    TextField("ISBN", text: $source.ISBN)
                    TextField("URL", text: $source.URLString)
                }
                Section("Notes") {
                    TextField("Keywords, separated by commas", text: Binding(
                        get: { source.keywords.joined(separator: ", ") },
                        set: { source.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                    ))
                    TextEditor(text: $source.abstract).frame(minHeight: 70)
                    TextEditor(text: $source.libraryNotes).frame(minHeight: 90)
                }
                Section("Attachments") {
                    Picker("When adding files", selection: $attachmentStorage) {
                        ForEach(ResearchAttachmentStorage.allCases) { Text($0.title).tag($0) }
                    }
                    ForEach(source.attachments) { attachment in
                        HStack {
                            Image(systemName: "paperclip")
                            VStack(alignment: .leading) {
                                Text(attachment.displayName)
                                Text(isIndexing(attachment.id) ? "Indexing locally…" : attachment.extractionStatus.title)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open") { onOpenAttachment(attachment) }
                            Button(role: .destructive) { onRemoveAttachment(attachment) } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Remove \(attachment.displayName)")
                        }
                    }
                    Button("Add PDF, EPUB, Web Archive, Image, or Text…", action: onAddAttachment)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ResearchMetadataLookupView: View {
    @EnvironmentObject private var store: ResearchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let onUse: (ResearchSource) -> Void
    @State private var kind = "DOI"
    @State private var identifier = ""
    @State private var result: ResearchSource?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Look Up Source Metadata").font(.title2.bold())
            Text("This explicit command contacts Crossref for DOI records or Open Library for ISBN records. It does not send manuscript text or attachments.")
                .foregroundStyle(.secondary)
            Picker("Identifier", selection: $kind) {
                Text("DOI").tag("DOI")
                Text("ISBN").tag("ISBN")
            }.pickerStyle(.segmented)
            TextField(kind == "DOI" ? "10.…" : "ISBN", text: $identifier)
            if let result {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).font(.headline)
                        Text("\(result.primaryCreatorName) · \(result.issuedYear.map(String.init) ?? "n.d.")")
                        Text("@\(result.citeKey)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Look Up") { lookup() }.disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLookingUpMetadata)
                Button("Add to Library") {
                    if let result { onUse(result); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(result == nil)
            }
        }
        .padding(22).frame(width: 520)
    }

    private func lookup() {
        Task {
            do {
                result = kind == "DOI" ? try await store.lookupDOI(identifier) : try await store.lookupISBN(identifier)
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct ProjectResearchView: View {
    @ObservedObject var projectStore: WritingProjectStore
    @ObservedObject var researchStore: ProjectResearchStore
    @EnvironmentObject private var library: ResearchLibraryStore
    @Environment(\.dismiss) private var dismiss
    let selectionText: String?
    let onInsertCitation: (ResearchSource, String) -> Void
    @State private var selectedSourceID: UUID?
    @State private var locator = ""
    @State private var search = ""
    @State private var quotation = ""
    @State private var note = ""
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project Research").font(.title2.bold())
                Spacer()
                Picker("Citation style", selection: Binding(
                    get: { researchStore.projectBibliography.style },
                    set: { researchStore.setBibliographyStyle($0) }
                )) {
                    ForEach(BibliographyStyle.allCases) { Text($0.title).tag($0) }
                }.frame(width: 245)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            Divider()
            if library.rootURL == nil {
                ContentUnavailableView("Research Library Not Set", systemImage: "books.vertical", description: Text("Open the global Research Library and choose its folder first."))
            } else {
                Picker("Section", selection: $tab) {
                    Text("Sources & Citations").tag(0)
                    Text("Quotations & Claims").tag(1)
                    Text("Research Notes").tag(2)
                }.pickerStyle(.segmented).padding()
                switch tab {
                case 0: sourcesAndCitations
                case 1: quotationsAndClaims
                default: notesEditor
                }
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    private var projectSources: [ResearchSource] { researchStore.projectSources(in: library) }

    private var sourcesAndCitations: some View {
        HSplitView {
            VStack(spacing: 8) {
                TextField("Search shared library", text: $search).textFieldStyle(.roundedBorder).padding([.horizontal, .top])
                List(selection: $selectedSourceID) {
                    Section("In This Project") {
                        ForEach(projectSources) { source in
                            sourceRow(source).tag(source.id).contextMenu {
                                Button("Remove from Project", role: .destructive) { researchStore.removeResearchSource(source.id) }
                            }
                        }
                    }
                    Section("Shared Library") {
                        ForEach(availableSources) { source in
                            HStack {
                                sourceRow(source)
                                Spacer()
                                Button("Add") { researchStore.addResearchSource(source.id) }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }.frame(minWidth: 300)
            VStack(alignment: .leading, spacing: 14) {
                if let source = projectSources.first(where: { $0.id == selectedSourceID }) {
                    Text(source.title).font(.title3.bold())
                    Text(source.primaryCreatorName).foregroundStyle(.secondary)
                    TextField("Locator, such as p. 31", text: $locator)
                    Text(CitationFormatter.markdownCitation(for: source, locator: locator))
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Button("Insert Citation at Cursor") { onInsertCitation(source, locator); dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("Select a project source to insert its Markdown citation.").foregroundStyle(.secondary)
                }
                Divider()
                Text("Bibliography Preview").font(.headline)
                ScrollView {
                    Text(CitationFormatter.bibliography(projectSources, style: researchStore.projectBibliography.style))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding().frame(minWidth: 470)
        }
    }

    private var quotationsAndClaims: some View {
        HSplitView {
            List(projectSources, selection: $selectedSourceID) { source in sourceRow(source).tag(source.id) }
                .frame(minWidth: 260)
            VStack(alignment: .leading, spacing: 12) {
                Text("Project-specific evidence").font(.headline)
                TextEditor(text: $quotation).frame(minHeight: 90).overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
                TextField("Locator", text: $locator)
                TextField("Note", text: $note)
                HStack {
                    Button("Save as Quotation") {
                        if let id = selectedSourceID { researchStore.addQuotation(sourceID: id, text: quotation, locator: locator, note: note); quotation = ""; note = "" }
                    }
                    Button("Link Selected Manuscript Claim") {
                        if let id = selectedSourceID, let selectionText, let path = projectStore.selectedChapterPath {
                            researchStore.addClaimLink(sourceID: id, chapterPath: path, excerpt: selectionText, locator: locator, note: note)
                        }
                    }.disabled(selectionText == nil)
                }
                Divider()
                List {
                    Section("Quotations") {
                        ForEach(researchStore.projectBibliography.quotations) { item in
                            VStack(alignment: .leading) { Text("“\(item.text)”"); Text(item.locator).font(.caption).foregroundStyle(.secondary) }
                                .contextMenu { Button("Remove", role: .destructive) { researchStore.removeQuotation(item.id) } }
                        }
                    }
                    Section("Claim Links") {
                        ForEach(researchStore.projectBibliography.claimLinks) { item in
                            VStack(alignment: .leading) { Text(item.claimExcerpt); Text("\(item.chapterPath) · \(item.locator)").font(.caption).foregroundStyle(.secondary) }
                                .contextMenu { Button("Remove", role: .destructive) { researchStore.removeClaimLink(item.id) } }
                        }
                    }
                }
            }.padding().frame(minWidth: 530)
        }
    }

    private var notesEditor: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Kistulentz Research Notes.md").font(.headline)
                Spacer()
                Button("Show in Finder") { researchStore.revealResearchNotes() }
            }
            TextEditor(text: Binding(get: { researchStore.researchNotesText }, set: { researchStore.updateResearchNotes($0) }))
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
        }.padding()
    }

    private var availableSources: [ResearchSource] {
        let included = Set(researchStore.projectBibliography.sourceIDs)
        return library.sources.filter {
            !included.contains($0.id) && (search.isEmpty || [$0.title, $0.primaryCreatorName, $0.citeKey].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    private func sourceRow(_ source: ResearchSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.title).lineLimit(2)
            Text("\(source.primaryCreatorName) · @\(source.citeKey)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
