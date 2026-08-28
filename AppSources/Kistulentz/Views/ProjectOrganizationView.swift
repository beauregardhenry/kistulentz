import SwiftUI

private enum OrganizationViewMode: String, CaseIterable, Identifiable {
    case corkboard = "Corkboard"
    case outliner = "Outliner"
    var id: String { rawValue }
}

private struct PendingOutlineItem: Identifiable {
    let id = UUID()
    let kind: OutlineNodeKind
    let parentID: UUID?
}

struct ProjectOrganizationView: View {
    @ObservedObject var store: WritingProjectStore
    let reference: EPUBReference?

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var mode: OrganizationViewMode = .corkboard
    @State private var focusedContainerID: UUID?
    @State private var selectedNodeID: UUID?
    @State private var pendingNewItem: PendingOutlineItem?
    @State private var filePlan: OutlineFileOrganizationPlan?
    @State private var splitPlan: HeadingSplitPlan?
    @State private var pendingAIRequest: AIRequestPreview?
    @State private var pendingAISynopsisNodeID: UUID?
    @State private var isRunningAI = false
    @State private var searchText = ""

    private var focusedNode: OutlineNode? { store.outlineNode(id: focusedContainerID) }
    private var selectedNode: OutlineNode? { store.outlineNode(id: selectedNodeID) }

