import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var beneparPack: BeneparLanguagePackManager
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var ollamaModels: [String] = []
    @State private var isDetectingOllama = false
    @State private var ollamaDetectionMessage = "Not checked"
    @State private var showingLanguagePackConfirmation = false
    @State private var showingLanguagePackRemovalConfirmation = false

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

            Section("System Check & Support") {
                Text("Check Markdown file support, local analysis, optional language packs and AI, the Reference Library, and publishing tools without sending writing anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Kistulentz System Check…") {
                    openWindow(id: "system-check")
                }
            }

            Section("English structural analysis · local") {
                LabeledContent("Status") {
                    HStack(spacing: 7) {
                        if beneparPack.isInstalling {
                            ProgressView().controlSize(.small)
                        }
                        Label(
                            beneparPack.state.title,
                            systemImage: beneparPack.isInstalled ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(beneparPack.isInstalled ? Color.green : Color.secondary)
                    }
                }

                Text("The optional English pack uses Benepar to examine clauses, phrase depth, subordination, coordination, likely fragments, adverbs, and passive constructions. Kistulentz uses those signals in live guidance, manuscript reports, and selected EPUB profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !beneparPack.activityMessage.isEmpty {
                    Text(beneparPack.activityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if beneparPack.isInstalled {
                        Button("Remove English Pack…", role: .destructive) {
                            showingLanguagePackRemovalConfirmation = true
                        }
                    } else {
                        Button("Install English Pack…") {
                            showingLanguagePackConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Text("Native analysis always remains available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(beneparPack.isInstalling)

                Label("Installation downloads the runtime and model from Kistulentz’s GitHub release. Document and EPUB text never leaves this Mac.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("The first structural analysis after launching Kistulentz may take longer while the local model starts. Native guidance remains visible during that time.")
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
            beneparPack.refresh()
            await detectOllama()
        }
        .alert("Install the English language pack?", isPresented: $showingLanguagePackConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Download and Install") {
                Task { await beneparPack.install() }
            }
        } message: {
            Text("This optional local component is a large download and needs more than 1 GB of storage after installation. It downloads program files and the Benepar English model; it does not upload writing or reference books.")
        }
        .alert("Remove the English language pack?", isPresented: $showingLanguagePackRemovalConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await beneparPack.remove() }
            }
        } message: {
            Text("Kistulentz will delete the downloaded parser runtime and model. Native readability, spelling, grammar, and AI features will continue to work.")
        }
        .alert("English language pack", isPresented: Binding(
            get: { beneparPack.errorMessage != nil },
            set: { if !$0 { beneparPack.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(beneparPack.errorMessage ?? "")
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
