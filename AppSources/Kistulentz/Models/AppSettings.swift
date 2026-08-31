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

struct AIModelChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let isRecommended: Bool

    var menuTitle: String {
        let recommendation = isRecommended ? " · Recommended" : ""
        return "\(name) — \(summary)\(recommendation)"
    }
}

enum AIModelCatalog {
    static let openAI: [AIModelChoice] = [
        AIModelChoice(
            id: "gpt-5.6-terra",
            name: "GPT-5.6 Terra",
            summary: "Balanced quality and cost",
            isRecommended: true
        ),
        AIModelChoice(
            id: "gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            summary: "Highest quality",
            isRecommended: false
        ),
        AIModelChoice(
            id: "gpt-5.6-luna",
            name: "GPT-5.6 Luna",
            summary: "Fastest and lowest cost",
            isRecommended: false
        )
    ]

    static let anthropic: [AIModelChoice] = [
        AIModelChoice(
            id: "claude-sonnet-5",
            name: "Claude Sonnet 5",
            summary: "Balanced speed and intelligence",
            isRecommended: true
        ),
        AIModelChoice(
            id: "claude-fable-5",
            name: "Claude Fable 5",
            summary: "Highest capability",
            isRecommended: false
        ),
        AIModelChoice(
            id: "claude-opus-4-8",
            name: "Claude Opus 4.8",
            summary: "Complex professional work",
            isRecommended: false
        ),
        AIModelChoice(
            id: "claude-haiku-4-5-20251001",
            name: "Claude Haiku 4.5",
            summary: "Fastest and lowest cost",
            isRecommended: false
        )
    ]

    static func choices(for provider: AIProvider) -> [AIModelChoice] {
        switch provider {
        case .openAI: openAI
        case .anthropic: anthropic
        case .ollama: []
        }
    }

    static func recommendedModel(for provider: AIProvider) -> String {
        choices(for: provider).first(where: \.isRecommended)?.id ?? ""
    }
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
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
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

    @Published private(set) var hasCompletedOnboarding: Bool

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
        openAIModel = defaults.string(forKey: DefaultsKey.openAIModel)
            ?? AIModelCatalog.recommendedModel(for: .openAI)
        anthropicModel = defaults.string(forKey: DefaultsKey.anthropicModel)
            ?? AIModelCatalog.recommendedModel(for: .anthropic)
        ollamaModel = defaults.string(forKey: DefaultsKey.ollamaModel) ?? ""
        hiddenHighlightCategories = Set(
            (defaults.stringArray(forKey: DefaultsKey.hiddenHighlightCategories) ?? [])
                .compactMap(IssueCategory.init(rawValue:))
        )
        hasCompletedOnboarding = defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding)

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
            DefaultsKey.hiddenHighlightCategories,
            DefaultsKey.hasCompletedOnboarding
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

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: DefaultsKey.hasCompletedOnboarding)
    }

    private func refreshKeyStatus() {
        hasOpenAIKey = AIProvider.openAI.keychainAccount.flatMap { keychain.read(account: $0) } != nil
        hasAnthropicKey = AIProvider.anthropic.keychainAccount.flatMap { keychain.read(account: $0) } != nil
    }
}
