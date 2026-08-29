import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SystemCheckView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var beneparPack: BeneparLanguagePackManager
    @EnvironmentObject private var referenceLibrary: ReferenceLibraryStore
    @State private var report: SystemCheckReport?
    @State private var isRunning = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kistulentz System Check")
                        .font(.title2.weight(.semibold))
                    Text("A private, local check of this installation and its optional tools.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("System Check in progress")
                }
            }
            .padding(20)

            Divider()

            if let report {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(report.items) { item in
                            SystemCheckRow(item: item)
                        }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Checking this Mac…",
                    systemImage: "stethoscope",
                    description: Text("Kistulentz will not send writing or contact cloud AI providers.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack {
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("No writing, excerpts, keys, filenames, or paths are included", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Again") {
                    Task { await runCheck() }
                }
                .disabled(isRunning)
                Button("Export Diagnostic Report…") {
                    exportReport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(report == nil || isRunning)
            }
            .padding(16)
        }
        .frame(minWidth: 660, minHeight: 540)
        .task {
            if report == nil { await runCheck() }
        }
        .alert("Couldn’t export the report", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func runCheck() async {
        guard !isRunning else { return }
        isRunning = true
        message = nil
        report = await SystemCheckService.run(
            settings: settings,
            beneparPack: beneparPack,
            referenceLibrary: referenceLibrary
        )
        isRunning = false
    }

    private func exportReport() {
        guard let report else { return }
        let panel = NSSavePanel()
        panel.title = "Export Kistulentz Diagnostic Report"
        panel.nameFieldStringValue = "Kistulentz Diagnostics \(Date.now.formatted(.iso8601.year().month().day())).md"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try report.markdown().write(to: destination, atomically: true, encoding: .utf8)
            message = "Diagnostic report exported."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SystemCheckRow: View {
    let item: SystemCheckItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.status.symbolName)
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                    Spacer()
                    Text(item.status.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(color)
                }
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.status.title). \(item.detail)")
    }

    private var color: Color {
        switch item.status {
        case .passed: .green
        case .attention: .orange
        case .information: .secondary
        }
    }
}
