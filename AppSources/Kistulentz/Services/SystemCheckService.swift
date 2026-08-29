import Foundation

@MainActor
enum SystemCheckService {
    static func run(
        settings: AppSettings,
        beneparPack: BeneparLanguagePackManager,
        referenceLibrary: ReferenceLibraryStore,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) async -> SystemCheckReport {
        beneparPack.refresh()
        var items: [SystemCheckItem] = [
            SystemCheckItem(
                id: "native-analysis",
                title: "Native writing analysis",
                detail: "Readability, spelling, grammar, and Kistulentz’s built-in writing checks are available without an internet connection.",
                status: .passed
            ),
            markdownDocumentCheck(bundle: bundle),
            providerCheck(settings: settings),
            referenceLibraryCheck(referenceLibrary),
            publishingToolCheck(fileManager: fileManager)
        ]

        items.append(await languagePackCheck(state: beneparPack.state))
        items.append(await ollamaCheck())

        return SystemCheckReport(
            generatedAt: Date(),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development",
            bundleIdentifier: bundle.bundleIdentifier ?? "com.beauhenry.kistulentz",
            macOSVersion: processInfo.operatingSystemVersionString,
            architecture: BeneparLanguagePackLocator.architecture,
            items: items
        )
    }

    nonisolated static func declaresMarkdownDocuments(infoDictionary: [String: Any]?) -> Bool {
        guard let documentTypes = infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return false
        }
        return documentTypes.contains { declaration in
            let extensions = declaration["CFBundleTypeExtensions"] as? [String] ?? []
            let contentTypes = declaration["LSItemContentTypes"] as? [String] ?? []
            return extensions.contains(where: { ["md", "markdown", "mdown"].contains($0.lowercased()) })
                && contentTypes.contains("net.daringfireball.markdown")
        }
    }

    private static func markdownDocumentCheck(bundle: Bundle) -> SystemCheckItem {
        let declared = declaresMarkdownDocuments(infoDictionary: bundle.infoDictionary)
        return SystemCheckItem(
            id: "markdown-documents",
            title: "Markdown document support",
            detail: declared
                ? "The application declares support for opening and editing .md, .markdown, and .mdown files."
                : "This build does not declare complete Markdown document support. Reinstall an official Kistulentz build before reporting a file-opening problem.",
            status: declared ? .passed : .attention
        )
    }

    private static func providerCheck(settings: AppSettings) -> SystemCheckItem {
        let configured = [
            settings.isProviderReady(.openAI) ? "OpenAI" : nil,
            settings.isProviderReady(.anthropic) ? "Anthropic" : nil,
            settings.isProviderReady(.ollama) ? "Ollama" : nil
        ].compactMap { $0 }
        let detail = configured.isEmpty
            ? "No optional AI provider is fully configured. All local writing analysis remains available."
            : "Configured providers: \(configured.joined(separator: ", ")). Cloud providers were not contacted."
        return SystemCheckItem(
            id: "ai-providers",
            title: "Optional AI providers",
            detail: detail,
            status: configured.isEmpty ? .information : .passed
        )
    }

    private static func referenceLibraryCheck(_ library: ReferenceLibraryStore) -> SystemCheckItem {
        guard let rootURL = library.rootURL else {
            return SystemCheckItem(
                id: "reference-library",
                title: "Reference Library",
                detail: "No Reference Library folder is selected. EPUB analysis remains available after an author chooses a local folder.",
                status: .information
            )
        }
        let structuralProfiles = library.books.count { $0.profile.structuralProfile != nil }
        let writable = FileManager.default.isWritableFile(atPath: rootURL.path)
        return SystemCheckItem(
            id: "reference-library",
            title: "Reference Library",
            detail: "\(library.books.count) book\(library.books.count == 1 ? "" : "s") indexed; \(structuralProfiles) structural profile\(structuralProfiles == 1 ? "" : "s") cached. Automatic checkpoints are \(writable ? "available" : "blocked because the selected folder is not writable").",
            status: writable ? .passed : .attention
        )
    }

    private static func languagePackCheck(state: BeneparLanguagePackState) async -> SystemCheckItem {
        switch state {
        case .notInstalled:
            return SystemCheckItem(
                id: "english-language-pack",
                title: "English structural-analysis pack",
                detail: "The optional Benepar pack is not installed. Native analysis remains available, and the pack can be installed from Settings.",
                status: .information
            )
        case .invalid:
            return SystemCheckItem(
                id: "english-language-pack",
                title: "English structural-analysis pack",
                detail: "The installed pack needs repair. Remove it in Settings, then install it again. Native analysis remains available.",
                status: .attention
            )
        case .installed(let version, let installedBytes):
            let analysis = await BeneparService.shared.analyzeIfAvailable(
                text: "Although the rain had stopped, the road remained difficult to cross.",
                maximumSentences: 2,
                includeIssues: false,
                waitForAvailability: true
            )
            guard analysis != nil else {
                return SystemCheckItem(
                    id: "english-language-pack",
                    title: "English structural-analysis pack",
                    detail: "English pack \(version) is installed, but its local worker did not complete the built-in test. Remove and reinstall the pack in Settings.",
                    status: .attention
                )
            }
            let size = installedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return SystemCheckItem(
                id: "english-language-pack",
                title: "English structural-analysis pack",
                detail: "English pack \(version) passed a local worker test\(size.map { " and uses approximately \($0)" } ?? ""). No author text was used.",
                status: .passed
            )
        }
    }

    private static func ollamaCheck() async -> SystemCheckItem {
        do {
            let models = try await OllamaService().installedModels()
            return SystemCheckItem(
                id: "ollama",
                title: "Ollama local AI",
                detail: models.isEmpty
                    ? "Ollama is running locally, but no models were reported."
                    : "Ollama is running locally with \(models.count) installed model\(models.count == 1 ? "" : "s"). Model names are excluded from this report.",
                status: models.isEmpty ? .information : .passed
            )
        } catch {
            return SystemCheckItem(
                id: "ollama",
                title: "Ollama local AI",
                detail: "Ollama is not running on this Mac. This is optional and does not affect native analysis or configured cloud providers.",
                status: .information
            )
        }
    }

    private static func publishingToolCheck(fileManager: FileManager) -> SystemCheckItem {
        var tools: [String] = []
        let executablePaths = ["/opt/homebrew/bin/epubcheck", "/usr/local/bin/epubcheck"]
        if executablePaths.contains(where: fileManager.isExecutableFile(atPath:)) {
            tools.append("EPUBCheck")
        }
        if ["/Applications/Kindle Previewer 3.app", "/Applications/Kindle Previewer.app"]
            .contains(where: fileManager.fileExists(atPath:)) {
            tools.append("Kindle Previewer")
        }
        if fileManager.fileExists(atPath: "/Applications/Transporter.app") {
            tools.append("Apple Transporter")
        }
        return SystemCheckItem(
            id: "publishing-tools",
            title: "Optional publishing validators",
            detail: tools.isEmpty
                ? "No external publishing validators were found. Kistulentz export still works, but retailer and EPUB validation remains an author step."
                : "Detected locally: \(tools.joined(separator: ", ")).",
            status: tools.isEmpty ? .information : .passed
        )
    }
}
