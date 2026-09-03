import SwiftUI

struct DestinkSelection {
    let text: String
    let range: NSRange
}

struct DestinkView: View {
    let currentDocument: ManuscriptDocument
    let selection: DestinkSelection?
    let manuscriptDocuments: [ManuscriptDocument]?
    let onNavigate: (String, NSRange) -> Void

    @EnvironmentObject private var beneparPack: BeneparLanguagePackManager
    @Environment(\.dismiss) private var dismiss
    @State private var scope: BetaReaderScope
    @State private var report: DestinkReport?
    @State private var selectedTier: DestinkTier?
    @State private var isRunning = false
    @State private var runID = UUID()

    init(
        currentDocument: ManuscriptDocument,
        selection: DestinkSelection?,
        manuscriptDocuments: [ManuscriptDocument]?,
        onNavigate: @escaping (String, NSRange) -> Void
    ) {
        self.currentDocument = currentDocument
        self.selection = selection
        self.manuscriptDocuments = manuscriptDocuments
        self.onNavigate = onNavigate
        _scope = State(initialValue: selection == nil ? .chapter : .selection)
    }

    private var availableScopes: [BetaReaderScope] {
        var scopes: [BetaReaderScope] = []
        if selection != nil { scopes.append(.selection) }
        scopes.append(.chapter)
        if manuscriptDocuments != nil { scopes.append(.manuscript) }
        return scopes
    }

    private var visibleDocuments: [DestinkDocumentReport] {
        guard let report else { return [] }
        guard let selectedTier else { return report.documents }
        return report.documents.compactMap { document in
            let findings = document.findings.filter { $0.tier == selectedTier }
            guard !findings.isEmpty else { return nil }
            return DestinkDocumentReport(
                relativePath: document.relativePath,
                title: document.title,
                wordCount: document.wordCount,
                findings: findings,
                usedBenepar: document.usedBenepar
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("De-stink Review")
                        .font(.title2.weight(.semibold))
                    Text("A deterministic local check for stock phrasing, staged sentence shapes, formatting tics, and repetitive rhythm.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Review only: this screen never changes your prose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(16)

            HStack(spacing: 12) {
                Picker("Scope", selection: $scope) {
                    ForEach(availableScopes) { item in
                        Text(item == .chapter && manuscriptDocuments == nil ? "Document" : item.title)
                            .tag(item)
                    }
                }
                .frame(width: 230)

                if isRunning {
                    ProgressView().controlSize(.small)
                    Text("Checking locally…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        runID = UUID()
                    } label: {
                        Label("Run Again", systemImage: "arrow.clockwise")
                    }
                }

                Spacer()

                Label(
                    beneparPack.isInstalled ? "Benepar structural pass available" : "Native rules only — English pack not installed",
                    systemImage: beneparPack.isInstalled ? "checkmark.circle.fill" : "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if let report {
                VStack(spacing: 0) {
                    summary(report)
                    Divider()
                    resultList(report)
                }
            } else if isRunning {
                ContentUnavailableView(
                    "Reading the prose",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Kistulentz is running the local rule set and, when available, Benepar sentence parsing.")
                )
            } else {
                ContentUnavailableView("No report", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: 940, minHeight: 680)
        .task(id: runID) { await run() }
        .onChange(of: scope) { _, _ in
            report = nil
            runID = UUID()
        }
    }

    private func summary(_ report: DestinkReport) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 1) {
                Text(report.score.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("weighted findings / 1,000 words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("De-stink score \(report.score.formatted(.number.precision(.fractionLength(1)))) weighted findings per one thousand words")

            Divider().frame(height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(report.findingCount) finding\(report.findingCount == 1 ? "" : "s")")
                    .font(.headline)
                Text("\(report.wordCount.formatted()) words · \(report.documents.count) document\(report.documents.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Category", selection: $selectedTier) {
                Text("All categories").tag(DestinkTier?.none)
                ForEach(DestinkTier.allCases) { tier in
                    Text("\(tier.title) · \(report.findings.count { $0.tier == tier })")
                        .tag(DestinkTier?.some(tier))
                }
            }
            .frame(width: 250)
        }
        .padding(16)
    }

    @ViewBuilder
    private func resultList(_ report: DestinkReport) -> some View {
        if report.findingCount == 0 {
            ContentUnavailableView(
                "No structural or stylistic tells found",
                systemImage: "checkmark.seal",
                description: Text("A clean score is not a claim that the prose is good; it only means this rule set found none of the patterns it can name.")
            )
        } else if visibleDocuments.isEmpty {
            ContentUnavailableView("No findings in this category", systemImage: "line.3.horizontal.decrease.circle")
        } else {
            List {
                ForEach(visibleDocuments) { document in
                    Section {
                        ForEach(document.findings) { finding in
                            findingRow(finding, document: document)
                        }
                    } header: {
                        HStack {
                            Text(document.title)
                            Spacer()
                            Text("\(document.findings.count) · score \(document.score.formatted(.number.precision(.fractionLength(1))))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func findingRow(_ finding: DestinkFinding, document: DestinkDocumentReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(finding.severity.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(finding.severity.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(finding.severity.color.opacity(0.12), in: Capsule())
                Text(finding.tier.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if finding.usedBenepar {
                    Label("Parsed", systemImage: "tree")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show in Document") {
                    var range = finding.range
                    if scope == .selection, let selection {
                        range.location += selection.range.location
                    }
                    dismiss()
                    onNavigate(document.relativePath, range)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show \(finding.message) in \(document.title)")
            }
            Text(finding.message)
                .font(.headline)
            Text(finding.excerpt.replacingOccurrences(of: "\n", with: " "))
                .font(.system(.callout, design: .serif))
                .lineLimit(3)
                .textSelection(.enabled)
            Text(finding.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
    }

    private func documentsForRun() -> [ManuscriptDocument] {
        switch scope {
        case .selection:
            guard let selection else { return [currentDocument] }
            return [ManuscriptDocument(
                relativePath: currentDocument.relativePath,
                title: "Selection in \(currentDocument.title)",
                text: selection.text
            )]
        case .chapter:
            return [currentDocument]
        case .manuscript:
            return manuscriptDocuments ?? [currentDocument]
        }
    }

    @MainActor
    private func run() async {
        let id = runID
        isRunning = true
        let documents = documentsForRun()
        let result = await DestinkService.analyze(
            documents: documents,
            useBenepar: beneparPack.isInstalled
        )
        guard !Task.isCancelled else {
            // Only clear the spinner when no later run has already claimed it.
            if runID == id { isRunning = false }
            return
        }
        report = result
        isRunning = false
    }
}

private extension DestinkSeverity {
    var color: Color {
        switch self {
        case .candidate: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}
