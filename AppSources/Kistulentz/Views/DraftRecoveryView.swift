import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DraftRecoveryViewError: LocalizedError {
    case originalChanged
    case missingOriginal

    var errorDescription: String? {
        switch self {
        case .originalChanged:
            "The saved file changed after the recovery preview loaded. Reload the preview before replacing it."
        case .missingOriginal:
            "The original file is no longer available. Save the recovered draft as a new copy instead."
        }
    }
}

struct DraftRecoveryView: View {
    @ObservedObject var manager: DraftRecoveryManager
    let onClose: () -> Void

    @State private var selectedID: UUID?
    @State private var savedText: String?
    @State private var isLoadingSavedText = false
    @State private var isWorking = false
    @State private var pendingReplace: DraftRecoveryEntry?
    @State private var pendingDiscard: DraftRecoveryEntry?
    @State private var errorMessage: String?

    private let previewLimit = 50_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.pendingEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Drafts Need Recovery", systemImage: "checkmark.circle")
                } description: {
                    Text("Kistulentz did not find editing work left behind by an abnormal quit.")
                } actions: {
                    Button("Done", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                HSplitView {
                    recoveryList.frame(minWidth: 250, idealWidth: 290, maxWidth: 340)
                    recoveryPreview.frame(minWidth: 680)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 1_000, minHeight: 680)
        .onAppear {
            selectedID = selectedID ?? manager.pendingEntries.first?.id
            loadSavedText()
        }
        .onChange(of: selectedID) { _, _ in loadSavedText() }
        .alert("Draft Recovery", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Replace the saved file with this recovered draft?",
            isPresented: Binding(
                get: { pendingReplace != nil },
                set: { if !$0 { pendingReplace = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = pendingReplace {
                Button("Replace Saved File", role: .destructive) {
                    pendingReplace = nil
                    replaceOriginal(entry)
                }
            }
            Button("Cancel", role: .cancel) { pendingReplace = nil }
        } message: {
            Text("Kistulentz will write the full recovered text only after confirming the saved file has not changed since this preview loaded.")
        }
        .confirmationDialog(
            "Discard this recovered draft?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = pendingDiscard {
                Button("Discard Recovery", role: .destructive) {
                    pendingDiscard = nil
                    resolve(entry)
                }
            }
            Button("Cancel", role: .cancel) { pendingDiscard = nil }
        } message: {
            Text("The saved document will not be changed. The local recovery copy will be removed.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lifepreserver.fill")
                .font(.title)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Draft Recovery Review").font(.title2.bold())
                Text("Compare recovered writing with the currently saved file. Nothing is replaced automatically.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
        }
        .padding()
    }

    private var recoveryList: some View {
        List(manager.pendingEntries, selection: $selectedID) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline)
                Text(entry.updatedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.originalFilePath ?? "Unsaved document")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .tag(entry.id)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .accessibilityLabel("Recovered drafts")
    }

    @ViewBuilder
    private var recoveryPreview: some View {
        if let entry = selectedEntry {
            VStack(alignment: .leading, spacing: 10) {
                if entry.recoveredText.count > previewLimit || (savedText?.count ?? 0) > previewLimit {
                    Label(
                        "For responsiveness, each preview shows its first \(previewLimit.formatted()) characters. Save and replace actions use the complete text.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                HSplitView {
                    previewPane(
                        title: "Saved File",
                        text: savedPreview,
                        accessibilityLabel: "Currently saved text"
                    )
                    previewPane(
                        title: "Recovered Draft",
                        text: preview(entry.recoveredText),
                        accessibilityLabel: "Recovered draft text"
                    )
                }
            }
            .padding(12)
        } else {
            ContentUnavailableView("Select a Draft", systemImage: "doc.text.magnifyingglass")
        }
    }

    private var footer: some View {
        HStack {
            if isLoadingSavedText || isWorking {
                ProgressView().controlSize(.small)
            }
            Text(selectedEntry?.projectRootPath.map { "Project: \($0)" } ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Discard…") {
                pendingDiscard = selectedEntry
            }
            .disabled(selectedEntry == nil || isWorking)
            Button("Save Recovered Copy…") {
                if let entry = selectedEntry { saveCopy(entry) }
            }
            .disabled(selectedEntry == nil || isWorking)
            Button("Replace Saved File…") {
                pendingReplace = selectedEntry
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canReplaceSelected || isWorking || isLoadingSavedText)
        }
        .padding()
    }

    private func previewPane(title: String, text: String, accessibilityLabel: String) -> some View {
        GroupBox(title) {
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? "No text is available." : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(8)
            }
            .accessibilityLabel(accessibilityLabel)
        }
        .frame(minWidth: 320)
    }

    private var selectedEntry: DraftRecoveryEntry? {
        manager.pendingEntries.first { $0.id == selectedID }
    }

    private var canReplaceSelected: Bool {
        guard savedText != nil, let path = selectedEntry?.originalFilePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private var savedPreview: String {
        if isLoadingSavedText { return "Loading the saved file…" }
        guard let savedText else { return "The original file is unavailable." }
        return preview(savedText)
    }

    private func preview(_ text: String) -> String {
        guard text.count > previewLimit else { return text }
        return String(text.prefix(previewLimit)) + "\n\n[Preview truncated]"
    }

    private func loadSavedText() {
        guard let entry = selectedEntry else {
            savedText = nil
            return
        }
        isLoadingSavedText = true
        Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) {
                DraftRecoveryDisk.savedText(for: entry)
            }.value
            guard selectedID == entry.id else { return }
            savedText = loaded
            isLoadingSavedText = false
        }
    }

    private func saveCopy(_ entry: DraftRecoveryEntry) {
        let panel = NSSavePanel()
        panel.title = "Save Recovered Draft"
        panel.message = "The original file will remain unchanged."
        panel.prompt = "Save Recovered Copy"
        panel.allowedContentTypes = [.markdownDocument]
        panel.nameFieldStringValue = entry.suggestedCopyName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isWorking = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DraftRecoveryDisk.writeRecoveredText(entry, to: url) }
            }.value
            isWorking = false
            switch result {
            case .success: resolve(entry)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func replaceOriginal(_ entry: DraftRecoveryEntry) {
        guard let url = entry.originalFileURL else {
            errorMessage = DraftRecoveryViewError.missingOriginal.localizedDescription
            return
        }
        let previewedSavedText = savedText
        isWorking = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        throw DraftRecoveryViewError.missingOriginal
                    }
                    guard DraftRecoveryDisk.savedText(for: entry) == previewedSavedText else {
                        throw DraftRecoveryViewError.originalChanged
                    }
                    try DraftRecoveryDisk.writeRecoveredText(entry, to: url)
                }
            }.value
            isWorking = false
            switch result {
            case .success: resolve(entry)
            case .failure(let error):
                errorMessage = error.localizedDescription
                loadSavedText()
            }
        }
    }

    private func resolve(_ entry: DraftRecoveryEntry) {
        manager.resolve(entry)
        selectedID = manager.pendingEntries.first?.id
        loadSavedText()
    }
}
