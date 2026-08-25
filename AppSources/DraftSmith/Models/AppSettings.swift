import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI
    case anthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    var keychainAccount: String {
        switch self {
        case .openAI: "openai-api-key"
        case .anthropic: "anthropic-api-key"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum DefaultsKey {
        static let provider = "selectedAIProvider"
        static let targetGrade = "targetReadingGrade"
        static let openAIModel = "openAIModel"
        static let anthropicModel = "anthropicModel"
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

        refreshKeyStatus()
    }

    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        guard let legacy = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        let keys = [
            DefaultsKey.provider,
            DefaultsKey.targetGrade,
            DefaultsKey.openAIModel,
            DefaultsKey.anthropicModel
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
        }
    }

    func apiKey(for provider: AIProvider) -> String? {
        keychain.read(account: provider.keychainAccount)
    }

    func saveAPIKey(_ value: String, for provider: AIProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(account: provider.keychainAccount)
        } else {
            try keychain.save(trimmed, account: provider.keychainAccount)
        }
        refreshKeyStatus()
    }

    func hasKey(for provider: AIProvider) -> Bool {
        switch provider {
        case .openAI: hasOpenAIKey
        case .anthropic: hasAnthropicKey
        }
    }

    private func refreshKeyStatus() {
        hasOpenAIKey = keychain.read(account: AIProvider.openAI.keychainAccount) != nil
        hasAnthropicKey = keychain.read(account: AIProvider.anthropic.keychainAccount) != nil
    }
}
