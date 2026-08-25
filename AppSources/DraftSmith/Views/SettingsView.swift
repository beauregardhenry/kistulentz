import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Writing target") {
                Picker("Default reading grade", selection: $settings.targetGrade) {
                    ForEach(4...16, id: \.self) { grade in
                        Text("Grade \(grade)").tag(grade)
                    }
                }
                Text("Kistulentz adjusts sentence-length guidance and asks the selected AI provider to rewrite toward this level.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI") {
                LabeledContent("Status") {
                    statusLabel(connected: settings.hasOpenAIKey)
                }
                SecureField(settings.hasOpenAIKey ? "Enter a replacement key" : "API key", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.openAIModel)
                    .textFieldStyle(.roundedBorder)
                keyButtons(provider: .openAI, value: $openAIKey)
            }

            Section("Anthropic") {
                LabeledContent("Status") {
                    statusLabel(connected: settings.hasAnthropicKey)
                }
                SecureField(settings.hasAnthropicKey ? "Enter a replacement key" : "API key", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.anthropicModel)
                    .textFieldStyle(.roundedBorder)
                keyButtons(provider: .anthropic, value: $anthropicKey)
            }

            Section {
                Label("Keys are saved in your Mac Keychain. Kistulentz sends document text only to the provider you choose when you run a review.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .navigationTitle("Kistulentz Settings")
        .alert("Couldn’t save the key", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func statusLabel(connected: Bool) -> some View {
        Label(connected ? "Connected" : "Not configured", systemImage: connected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(connected ? .green : .secondary)
    }

    private func keyButtons(provider: AIProvider, value: Binding<String>) -> some View {
        HStack {
            Button("Save key") {
                do {
                    try settings.saveAPIKey(value.wrappedValue, for: provider)
                    value.wrappedValue = ""
                    statusMessage = "\(provider.title) key saved securely."
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .disabled(value.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if settings.hasKey(for: provider) {
                Button("Remove key", role: .destructive) {
                    do {
                        try settings.saveAPIKey("", for: provider)
                        value.wrappedValue = ""
                        statusMessage = "\(provider.title) key removed."
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
