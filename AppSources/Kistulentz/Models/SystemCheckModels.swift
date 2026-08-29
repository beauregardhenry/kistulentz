import Foundation

enum SystemCheckStatus: String, Equatable {
    case passed
    case attention
    case information

    var title: String {
        switch self {
        case .passed: "Ready"
        case .attention: "Needs attention"
        case .information: "Optional"
        }
    }

    var symbolName: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .information: "info.circle.fill"
        }
    }
}

struct SystemCheckItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let status: SystemCheckStatus
}

struct SystemCheckReport: Equatable {
    let generatedAt: Date
    let appVersion: String
    let buildNumber: String
    let bundleIdentifier: String
    let macOSVersion: String
    let architecture: String
    let items: [SystemCheckItem]

    var attentionCount: Int {
        items.count { $0.status == .attention }
    }

    func markdown() -> String {
        let formatter = ISO8601DateFormatter()
        var text = """
        # Kistulentz System Check

        - Generated: \(formatter.string(from: generatedAt))
        - Kistulentz: \(appVersion) (build \(buildNumber))
        - Bundle identifier: \(bundleIdentifier)
        - macOS: \(macOSVersion)
        - Architecture: \(architecture)
        - Result: \(attentionCount == 0 ? "No required problems found" : "\(attentionCount) item\(attentionCount == 1 ? " needs" : "s need") attention")

        """

        for status in [SystemCheckStatus.attention, .passed, .information] {
            let matchingItems = items.filter { $0.status == status }
            guard !matchingItems.isEmpty else { continue }
            text += "## \(status.title)\n\n"
            for item in matchingItems {
                text += "### \(item.title)\n\n\(item.detail)\n\n"
            }
        }

        text += """
        ## Privacy

        This report was generated locally. It intentionally excludes document and manuscript text, EPUB excerpts, book and document titles, filenames and paths, API keys, account identifiers, and AI model names. Kistulentz did not contact OpenAI or Anthropic while running this check.
        """
        return text + "\n"
    }
}
