import SwiftUI

struct ResearchMetadataLookupView: View {
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
            }
            .pickerStyle(.segmented)
            TextField(kind == "DOI" ? "10.…" : "ISBN", text: $identifier)
            if let result {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title).font(.headline)
                        Text("\(result.primaryCreatorName) · \(result.issuedYear.map(String.init) ?? "n.d.")")
                        Text("@\(result.citeKey)").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Look Up") { lookup() }
                    .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isLookingUpMetadata)
                Button("Add to Library") {
                    if let result {
                        onUse(result)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(result == nil)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func lookup() {
        Task {
            do {
                result = kind == "DOI"
                    ? try await store.lookupDOI(identifier)
                    : try await store.lookupISBN(identifier)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
