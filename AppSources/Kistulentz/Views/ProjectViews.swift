import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var store: WritingProjectStore
    let onSelectSearchResult: (ProjectSearchResult) -> Void
    let onNewChapter: () -> Void
    let onEditStyle: () -> Void
    let onShowHistory: () -> Void
    let onCreateSnapshot: () -> Void
    let onShowManuscriptInsights: () -> Void
    let onShowOrganization: () -> Void
    let onShowResearch: () -> Void
    let onShowRevisionCenter: () -> Void
    let onShowPublish: () -> Void
    let onCloseProject: () -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.projectName)
                            .font(.headline)
                            .lineLimit(2)
                        Text(store.projectKind?.title ?? "Project")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("New Chapter…", action: onNewChapter)
                        Button("Edit Kistulentz Style…", action: onEditStyle)
                        Button("Revision History…", action: onShowHistory)
                        Button("Create Snapshot…", action: onCreateSnapshot)
                        Button("Manuscript Insights…", action: onShowManuscriptInsights)
                        Button("Project Organization…", action: onShowOrganization)
                        Button("Project Research…", action: onShowResearch)
                        Button("Systemic Revision Center…", action: onShowRevisionCenter)
                        Button("Publish & Export…", action: onShowPublish)
                        Divider()
                        Button("Close Project", action: onCloseProject)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Project actions")
                }

                HStack(spacing: 12) {
                    Label("\(store.chapters.count)", systemImage: "doc.text")
                    Label(store.combinedWordCount.formatted(), systemImage: "text.word.spacing")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search manuscript", text: $searchText)
                        .textFieldStyle(.plain)
                    if store.isSearching {
                        ProgressView().controlSize(.mini)
                    } else if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear manuscript search")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                .onChange(of: searchText) { _, value in store.search(value) }
            }
            .padding(12)

            Divider()

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapterList
            } else {
                searchResultList
            }

            Divider()
            HStack {
                Button(action: onNewChapter) {
                    Label("Chapter", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(action: onEditStyle) {
                    Image(systemName: "text.book.closed")
                }
                .buttonStyle(.borderless)
                .help("Edit Kistulentz Style")
                .accessibilityLabel("Edit Kistulentz Style")
                Button(action: onShowManuscriptInsights) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Manuscript Insights")
                .accessibilityLabel("Manuscript Insights")
                Button(action: onShowOrganization) {
                    Image(systemName: "rectangle.3.group")
                }
                .buttonStyle(.borderless)
                .help("Project Organization")
                .accessibilityLabel("Project Organization")
                Button(action: onShowResearch) {
                    Image(systemName: "books.vertical")
                }
                .buttonStyle(.borderless)
                .help("Project Research")
                .accessibilityLabel("Project Research")
                Button(action: onShowRevisionCenter) {
                    Image(systemName: "checklist")
                }
                .buttonStyle(.borderless)
                .help("Systemic Revision Center")
                .accessibilityLabel("Systemic Revision Center")
                Button(action: onShowPublish) {
                    Image(systemName: "shippingbox")
                }
                .buttonStyle(.borderless)
                .help("Publish & Export")
                .accessibilityLabel("Publish & Export")
                Button(action: onShowHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Revision History")
                .accessibilityLabel("Revision History")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.82))
    }

    private var chapterList: some View {
        List {
            ForEach(store.chapters) { chapter in
                Button {
                    store.selectChapter(chapter.relativePath)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: chapter.relativePath == store.selectedChapterPath ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(chapter.relativePath == store.selectedChapterPath ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            Text("\(chapter.wordCount.formatted()) words")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    chapter.relativePath == store.selectedChapterPath
                        ? Color.accentColor.opacity(0.11)
                        : Color.clear
                )
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.chapters.isEmpty {
                ContentUnavailableView("No chapters", systemImage: "doc.badge.plus")
            }
        }
    }

    private var searchResultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.searchResults) { result in
                    Button {
                        onSelectSearchResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(result.chapterTitle) · line \(result.line)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(result.preview)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                }

                if !store.isSearching && store.searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 24)
                }
            }
            .padding(8)
        }
    }
}

