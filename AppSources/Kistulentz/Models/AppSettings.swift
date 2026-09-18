import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Hashable {
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
        static let hasAcknowledgedEnglishPackPrompt = "hasAcknowledgedEnglishPackPrompt"
        static let editorFontName = "editorFontName"
        static let editorFontSize = "editorFontSize"
        static let lastSeenAppVersion = "lastSeenAppVersion"
        static let lastOpenedProjectURL = "lastOpenedProjectURL"
        static let isPracticeModeEnabled = "isPracticeModeEnabled"
    }

    /// The lowest and highest editor font size a user can choose in Settings. Kept in one place
    /// so the stored-value clamp in `init` and the Settings stepper's range can't drift apart.
    static let editorFontSizeRange: ClosedRange<Double> = 12...32

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

    /// When on, flags whose category has a craft judgment behind it (see
    /// `IssueCategory.practicePrompt`) show their diagnosis and a prompt instead of a one-click
    /// fix -- Accept, per-issue Rewrite, Apply All, and Polish all withhold the replacement for
    /// those categories so the author practices the edit rather than outsourcing it. Categories
    /// without a craft judgment (spelling, grammar, continuity, an AI suggestion already reviewed
    /// through its own explicit flow) are unaffected either way.
    @Published var isPracticeModeEnabled: Bool {
        didSet { defaults.set(isPracticeModeEnabled, forKey: DefaultsKey.isPracticeModeEnabled) }
    }

    /// The editor's font, by font family name (as offered by the Settings picker, sourced from
    /// `NSFontManager.availableFontFamilies`). Empty means "use the system font" -- the same
    /// appearance every user already had before this preference existed.
    @Published var editorFontName: String {
        didSet { defaults.set(editorFontName, forKey: DefaultsKey.editorFontName) }
    }

    /// The editor's font point size. The Settings stepper is bounded to `editorFontSizeRange`, so
    /// values only fall outside it via a corrupted or hand-edited defaults file; `init` re-clamps
    /// on load rather than this setter clamping on every assignment.
    @Published var editorFontSize: Double {
        didSet { defaults.set(editorFontSize, forKey: DefaultsKey.editorFontSize) }
    }

    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var hasAcknowledgedEnglishPackPrompt: Bool
    @Published private(set) var lastSeenAppVersion: String?

    /// The most recently opened project's folder, so launch can reopen it automatically. A
    /// document-based Mac app's own window restoration only ever knows about the single generic
    /// Markdown document each window represents at the macOS level -- a Kistulentz project is a
    /// folder loaded on top of that window, invisible to AppKit, so without this, closing the app
    /// while a project is open silently loses the project on relaunch (the window still resumes,
    /// but back to whatever plain document it last represented, or nothing at all). Set on
    /// `activateProject()`, cleared on an explicit `closeProject()` so relaunch doesn't reopen a
    /// project the user chose to leave.
    @Published private(set) var lastOpenedProjectURL: URL?

    @Published private(set) var hasOpenAIKey = false
    @Published private(set) var hasAnthropicKey = false

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private var hasClaimedEnglishPackPromptThisLaunch = false

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
        editorFontName = defaults.string(forKey: DefaultsKey.editorFontName) ?? ""
        let savedFontSize = defaults.double(forKey: DefaultsKey.editorFontSize)
        editorFontSize = savedFontSize == 0
            ? 17
            : min(max(savedFontSize, Self.editorFontSizeRange.lowerBound), Self.editorFontSizeRange.upperBound)
        hasCompletedOnboarding = defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding)
        hasAcknowledgedEnglishPackPrompt = defaults.bool(
            forKey: DefaultsKey.hasAcknowledgedEnglishPackPrompt
        )
        lastSeenAppVersion = defaults.string(forKey: DefaultsKey.lastSeenAppVersion)
        lastOpenedProjectURL = defaults.url(forKey: DefaultsKey.lastOpenedProjectURL)
        isPracticeModeEnabled = defaults.bool(forKey: DefaultsKey.isPracticeModeEnabled)

        refreshKeyStatus()
    }

    private static func migrateLegacyDefaults(into defaults: UserDefaults) {
        guard let legacy = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        migrateLegacyDefaults(into: defaults, from: legacy)
    }

    static func migrateLegacyDefaults(into defaults: UserDefaults, from legacy: UserDefaults) {
        let keyMappings = [
            (DefaultsKey.provider, DefaultsKey.provider),
            (DefaultsKey.targetGrade, DefaultsKey.targetGrade),
            (DefaultsKey.openAIModel, DefaultsKey.openAIModel),
            (DefaultsKey.anthropicModel, DefaultsKey.anthropicModel),
            (DefaultsKey.ollamaModel, DefaultsKey.ollamaModel),
            (DefaultsKey.hiddenHighlightCategories, DefaultsKey.hiddenHighlightCategories),
            (DefaultsKey.hasCompletedOnboarding, DefaultsKey.hasCompletedOnboarding),
            (DefaultsKey.hasAcknowledgedEnglishPackPrompt, DefaultsKey.hasAcknowledgedEnglishPackPrompt),
            (DefaultsKey.editorFontName, DefaultsKey.editorFontName),
            (DefaultsKey.editorFontSize, DefaultsKey.editorFontSize),
            ("referenceLibraryFolder", "referenceLibraryFolder"),
            ("Kistulentz.researchLibraryLocation", "Kistulentz.researchLibraryLocation"),
            (
                "com.beauhenry.kistuletz.dismissedSuggestions.v1",
                "com.beauhenry.kistulentz.dismissedSuggestions.v1"
            )
        ]
        for (sourceKey, destinationKey) in keyMappings
        where defaults.object(forKey: destinationKey) == nil {
            if let value = legacy.object(forKey: sourceKey) {
                defaults.set(value, forKey: destinationKey)
            }
        }
    }

    static func appVersion(in bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    func shouldPresentWhatsNew(for appVersion: String) -> Bool {
        hasCompletedOnboarding && lastSeenAppVersion != appVersion
    }

    func acknowledgeWhatsNew(for appVersion: String) {
        lastSeenAppVersion = appVersion
        defaults.set(appVersion, forKey: DefaultsKey.lastSeenAppVersion)
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

    func acknowledgeEnglishPackPrompt() {
        hasAcknowledgedEnglishPackPrompt = true
        defaults.set(true, forKey: DefaultsKey.hasAcknowledgedEnglishPackPrompt)
    }

    func recordOpenedProject(url: URL) {
        lastOpenedProjectURL = url
        defaults.set(url, forKey: DefaultsKey.lastOpenedProjectURL)
    }

    func clearLastOpenedProject() {
        lastOpenedProjectURL = nil
        defaults.removeObject(forKey: DefaultsKey.lastOpenedProjectURL)
    }

    func claimEnglishPackPrompt() -> Bool {
        guard !hasAcknowledgedEnglishPackPrompt,
              !hasClaimedEnglishPackPromptThisLaunch else { return false }
        hasClaimedEnglishPackPromptThisLaunch = true
        return true
    }

    private func refreshKeyStatus() {
        hasOpenAIKey = AIProvider.openAI.keychainAccount.flatMap { keychain.read(account: $0) } != nil
        hasAnthropicKey = AIProvider.anthropic.keychainAccount.flatMap { keychain.read(account: $0) } != nil
    }
}
