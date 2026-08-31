import AppKit
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
    @State private var isOllamaReachable = false
    @State private var ollamaDetectionMessage = "Not checked"
    @State private var showingRecommendedModelConfirmation = false
    @State private var ollamaPullProgress: OllamaPullProgress?
    @State private var ollamaPullTask: Task<Void, Never>?
    @State private var isPullingOllamaModel = false
    @State private var showingLanguagePackConfirmation = false
    @State private var showingLanguagePackRemovalConfirmation = false
    @State private var providerTestTask: Task<Void, Never>?
    @State private var testingProvider: AIProvider?
    @State private var providerTestResults: [AIProvider: ProviderTestDisplay] = [:]

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
                ProviderModelPicker(provider: .openAI, selection: $settings.openAIModel)
                keyButtons(provider: .openAI, value: $openAIKey)
                connectionTestRow(provider: .openAI)
            }

            Section("Anthropic") {
                LabeledContent("Status") {
                    statusLabel(connected: settings.hasAnthropicKey)
                }
                SecureField(settings.hasAnthropicKey ? "Enter a replacement key" : "API key", text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
                ProviderModelPicker(provider: .anthropic, selection: $settings.anthropicModel)
                keyButtons(provider: .anthropic, value: $anthropicKey)
                connectionTestRow(provider: .anthropic)
            }

            Section("Ollama · local AI") {
                LabeledContent("Status") {
                    HStack(spacing: 7) {
                        if isDetectingOllama {
                            ProgressView().controlSize(.small)
                        }
                        Text(ollamaDetectionMessage)
                            .foregroundStyle(isOllamaReachable ? Color.green : Color.secondary)
                    }
                }

                if isPullingOllamaModel {
                    VStack(alignment: .leading, spacing: 8) {
                        if let fraction = ollamaPullProgress?.fractionCompleted {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView()
                        }
                        Text(ollamaProgressDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Cancel Model Download", role: .cancel) {
                            ollamaPullTask?.cancel()
                        }
                    }
                } else if isOllamaReachable, !ollamaModels.isEmpty {
                    Picker("Detected models", selection: $settings.ollamaModel) {
                        if !ollamaModels.contains(settings.ollamaModel), !settings.ollamaModel.isEmpty {
                            Text("Unavailable · (settings.ollamaModel)").tag(settings.ollamaModel)
                        }
                        ForEach(ollamaModels, id: \.self) { model in
                            Text(model == OllamaService.recommendedWritingModel
                                ? "\(model) · Recommended"
                                : model)
                                .tag(model)
                        }
                    }

                    HStack {
                        Button("Use Ollama for Polish and Rewrite") {
                            settings.provider = .ollama
                            statusMessage = "Ollama is now the selected writing provider."
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!ollamaModels.contains(settings.ollamaModel))

                        if !ollamaModels.contains(OllamaService.recommendedWritingModel) {
                            Button("Get Recommended Model…") {
                                showingRecommendedModelConfirmation = true
                            }
                        }
                    }
                } else if isOllamaReachable {
                    Text("Ollama is running, but it has no local models yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Download and Use Recommended Model…") {
                        showingRecommendedModelConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Install and open Ollama, then Kistulentz will detect it automatically and help you add a writing model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Get Ollama…") {
                            NSWorkspace.shared.open(OllamaService.downloadURL)
                            ollamaDetectionMessage = "Waiting for Ollama to start…"
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Check Again") {
                            Task { await detectOllama() }
                        }
                        .disabled(isDetectingOllama)
                    }
                }

                HStack {
                    Button("Refresh Models") {
                        Task { await detectOllama() }
                    }
                    .disabled(isDetectingOllama || isPullingOllamaModel)
                    Text("Ollama and its models stay on this Mac. Every download requires confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                connectionTestRow(provider: .ollama)
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
            await monitorOllama()
        }
        .onDisappear {
            ollamaPullTask?.cancel()
            providerTestTask?.cancel()
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
        .alert("Download the recommended Ollama model?", isPresented: $showingRecommendedModelConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Download and Use") { startRecommendedModelDownload() }
        } message: {
            Text("Kistulentz will ask Ollama to download \(OllamaService.recommendedWritingModel). The model needs several GB of local storage. Progress is shown here, and you can cancel while it downloads.")
        }
        .alert("English language pack", isPresented: Binding(
            get: { beneparPack.errorMessage != nil },
            set: { if !$0 { beneparPack.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(beneparPack.errorMessage ?? "")
        }
        .alert("Kistulentz Settings", isPresented: Binding(
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
                    providerTestResults[provider] = nil
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
                        providerTestResults[provider] = nil
                        statusMessage = "\(provider.title) key removed."
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionTestRow(provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            Button(testingProvider == provider ? "Testing…" : "Test Connection") {
                testConnection(provider)
            }
            .disabled(testingProvider != nil || !settings.isProviderReady(provider))

            if testingProvider == provider {
                ProgressView().controlSize(.small)
            } else if let result = providerTestResults[provider] {
                Label(
                    result.message,
                    systemImage: result.succeeded
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(result.succeeded ? Color.green : Color.orange)
            }
        }
        Text("This checks only the saved key and selected model. No manuscript, project, reference, or prompt text is sent.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func testConnection(_ provider: AIProvider) {
        providerTestTask?.cancel()
        testingProvider = provider
        providerTestResults[provider] = nil
        let model = settings.model(for: provider)
        let apiKey = settings.apiKey(for: provider)
        providerTestTask = Task {
            defer {
                if testingProvider == provider { testingProvider = nil }
                providerTestTask = nil
            }
            do {
                let result = try await ProviderConnectionTester().test(
                    provider: provider,
                    model: model,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                providerTestResults[provider] = ProviderTestDisplay(
                    succeeded: true,
                    message: result.message
                )
            } catch is CancellationError {
                return
            } catch {
                providerTestResults[provider] = ProviderTestDisplay(
                    succeeded: false,
                    message: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    private func detectOllama() async {
        guard !isDetectingOllama else { return }
        isDetectingOllama = true
        do {
            let models = try await OllamaService().installedModels()
            isOllamaReachable = true
            ollamaModels = models
            if models.isEmpty {
                ollamaDetectionMessage = "Ollama found · no models installed"
            } else {
                ollamaDetectionMessage = "\(models.count) model\(models.count == 1 ? "" : "s") found"
                if settings.ollamaModel.isEmpty || !models.contains(settings.ollamaModel) {
                    settings.ollamaModel = models.contains(OllamaService.recommendedWritingModel)
                        ? OllamaService.recommendedWritingModel
                        : models[0]
                }
            }
        } catch {
            isOllamaReachable = false
            ollamaModels = []
            ollamaDetectionMessage = "Ollama not running"
        }
        isDetectingOllama = false
    }

    @MainActor
    private func monitorOllama() async {
        await detectOllama()
        while !Task.isCancelled, !isOllamaReachable {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await detectOllama()
        }
    }

    @MainActor
    private func startRecommendedModelDownload() {
        guard isOllamaReachable, !isPullingOllamaModel else { return }
        isPullingOllamaModel = true
        ollamaPullProgress = OllamaPullProgress(
            status: "Starting download…",
            completedBytes: nil,
            totalBytes: nil
        )
        errorMessage = nil
        ollamaPullTask = Task {
            do {
                try await OllamaService().pullModel(OllamaService.recommendedWritingModel) { progress in
                    ollamaPullProgress = progress
                }
                guard !Task.isCancelled else { throw CancellationError() }
                await detectOllama()
                let verifiedModel = try OllamaSetupVerifier.verifyDownloadedModel(
                    OllamaService.recommendedWritingModel,
                    in: ollamaModels
                )
                guard isOllamaReachable else { throw OllamaSetupError.modelNotVerified }
                settings.ollamaModel = verifiedModel
                settings.provider = .ollama
                statusMessage = "The recommended Ollama model is ready and selected."
            } catch is CancellationError {
                statusMessage = "Ollama model download cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            isPullingOllamaModel = false
            ollamaPullProgress = nil
            ollamaPullTask = nil
        }
    }

    private var ollamaProgressDescription: String {
        guard let progress = ollamaPullProgress else { return "Preparing the local model…" }
        if let completed = progress.completedBytes, let total = progress.totalBytes {
            return "\(progress.status) · \(formattedBytes(completed)) of \(formattedBytes(total))"
        }
        return progress.status
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct ProviderTestDisplay {
    let succeeded: Bool
    let message: String
}

private struct ProviderModelPicker: View {
    private static let customChoice = "__kistulentz_custom_model__"

    let provider: AIProvider
    let choices: [AIModelChoice]
    @Binding var selection: String
    @State private var usesCustomModel: Bool

    init(provider: AIProvider, selection: Binding<String>) {
        let choices = AIModelCatalog.choices(for: provider)
        self.provider = provider
        self.choices = choices
        _selection = selection
        _usesCustomModel = State(
            initialValue: !choices.contains(where: { $0.id == selection.wrappedValue })
        )
    }

    var body: some View {
        Picker("Model", selection: pickerSelection) {
            ForEach(choices) { choice in
                Text(choice.menuTitle).tag(choice.id)
            }
            Text("Custom…").tag(Self.customChoice)
        }
        .pickerStyle(.menu)

        if usesCustomModel {
            TextField("Custom model ID", text: $selection)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Custom \(provider.title) model ID")
        }

        Text(modelDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var pickerSelection: Binding<String> {
        Binding(
            get: { usesCustomModel ? Self.customChoice : selection },
            set: { newValue in
                if newValue == Self.customChoice {
                    if choices.contains(where: { $0.id == selection }) {
                        selection = ""
                    }
                    usesCustomModel = true
                } else {
                    usesCustomModel = false
                    selection = newValue
                }
            }
        )
    }

    private var modelDescription: String {
        if usesCustomModel {
            return selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter a model ID supplied by \(provider.title)."
                : "Using the custom model ID saved for \(provider.title)."
        }
        return choices.first(where: { $0.id == selection })?.summary ?? "Choose a model."
    }
}
