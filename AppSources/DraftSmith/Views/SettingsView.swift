import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var ollamaModels: [String] = []
    @State private var isDetectingOllama = false
    @State private var ollamaDetectionMessage = "Not checked"

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

            Section("Ollama · local AI") {
                LabeledContent("Status") {
                    HStack(spacing: 7) {
                        if isDetectingOllama {
                            ProgressView().controlSize(.small)
                        }
                        Text(ollamaDetectionMessage)
                            .foregroundStyle(ollamaModels.isEmpty ? Color.secondary : Color.green)
                    }
                }

                TextField("Selected model", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)

                if !ollamaModels.isEmpty {
                    Picker("Detected models", selection: $settings.ollamaModel) {
                        if !ollamaModels.contains(settings.ollamaModel), !settings.ollamaModel.isEmpty {
                            Text(settings.ollamaModel).tag(settings.ollamaModel)
                        }
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                HStack {
                    Button("Detect Models") {
                        Task { await detectOllama() }
                    }
                    .disabled(isDetectingOllama)

                    Text("Kistulentz never installs Ollama or downloads models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("Keys are saved in your Mac Keychain. OpenAI and Anthropic requests show a privacy preview before anything is sent. Ollama runs through localhost on this Mac.", systemImage: "lock.shield")
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
        .task {
            await detectOllama()
        }
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

    @MainActor
    private func detectOllama() async {
        guard !isDetectingOllama else { return }
        isDetectingOllama = true
        do {
            let models = try await OllamaService().installedModels()
            ollamaModels = models
            if models.isEmpty {
                ollamaDetectionMessage = "Ollama found · no models installed"
            } else {
                ollamaDetectionMessage = "\(models.count) model\(models.count == 1 ? "" : "s") found"
                if settings.ollamaModel.isEmpty || !models.contains(settings.ollamaModel) {
                    settings.ollamaModel = models[0]
                }
            }
        } catch {
            ollamaModels = []
            ollamaDetectionMessage = "Ollama not running"
        }
        isDetectingOllama = false
    }
}
