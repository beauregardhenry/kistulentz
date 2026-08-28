import SwiftUI

struct ProjectRecoveryView: View {
    let request: ProjectRecoveryRequest
    let onRestore: (ProjectMetadataBackup) -> Void
    let onCancel: () -> Void

    @State private var selectedID: String?
    @State private var pendingRestore: ProjectMetadataBackup?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Project metadata needs recovery", systemImage: "lifepreserver.fill")
                    .font(.title2.weight(.semibold))
                Text(request.failureDescription)
                    .foregroundStyle(.secondary)
                Text(request.rootURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            List(request.backups, selection: $selectedID) { backup in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(backup.reason.title).font(.headline)
                        Spacer()
                        Text("Format \(backup.formatVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(backup.createdAt.formatted(date: .abbreviated, time: .standard))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .tag(backup.id)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 210)

            Text("Restoring rolls back Kistulentz’s project metadata only. Manuscript Markdown files are not replaced. Kistulentz saves the current failed metadata before restoring the selected snapshot.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Restore Selected Snapshot…") {
                    pendingRestore = selectedBackup
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedBackup == nil)
            }
        }
        .padding(22)
        .frame(width: 620, height: 470)
        .onAppear { selectedID = request.backups.first?.id }
        .confirmationDialog(
            "Restore this metadata snapshot?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRestore {
                Button("Restore Metadata", role: .destructive) {
                    self.pendingRestore = nil
                    onRestore(pendingRestore)
                }
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("The current metadata will first be preserved as a new recovery snapshot. Manuscript Markdown files will not be changed.")
        }
    }

    private var selectedBackup: ProjectMetadataBackup? {
        request.backups.first { $0.id == selectedID }
    }
}
