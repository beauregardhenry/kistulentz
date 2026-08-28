import SwiftUI

struct AIRequestPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AIRequestPreview
    let onConfirm: (AIRequestPreview) -> Void

    init(preview: AIRequestPreview, onConfirm: @escaping (AIRequestPreview) -> Void) {
        _draft = State(initialValue: preview)
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: draft.provider.isLocal ? "desktopcomputer" : "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(draft.provider.isLocal ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.purpose.title)
                        .font(.title2.weight(.semibold))
                    Text(draft.provider.isLocal
                        ? "This request stays on this Mac. Review the local material below before running it."
                        : "Nothing is sent until you confirm. Review or redact the writing material below.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    requestDestination

                    materialEditor(
                        title: draft.primaryLabel,
                        detail: "Required · \(draft.primaryText.count.formatted()) characters",
                        text: $draft.primaryText
                    )

                    if draft.styleGuide != nil {
                        optionalMaterial(
                            title: "Kistulentz Style.md",
                            included: $draft.includesStyleGuide,
                            text: Binding(
                                get: { draft.styleGuide ?? "" },
                                set: { draft.styleGuide = $0 }
                            )
                        )
                    }

                    if draft.referenceContext != nil {
                        optionalMaterial(
                            title: "Reference profile and selected excerpts",
                            included: $draft.includesReferenceContext,
                            text: Binding(
                                get: { draft.referenceContext ?? "" },
                                set: { draft.referenceContext = $0 }
                            )
                        )
                    }

                    DisclosureGroup("Exact service instructions") {
                        selectableRequestText(draft.instructions)
                    }

                    DisclosureGroup("Exact assembled input") {
                        selectableRequestText(draft.input)
                    }

                    Label(
                        draft.provider.isLocal
                            ? "The request goes only to Ollama at localhost:11434. Kistulentz does not install models or send this request to a cloud provider."
                            : "Only the displayed service instructions, assembled input, selected model, and fixed response format are sent. Your API key is used only for authentication.",
                        systemImage: draft.provider.isLocal ? "checkmark.shield.fill" : "network.badge.shield.half.filled"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.purpose.actionTitle) {
                    let confirmed = draft
                    dismiss()
                    onConfirm(confirmed)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 650, idealHeight: 720)
    }

    private var requestDestination: some View {
        HStack(spacing: 0) {
            requestFact(label: "PROVIDER", value: draft.provider.title)
            Divider().frame(height: 34)
            requestFact(label: "MODEL", value: draft.model)
            Divider().frame(height: 34)
            requestFact(label: "DESTINATION", value: draft.provider.destination)
        }
        .padding(.vertical, 11)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 11))
    }

    private func requestFact(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func materialEditor(
        title: String,
        detail: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
            Text("Edits here change only what the AI receives. Redacted text may also appear redacted in its response.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func optionalMaterial(
        title: String,
        included: Binding<Bool>,
        text: Binding<String>
    ) -> some View {
        DisclosureGroup {
            TextEditor(text: text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 120)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
                .disabled(!included.wrappedValue)
                .opacity(included.wrappedValue ? 1 : 0.45)
        } label: {
            Toggle(isOn: included) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(included.wrappedValue ? "Included in this request" : "Kept on this Mac")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private func selectableRequestText(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(10)
        }
        .frame(maxHeight: 220)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 6)
    }
}

struct ToneRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tone = ""
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjust Tone")
                .font(.title2.weight(.semibold))
            Text("Describe the tone you want—for example, restrained and suspenseful, warm and conversational, or formal and authoritative.")
                .foregroundStyle(.secondary)
            TextField("Requested tone", text: $tone)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue") {
                    let value = tone.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                    onChoose(value)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(tone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

struct SelectionRewriteResultView: View {
    @Environment(\.dismiss) private var dismiss
    let presentation: SelectionRewritePresentation
    let onUse: (RewriteAlternative) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.goal.title)
                        .font(.title2.weight(.semibold))
                    Text("Choose one alternative. The replacement is one undoable edit.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DisclosureGroup("Original selection") {
                        Text(presentation.sourceText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }

                    ForEach(Array(presentation.alternatives.enumerated()), id: \.element.id) { index, alternative in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Alternative \(index + 1)")
                                    .font(.headline)
                                Spacer()
                                Text("Grade \(alternative.gradeEstimate, format: .number.precision(.fractionLength(1)))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(alternative.text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(alternative.explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            HStack {
                                Spacer()
                                Button("Use Alternative \(index + 1)") {
                                    dismiss()
                                    onUse(alternative)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(14)
                        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
    }
}