struct ProjectConfigurationSheet: View {
    let title: String
    let initialName: String
    let allowsNameEditing: Bool
    let onConfirm: (String, WritingProjectKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: WritingProjectKind = .fiction

    init(
        title: String,
        initialName: String,
        allowsNameEditing: Bool,
        onConfirm: @escaping (String, WritingProjectKind) -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.allowsNameEditing = allowsNameEditing
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text("Kistulentz keeps Markdown files normal and stores project metadata in a hidden .kistulentz folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Project name", text: $name)
                    .disabled(!allowsNameEditing)
                Picker("Writing type", selection: $kind) {
                    ForEach(WritingProjectKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(allowsNameEditing ? "Create Project" : "Use This Folder") {
                    onConfirm(name, kind)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 470)
    }
}

struct ProjectStyleEditorView: View {
    @ObservedObject var store: WritingProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kistulentz Style.md").font(.headline)
                    Text("Project-local instructions and learned preferences")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Learned Preferences", role: .destructive) {
                    showingClearConfirmation = true
                }
                Button("Cancel") { dismiss() }
                Button("Save") {
                    store.saveStyle(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            Divider()
            TextEditor(text: $draft)
                .font(.system(size: 14, design: .monospaced))
                .padding(8)
        }
        .frame(minWidth: 760, minHeight: 580)
        .onAppear { draft = store.styleText }
        .confirmationDialog(
            "Clear all learned preferences?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Learned Preferences", role: .destructive) {
                store.saveStyle(draft)
                store.clearLearnedStylePreferences()
                draft = store.styleText
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your manually written style instructions will remain unchanged.")
        }
    }
}

struct RevisionHistoryView: View {
    @ObservedObject var store: WritingProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSnapshotID: UUID?
    @State private var diffLines: [RevisionDiffLine] = []
    @State private var showingRestoreConfirmation = false
    @State private var errorMessage: String?

    private var selectedSnapshot: ProjectSnapshot? {
        store.snapshots.first { $0.id == selectedSnapshotID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revision History").font(.headline)
                    Text("Snapshots are stored inside this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedSnapshot != nil {
                    Button("Restore…") { showingRestoreConfirmation = true }
                        .buttonStyle(.borderedProminent)
                }
                Button("Done") { dismiss() }
            }
            .padding(14)
            Divider()

            HSplitView {
                List(selection: $selectedSnapshotID) {
                    ForEach(store.snapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.name).font(.callout.weight(.medium))
                            Text(snapshot.chapterPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(snapshot.createdAt, format: .dateTime.month().day().year().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(snapshot.id)
                    }
                }
                .frame(minWidth: 245, idealWidth: 280)

                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffLines) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(symbol(for: line.kind))
                                    .frame(width: 12, alignment: .center)
                                    .foregroundStyle(color(for: line.kind))
                                Text(line.text.isEmpty ? " " : line.text)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 12.5, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line.kind))
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(minWidth: 620, alignment: .leading)
                }
                .overlay {
                    if selectedSnapshot == nil {
                        ContentUnavailableView(
                            store.snapshots.isEmpty ? "No snapshots yet" : "Select a snapshot",
                            systemImage: "clock.arrow.circlepath",
                            description: Text(store.snapshots.isEmpty
                                ? "Create a named snapshot or begin editing a project chapter."
                                : "The comparison with the current chapter will appear here.")
                        )
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 650)
        .onAppear {
            selectedSnapshotID = store.snapshots.first?.id
            loadDiff()
        }
        .onChange(of: selectedSnapshotID) { _, _ in loadDiff() }
        .confirmationDialog(
            "Restore this snapshot?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Snapshot", role: .destructive) {
                if let selectedSnapshot {
                    store.restore(selectedSnapshot)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kistulentz will save the current chapter as another snapshot before restoring this version.")
        }
        .alert("Couldn’t compare revisions", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadDiff() {
        guard let snapshot = selectedSnapshot else {
            diffLines = []
            return
        }
        do {
            let old = try store.content(for: snapshot)
            let current = try store.currentContent(for: snapshot.chapterPath)
            diffLines = RevisionDiff.compare(old: old, new: current)
        } catch {
            errorMessage = error.localizedDescription
            diffLines = []
        }
    }

    private func symbol(for kind: RevisionDiffKind) -> String {
        switch kind {
        case .unchanged: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private func color(for kind: RevisionDiffKind) -> Color {
        switch kind {
        case .unchanged: .secondary
        case .added: .green
        case .removed: .red
        }
    }

    private func background(for kind: RevisionDiffKind) -> Color {
        switch kind {
        case .unchanged: .clear
        case .added: Color.green.opacity(0.10)
        case .removed: Color.red.opacity(0.10)
        }
    }
}

struct NamedSnapshotSheet: View {
    let chapterTitle: String
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Snapshot").font(.headline)
            Text("Save the current version of \(chapterTitle) inside the project.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Snapshot name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}

struct NewChapterSheet: View {
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Markdown Chapter").font(.headline)
            TextField("Chapter name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Kistulentz creates a normal .md file at the project root.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}