    private var boardNodes: [OutlineNode] {
        let source = store.outlineChildren(of: focusedContainerID)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { node in
            node.title.localizedCaseInsensitiveContains(query)
                || node.metadata.synopsis.localizedCaseInsensitiveContains(query)
                || node.metadata.suggestedSynopsis.localizedCaseInsensitiveContains(query)
                || node.metadata.labels.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                organizationContent
                    .frame(minWidth: 650)
                inspector
                    .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)
            }
        }
        .frame(minWidth: 1_080, minHeight: 720)
        .onAppear {
            store.attachUndoManager(undoManager)
            selectedNodeID = store.outlineRows.first?.id
        }
        .sheet(item: $pendingNewItem) { pending in
            NewOutlineItemSheet(kind: pending.kind) { title in
                if let id = store.addOutlineItem(kind: pending.kind, title: title, parentID: pending.parentID) {
                    selectedNodeID = id
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { filePlan != nil },
            set: { if !$0 { filePlan = nil } }
        )) {
            if let filePlan {
                FileOrganizationPreviewView(store: store, initialPlan: filePlan) { approved in
                    store.organizeFiles(approved)
                    self.filePlan = nil
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { splitPlan != nil },
            set: { if !$0 { splitPlan = nil } }
        )) {
            if let splitPlan {
                HeadingSplitPreviewView(initialPlan: splitPlan) { approved in
                    store.applyHeadingSplit(approved)
                    self.splitPlan = nil
                }
            }
        }
        .sheet(item: $pendingAIRequest) { preview in
            AIRequestPreviewView(preview: preview) { confirmed in
                pendingAIRequest = nil
                runAISynopsis(confirmed)
            }
        }
        .alert("Kistulentz", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Project Organization").font(.title2.weight(.semibold))
                    Text("Reordering changes Kistulentz’s outline, not files in Finder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("View", selection: $mode) {
                    ForEach(OrganizationViewMode.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                Menu {
                    addItemButtons
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button("Organize Files…") {
                    filePlan = store.fileOrganizationPlan()
                }
                .disabled(store.fileOrganizationPlan()?.hasChanges != true)
                Button("Done") { dismiss() }
            }

            HStack(spacing: 8) {
                breadcrumbButton(title: store.projectName, id: nil)
                if let focusedContainerID {
                    ForEach(OutlineTree.ancestry(to: focusedContainerID, in: store.outlineNodes)) { node in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        breadcrumbButton(title: node.title, id: node.id)
                    }
                }
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter this level", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 230, height: 28)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var addItemButtons: some View {
        if focusedContainerID == nil {
            Button("Part") { pendingNewItem = PendingOutlineItem(kind: .part, parentID: nil) }
            Button("Chapter") { pendingNewItem = PendingOutlineItem(kind: .chapter, parentID: nil) }
        } else if focusedNode?.kind == .part {
            Button("Chapter") { pendingNewItem = PendingOutlineItem(kind: .chapter, parentID: focusedContainerID) }
        } else if focusedNode?.kind == .chapter {
            let kind: OutlineNodeKind = store.projectKind == .fiction ? .scene : .section
            Button(kind.title) { pendingNewItem = PendingOutlineItem(kind: kind, parentID: focusedContainerID) }
        } else {
            Text("Open a Part or Chapter to add children")
        }
    }

    private func breadcrumbButton(title: String, id: UUID?) -> some View {
        Button(title) {
            focusedContainerID = id
            searchText = ""
        }
        .buttonStyle(.borderless)
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let movingID = UUID(uuidString: value) else { return false }
            store.moveOutlineNode(movingID, toParent: id)
            return true
        }
    }

    @ViewBuilder
    private var organizationContent: some View {
        switch mode {
        case .corkboard:
            ScrollView {
                if boardNodes.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "This level is empty" : "No matching cards",
                        systemImage: searchText.isEmpty ? "rectangle.stack.badge.plus" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Use Add to create the next level of the manuscript."
                            : "Try a different title, synopsis, or label.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 480)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 310), spacing: 14)], spacing: 14) {
                        ForEach(boardNodes) { node in
                            OutlineCard(
                                node: node,
                                wordCount: store.outlineWordCount(for: node),
                                warningCount: store.outlineWarningCount(for: node),
                                isSelected: selectedNodeID == node.id,
                                onSelect: { selectedNodeID = node.id },
                                onOpen: {
                                    if node.kind.isContainer {
                                        focusedContainerID = node.id
                                        selectedNodeID = node.id
                                        searchText = ""
                                    } else {
                                        store.selectOutlineNode(node.id)
                                        dismiss()
                                    }
                                },
                                onDropNode: { movingID in store.moveOutlineNode(movingID, onto: node.id) }
                            )
                        }
                    }
                    .padding(18)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.65))

        case .outliner:
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredOutlineRows) { row in
                        OutlineRow(
                            row: row,
                            wordCount: store.outlineWordCount(for: row.node),
                            warningCount: store.outlineWarningCount(for: row.node),
                            isSelected: selectedNodeID == row.id,
                            onSelect: { selectedNodeID = row.id },
                            onOpen: {
                                if row.node.kind.isContainer {
                                    focusedContainerID = row.id
                                    mode = .corkboard
                                } else {
                                    store.selectOutlineNode(row.id)
                                    dismiss()
                                }
                            },
                            onDropNode: { movingID in store.moveOutlineNode(movingID, onto: row.id) }
                        )
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
    }

    private var filteredOutlineRows: [OutlineFlatRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.outlineRows }
        return store.outlineRows.filter { row in
            row.node.title.localizedCaseInsensitiveContains(query)
                || row.node.metadata.synopsis.localizedCaseInsensitiveContains(query)
                || row.node.metadata.labels.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let node = selectedNode {
            OutlineNodeInspector(
                node: Binding(
                    get: { store.outlineNode(id: node.id) ?? node },
                    set: { store.updateOutlineNode($0) }
                ),
                projectKind: store.projectKind ?? .fiction,
                wordCount: store.outlineWordCount(for: node),
                isRunningAI: isRunningAI,
                onSuggestLocally: { store.suggestSynopsisLocally(for: node.id) },
                onDeepenAI: { prepareAISynopsis(for: node.id) },
                onOpenFile: {
                    store.selectOutlineNode(node.id)
                    dismiss()
                },
                onSplitHeadings: {
                    do { splitPlan = try store.headingSplitPlan(for: node.id) }
                    catch { store.errorMessage = error.localizedDescription }
                }
            )
            .id(node.id)
        } else {
            ContentUnavailableView(
                "Select an outline item",
                systemImage: "sidebar.right",
                description: Text("Its synopsis, status, labels, and project-specific details will appear here.")
            )
        }
    }

    private func prepareAISynopsis(for nodeID: UUID) {
        guard let node = store.outlineNode(id: nodeID) else { return }
        guard settings.isProviderReady(settings.provider) else {
            store.errorMessage = settings.provider.requiresAPIKey
                ? "Add your \(settings.provider.title) API key and choose a model in Settings first."
                : "Open Settings, detect the Ollama models already on this Mac, and choose one first."
            return
        }
        do {
            let context = try store.outlineAIContext(for: nodeID)
            let referenceContext = reference.map {
                WritingAIService.referenceContext($0, relevantTo: context, maxCharacters: 10_000)
            }
            pendingAISynopsisNodeID = nodeID
            pendingAIRequest = AIRequestPreview(
                purpose: .outlineSynopsis(
                    projectKind: store.projectKind ?? .fiction,
                    nodeKind: node.kind,
                    title: node.title
                ),
                provider: settings.provider,
                model: settings.model(for: settings.provider),
                primaryLabel: "Outline item and project context",
                primaryText: context,
                styleGuide: store.styleText,
                includesStyleGuide: !store.styleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                referenceContext: referenceContext,
                includesReferenceContext: referenceContext != nil,
                sourceRange: nil,
                sourceText: nil
            )
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func runAISynopsis(_ request: AIRequestPreview) {
        guard let nodeID = pendingAISynopsisNodeID else { return }
        isRunningAI = true
        Task {
            defer {
                isRunningAI = false
                pendingAISynopsisNodeID = nil
            }
            do {
                let response = try await OutlineAIService().suggestSynopsis(
                    request: request,
                    apiKey: settings.apiKey(for: request.provider)
                )
                store.applySuggestedSynopsis(response.synopsis, to: nodeID)
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OutlineCard: View {
    let node: OutlineNode
    let wordCount: Int
    let warningCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDropNode: (UUID) -> Void

    private var synopsis: String {
        let authored = node.metadata.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        if !authored.isEmpty { return authored }
        let suggested = node.metadata.suggestedSynopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        return suggested.isEmpty ? "No synopsis yet." : suggested
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(node.kind.title.uppercased(), systemImage: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(kindColor)
                Spacer()
                Text(node.metadata.status.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.13), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            Text(node.title)
                .font(.headline)
                .lineLimit(2)
            Text(synopsis)
                .font(.callout)
                .foregroundStyle(node.metadata.synopsis.isEmpty ? .secondary : .primary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            if !node.metadata.labels.isEmpty {
                Text(node.metadata.labels.prefix(4).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Label(wordCount.formatted(), systemImage: "text.word.spacing")
                if warningCount > 0 {
                    Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(node.kind.isContainer ? "Open" : "Edit", action: onOpen)
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onOpen)
        .draggable(node.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value) else { return false }
            onDropNode(id)
            return true
        }
    }

    private var icon: String {
        switch node.kind {
        case .part: "folder.fill"
        case .chapter: "doc.text.fill"
        case .scene: "theatermasks.fill"
        case .section: "text.alignleft"
        }
    }

    private var kindColor: Color {
        switch node.kind {
        case .part: .purple
        case .chapter: .blue
        case .scene: .pink
        case .section: .teal
        }
    }

    private var statusColor: Color {
        switch node.metadata.status {
        case .planned: .secondary
        case .drafting: .blue
        case .revised: .orange
        case .final: .green
        }
    }
}

private struct OutlineRow: View {
    let row: OutlineFlatRow
    let wordCount: Int
    let warningCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDropNode: (UUID) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Color.clear.frame(width: CGFloat(row.depth) * 22)
            Image(systemName: row.node.kind.isContainer ? "chevron.right" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.node.title).font(.callout.weight(.medium))
                Text(row.node.metadata.synopsis.isEmpty ? row.node.metadata.suggestedSynopsis : row.node.metadata.synopsis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if warningCount > 0 {
                Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(wordCount.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(row.node.metadata.status.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Button(action: onOpen) { Image(systemName: row.node.kind.isContainer ? "rectangle.stack" : "pencil") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .draggable(row.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value) else { return false }
            onDropNode(id)
            return true
        }
    }
}

private struct OutlineNodeInspector: View {
    @Binding var node: OutlineNode
    let projectKind: WritingProjectKind
    let wordCount: Int
    let isRunningAI: Bool
    let onSuggestLocally: () -> Void
    let onDeepenAI: () -> Void
    let onOpenFile: () -> Void
    let onSplitHeadings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.kind.title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("Title", text: $node.title)
                            .font(.title3.weight(.semibold))
                            .textFieldStyle(.plain)
                    }
                    Spacer()
                    if node.relativePath != nil {
                        Button("Edit", action: onOpenFile).buttonStyle(.bordered)
                    }
                }

                HStack {
                    Label("\(wordCount.formatted()) words", systemImage: "text.word.spacing")
                    if let path = node.relativePath {
                        Text(path).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                GroupBox("Synopsis") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $node.metadata.synopsis)
                            .frame(minHeight: 90)
                            .font(.callout)
                        Divider()
                        HStack {
                            Text("Suggested synopsis").font(.caption.weight(.semibold))
                            Spacer()
                            Button("Suggest Locally", action: onSuggestLocally)
                                .buttonStyle(.borderless)
                            Button(action: onDeepenAI) {
                                if isRunningAI { ProgressView().controlSize(.small) }
                                else { Text("Deepen w/ AI") }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isRunningAI)
                        }
                        Text(node.metadata.suggestedSynopsis.isEmpty
                            ? "Kistulentz keeps local and AI suggestions separate from your synopsis."
                            : node.metadata.suggestedSynopsis)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !node.metadata.suggestedSynopsis.isEmpty {
                            HStack {
                                Button("Use as Synopsis") {
                                    node.metadata.synopsis = node.metadata.suggestedSynopsis
                                }
                                .disabled(!node.metadata.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Clear Suggestion") { node.metadata.suggestedSynopsis = "" }
                                    .buttonStyle(.borderless)
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Planning") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Status", selection: $node.metadata.status) {
                            ForEach(OutlineDraftStatus.allCases) { status in Text(status.title).tag(status) }
                        }
                        TextField("Purpose", text: $node.metadata.purpose)
                        TextField("Labels, comma separated", text: commaSeparated($node.metadata.labels))
                        TextField("Target words", value: $node.metadata.targetWordCount, format: .number)
                        Toggle("Include in export", isOn: $node.metadata.includedInExport)
                        Text("Notes").font(.caption.weight(.semibold))
                        TextEditor(text: $node.metadata.notes)
                            .frame(minHeight: 70)
                    }
                    .padding(.top, 4)
                }

                if projectKind == .fiction {
                    fictionFields
                } else {
                    nonfictionFields
                }

                if node.kind == .chapter, node.relativePath != nil {
                    GroupBox("Chapter Structure") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview level-two headings and create separate \(projectKind == .fiction ? "Scene" : "Section") Markdown files. The chapter is snapshotted first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Split Headings into \(projectKind == .fiction ? "Scenes" : "Sections")…", action: onSplitHeadings)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private var fictionFields: some View {
        GroupBox("Fiction") {
            VStack(spacing: 9) {
                TextField("Point of view", text: $node.metadata.pointOfView)
                TextField("Characters, comma separated", text: commaSeparated($node.metadata.characters))
                TextField("Location", text: $node.metadata.location)
                TextField("Story date or time", text: $node.metadata.storyDateTime)
                TextField("Scene goal", text: $node.metadata.sceneGoal)
                TextField("Conflict", text: $node.metadata.conflict)
                TextField("Outcome or change", text: $node.metadata.outcome)
                TextField("Emotional movement", text: $node.metadata.emotionalMovement)
            }
            .padding(.top, 4)
        }
    }

    private var nonfictionFields: some View {
        GroupBox("Nonfiction") {
            VStack(spacing: 9) {
                TextField("Central claim", text: $node.metadata.centralClaim)
                TextField("Evidence status", text: $node.metadata.evidenceStatus)
                TextField("Sources, comma separated", text: commaSeparated($node.metadata.sources))
                TextField("Concepts, comma separated", text: commaSeparated($node.metadata.concepts))
                TextField("Intended audience", text: $node.metadata.intendedAudience)
                TextField("Counterargument", text: $node.metadata.counterargument)
                TextField("Target reading grade", value: $node.metadata.targetReadingGrade, format: .number)
                TextField("Reader takeaway", text: $node.metadata.readerTakeaway)
            }
            .padding(.top, 4)
        }
    }

    private func commaSeparated(_ values: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { values.wrappedValue.joined(separator: ", ") },
            set: { text in
                values.wrappedValue = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

private struct NewOutlineItemSheet: View {
    let kind: OutlineNodeKind
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(kind.title)").font(.headline)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Text(kind == .part
                ? "Parts organize the outline without creating a file."
                : "Kistulentz creates a normal Markdown file and adds it to the outline.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(title)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}

private struct FileOrganizationPreviewView: View {
    @ObservedObject var store: WritingProjectStore
    let onApply: (OutlineFileOrganizationPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var plan: OutlineFileOrganizationPlan

    init(
        store: WritingProjectStore,
        initialPlan: OutlineFileOrganizationPlan,
        onApply: @escaping (OutlineFileOrganizationPlan) -> Void
    ) {
        self.store = store
        self.onApply = onApply
        _plan = State(initialValue: initialPlan)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organize Files to Match Outline").font(.headline)
                    Text("Nothing moves until you approve this list. Filenames stay unchanged unless you edit them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Organize \(plan.includedMoves.filter { $0.sourcePath != $0.destinationPath }.count) Files") {
                    onApply(store.validateFileOrganizationPlan(plan))
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan.hasConflicts || !plan.hasChanges)
            }
            .padding(16)
            Divider()
            List {
                ForEach(plan.moves.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: moveBinding(index, \.isIncluded)).labelsHidden()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.moves[index].sourcePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Image(systemName: "arrow.turn.down.right")
                                TextField("Destination", text: moveBinding(index, \.destinationPath))
                                    .textFieldStyle(.roundedBorder)
                            }
                            if let conflict = plan.moves[index].conflict {
                                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            HStack {
                Label("Kistulentz snapshots each affected document and registers one macOS Undo action.", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private func moveBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<OutlineFileMove, Value>) -> Binding<Value> {
        Binding(
            get: { plan.moves[index][keyPath: keyPath] },
            set: { value in
                plan.moves[index][keyPath: keyPath] = value
                plan = store.validateFileOrganizationPlan(plan)
            }
        )
    }
}

private struct HeadingSplitPreviewView: View {
    let onApply: (HeadingSplitPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var plan: HeadingSplitPlan

    init(initialPlan: HeadingSplitPlan, onApply: @escaping (HeadingSplitPlan) -> Void) {
        self.onApply = onApply
        _plan = State(initialValue: initialPlan)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Split Chapter Headings").font(.headline)
                    Text("Selected headings become separate Markdown files. The chapter is snapshotted before any change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create \(plan.includedSections.count) Files") { onApply(plan) }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.includedSections.isEmpty)
            }
            .padding(16)
            Divider()
            List {
                ForEach(plan.sections.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: $plan.sections[index].isIncluded).labelsHidden()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.sections[index].title).font(.callout.weight(.semibold))
                            TextField("Filename", text: $plan.sections[index].fileName)
                                .textFieldStyle(.roundedBorder)
                            Text(plan.sections[index].markdown)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}
