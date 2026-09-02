import SwiftUI

struct DocumentImportPreviewView: View {
    let draft: DocumentImportDraft
    let onCancel: () -> Void
    let onSave: ([UUID: DocumentTrackedChangeDecision]) -> Void

    @State private var decisions: [UUID: DocumentTrackedChangeDecision] = [:]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import \(draft.sourceURL.lastPathComponent)")
                        .font(.title2.bold())
                    Text("\(draft.format.title) → one Markdown document")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save Markdown Copy…") { onSave(decisions) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!unresolvedCards.isEmpty)
                    .help(unresolvedCards.isEmpty
                        ? "Save the preview as a new Markdown file"
                        : "Accept or reject every tracked change first")
            }
            .padding()

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("Markdown Preview", systemImage: "doc.plaintext")
                            .font(.headline)
                        Spacer()
                        Text(previewWordCount.formatted() + " words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    Divider()
                    ScrollView([.vertical, .horizontal]) {
                        Text(previewMarkdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(16)
                    }
                }
                .frame(minWidth: 510)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sourceSafetyCard

                        if !draft.reviewCards.isEmpty {
                            trackedChangesSection
                        }

                        conversionReport

                        if !draft.assets.isEmpty {
                            Label(
                                "\(draft.assets.count) embedded image\(draft.assets.count == 1 ? "" : "s") will be copied beside the Markdown file.",
                                systemImage: "photo.on.rectangle"
                            )
                            .font(.callout)
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 330, idealWidth: 370, maxWidth: 430)
            }
        }
        .frame(minWidth: 920, minHeight: 680)
        .onExitCommand(perform: onCancel)
    }

    private var previewMarkdown: String {
        draft.renderedMarkdown(decisions: decisions)
    }

    private var previewWordCount: Int {
        previewMarkdown.split { $0.isWhitespace }.count
    }

    private var unresolvedCards: [DocumentImportReviewCard] {
        draft.reviewCards.filter { decisions[$0.id] == nil }
    }

    private var sourceSafetyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Original remains untouched", systemImage: "lock.doc")
                .font(.headline)
            Text("Kistulentz saves a new .md file. It does not overwrite or modify the selected source document.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var trackedChangesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Word Tracked Changes")
                        .font(.headline)
                    Text("\(unresolvedCards.count) of \(draft.reviewCards.count) still need a decision")
                        .font(.caption)
                        .foregroundStyle(unresolvedCards.isEmpty ? Color.secondary : Color.orange)
                }
                Spacer()
                Menu("Decide All") {
                    Button("Accept All") {
                        decisions = Dictionary(uniqueKeysWithValues: draft.reviewCards.map { ($0.id, .accept) })
                    }
                    Button("Reject All") {
                        decisions = Dictionary(uniqueKeysWithValues: draft.reviewCards.map { ($0.id, .reject) })
                    }
                    Button("Clear Decisions") { decisions.removeAll() }
                }
            }

            ForEach(draft.reviewCards) { card in
                trackedChangeCard(card)
            }
        }
    }

    private func trackedChangeCard(_ card: DocumentImportReviewCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    card.kind.title,
                    systemImage: card.kind == .insertion ? "plus.circle.fill" : "minus.circle.fill"
                )
                .font(.subheadline.bold())
                .foregroundStyle(card.kind == .insertion ? Color.green : Color.red)
                Spacer()
                if let author = card.author, !author.isEmpty {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                }
            }

            Text(card.changedMarkdown)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(6)
                .textSelection(.enabled)

            HStack {
                Button {
                    decisions[card.id] = .accept
                } label: {
                    Label("Accept", systemImage: decisions[card.id] == .accept ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)

                Button {
                    decisions[card.id] = .reject
                } label: {
                    Label("Reject", systemImage: decisions[card.id] == .reject ? "xmark.circle.fill" : "circle")
                }
                .buttonStyle(.bordered)
                Spacer()
                if let date = card.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(decisions[card.id] == nil ? Color.orange.opacity(0.7) : Color.secondary.opacity(0.2))
        }
    }

    private var conversionReport: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversion Report")
                .font(.headline)
            ForEach(draft.notices) { notice in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: notice.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(notice.severity == .warning ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notice.title).font(.subheadline.bold())
                        Text(notice.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
