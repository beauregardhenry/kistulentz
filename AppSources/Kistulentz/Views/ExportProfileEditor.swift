import SwiftUI

struct ExportProfileEditor: View {
    @Binding var profile: ExportProfile
    let destinations: [PublicationDestination]
    let onApplyDestinationPreset: () -> Void
    let onSave: () -> Void
    let onDuplicate: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Form {
            Section("Destination Preset") {
                LabeledContent(
                    "Selected destinations",
                    value: destinations.isEmpty ? "None" : destinations.map(\.shortTitle).joined(separator: ", ")
                )
                Text("Applying the preset chooses the required output format and raises locally checkable minimum settings. It does not replace your trim, typography, or design decisions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Recommended Settings", action: onApplyDestinationPreset)
                    .disabled(destinations.isEmpty)
            }
            Section("Named Profile") {
                TextField("Profile name", text: $profile.name)
                LabeledContent("Starting point", value: profile.kind.title)
                Picker("Preferred format", selection: $profile.preferredFormat) {
                    ForEach(PublicationExportFormat.allCases) { Text($0.title).tag($0) }
                }
                Picker("Citations", selection: $profile.citationMode) {
                    ForEach(PublicationCitationMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Include bibliography", isOn: $profile.includeBibliography)
                Toggle("Include cover", isOn: $profile.includeCover)
                Toggle("Include table of contents", isOn: $profile.includeTableOfContents)
                Toggle("Include front matter", isOn: $profile.includeFrontMatter)
                Toggle("Include back matter", isOn: $profile.includeBackMatter)
            }
            Section("Page & Type") {
                Picker("Page or trim size", selection: $profile.layout.pageSize) {
                    ForEach(PublicationPageSize.allCases) { Text($0.title).tag($0) }
                }
                TextField("Body font", text: $profile.layout.bodyFontName)
                TextField("Heading font", text: $profile.layout.headingFontName)
                TextField("Body size", value: $profile.layout.bodyFontSize, format: .number).frame(maxWidth: 140)
                TextField("Line height", value: $profile.layout.lineHeightMultiple, format: .number).frame(maxWidth: 140)
                TextField("Paragraph spacing", value: $profile.layout.paragraphSpacing, format: .number).frame(maxWidth: 140)
                TextField("First-line indent", value: $profile.layout.firstLineIndent, format: .number).frame(maxWidth: 140)
                Toggle("Hyphenation", isOn: $profile.layout.hyphenationEnabled)
            }
            Section("Margins & Running Matter") {
                TextField("Top margin", value: $profile.layout.topMargin, format: .number).frame(maxWidth: 140)
                TextField("Bottom margin", value: $profile.layout.bottomMargin, format: .number).frame(maxWidth: 140)
                TextField("Inside margin", value: $profile.layout.insideMargin, format: .number).frame(maxWidth: 140)
                TextField("Outside margin", value: $profile.layout.outsideMargin, format: .number).frame(maxWidth: 140)
                Toggle("Running header", isOn: $profile.layout.headerEnabled)
                Toggle("Footer", isOn: $profile.layout.footerEnabled)
                Toggle("Page numbers", isOn: $profile.layout.pageNumbersEnabled)
                Picker("Chapter openings", selection: $profile.layout.chapterOpening) {
                    ForEach(PublicationChapterOpening.allCases) { Text($0.title).tag($0) }
                }
                Picker("Print bleed", selection: $profile.printBleed) {
                    ForEach(PublicationPrintBleed.allCases) { Text($0.title).tag($0) }
                }
                Text("Use bleed only when artwork must reach the top, bottom, or outside trimmed edge. Kistulentz never adds gutter bleed or printer marks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Duplicate as Custom Profile", action: onDuplicate)
                    if let onDelete {
                        Button("Delete Custom Profile", role: .destructive, action: onDelete)
                    }
                    Spacer()
                    Button("Save Profile", action: onSave).buttonStyle(.borderedProminent)
                }
            }
        }
        .accessibilityIdentifier("PublicationExportHistory")
        .formStyle(.grouped)
    }
}
