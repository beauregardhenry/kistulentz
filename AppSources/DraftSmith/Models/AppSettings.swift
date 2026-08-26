import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .ollama: "Ollama (Local)"
        }
    }

    var keychainAccount: String? {
        switch self {
        case .openAI: "openai-api-key"
        case .anthropic: "anthropic-api-key"
        case .ollama: nil
        }
    }

    var requiresAPIKey: Bool { self != .ollama }

    var destination: String {
        switch self {
        case .openAI: "api.openai.com"
        case .anthropic: "api.anthropic.com"
        case .ollama: "This Mac · localhost:11434"
        }
    }

    var isLocal: Bool { self == .ollama }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum DefaultsKey {
        static let provider = "selectedAIProvider"
        static let targetGrade = "targetReadingGrade"
        static let openAIModel = "openAIModel"
        static let anthropicModel = "anthropicModel"
        static let ollamaModel = "ollamaModel"
        static let hiddenHighlightCategories = "hiddenHighlightCategories"
    }

    private static let legacyBundleIdentifier = "com.beauhenry.kistuletz"

    @Published var provider: AIProvider {
        didSet { defaults.set(provider.rawValue, forKey: DefaultsKey.provider) }
    }

    @Published var targetGrade: Int {
        didSet { defaults.set(targetGrade, forKey: DefaultsKey.targetGrade) }
    }

    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: DefaultsKey.openAIModel) }
    }

    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: DefaultsKey.anthropicModel) }
    }

    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: DefaultsKey.ollamaModel) }
    }

    @Published var hiddenHighlightCategories: Set<IssueCategory> {
        didSet {
            defaults.set(
                hiddenHighlightCategories.map(\.rawValue).sorted(),
                forKey: DefaultsKey.hiddenHighlightCategories
            )
        }
    }

    @Published private(set) var hasOpenAIKey = false
    @Published private(set) var hasAnthropicKey = false

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain

        Self.migrateLegacyDefaults(into: defaults)

        provider = AIProvider(rawValue: defaults.string(forKey: DefaultsKey.provider) ?? "") ?? .openAI
        let savedGrade = defaults.integer(forKey: DefaultsKey.targetGrade)
        targetGrade = savedGrade == 0 ? 8 : min(max(savedGrade, 4), 16)
        openAIModel = defaults.string(forKey: DefaultsKey.openAIModel) ?? "gpt-5.5"
        anthropicModel = defaults.string(forKey: DefaultsKey.anthropicModel) ?? "claude-sonnet-4-6"
        ollamaModel = defaults.string(forKey: DefaultsKey.ollamaModel) ?? ""
        hiddenHighlightCategories = Set(
            (defaults.stringArray(forKey: DefaultsKey.hiddenHighlightCategories) ?? [])
                .compactMap(IssueCategory.init(rawValue:))
        )

        refreshKeyStatus()
    }

    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        guard let legacy = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        let keys = [
            DefaultsKey.provider,
            DefaultsKey.targetGrade,
            DefaultsKey.openAIModel,
            DefaultsKey.anthropicModel,
            DefaultsKey.ollamaModel,
            DefaultsKey.hiddenHighlightCategories
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    func model(for provider: AIProvider) -> String {
        switch provider {
        case .openAI: openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anthropic: anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)
        case .ollama: ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func apiKey(for provider: AIProvider) -> String? {
        guard let account = provider.keychainAccount else { return nil }
        return keychain.read(account: account)
    }

    func saveAPIKey(_ value: String, for provider: AIProvider) throws {
        guard let account = provider.keychainAccount else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(account: account)
        } else {
            try keychain.save(trimmed, account: account)
        }
        refreshKeyStatus()
    }

    func hasKey(for provider: AIProvider) -> Bool {
        switch provider {
        case .openAI: hasOpenAIKey
        case .anthropic: hasAnthropicKey
        case .ollama: !model(for: .ollama).isEmpty
        }
    }

    func isProviderReady(_ provider: AIProvider) -> Bool {
        !model(for: provider).isEmpty && (!provider.requiresAPIKey || hasKey(for: provider))
    }

    func isHighlightVisible(_ category: IssueCategory) -> Bool {
        !hiddenHighlightCategories.contains(category)
    }

    func toggleHighlight(_ category: IssueCategory) {
        if hiddenHighlightCategories.contains(category) {
            hiddenHighlightCategories.remove(category)
        } else {
            hiddenHighlightCategories.insert(category)
        }
    }

    private func refreshKeyStatus() {
        hasOpenAIKey = AIProvider.openAI.keychainAccount.flatMap { keychain.read(account: $0) } != nil
        hasAnthropicKey = AIProvider.anthropic.keychainAccount.flatMap { keychain.read(account: $0) } != nil
    }
}
