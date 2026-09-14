import SwiftUI

struct NewOutlineItemSheet: View {
    let kind: OutlineNodeKind
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(kind.title)").font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("NewOutlineItemTitle")
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

struct FileOrganizationPreviewView: View {
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

struct HeadingSplitPreviewView: View {
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
