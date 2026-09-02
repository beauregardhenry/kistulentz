import SwiftUI

struct WelcomeView: View {
    let onCreateProject: () -> Void
    let onOpenDocument: () -> Void
    let onImportDocuments: () -> Void
    let onOpenSample: (WritingProjectKind) -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome to Kistulentz")
                        .font(.largeTitle.bold())
                    Text("A local-first writing studio for Markdown documents and long-form projects.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    welcomeAction(
                        "Create a Project",
                        detail: "Start a fiction or nonfiction manuscript in a normal folder.",
                        systemImage: "folder.badge.plus",
                        action: onCreateProject
                    )
                    welcomeAction(
                        "Open a Document",
                        detail: "Open an existing Markdown or plain-text document.",
                        systemImage: "doc.text",
                        action: onOpenDocument
                    )
                }
                GridRow {
                    welcomeAction(
                        "Import Documents",
                        detail: "Preview and combine Markdown, Word, RTF, HTML, ODT, or text files.",
                        systemImage: "square.stack.3d.up.badge.a",
                        action: onImportDocuments
                    )
                    .gridCellColumns(2)
                }
            }

            GroupBox("Explore an editable sample") {
                HStack(spacing: 12) {
                    Button {
                        onOpenSample(.fiction)
                    } label: {
                        Label("Fiction Sample", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityHint("Creates an editable two-chapter fiction project in a folder you choose.")

                    Button {
                        onOpenSample(.nonfiction)
                    } label: {
                        Label("Nonfiction Sample", systemImage: "text.book.closed")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityHint("Creates an editable two-section nonfiction project in a folder you choose.")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }

            Label {
                Text("Readability, imports, project analysis, and recovery stay on this Mac. Writing is sent elsewhere only after you explicitly approve an OpenAI or Anthropic request. Ollama requests stay local.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.green)
            }
            .accessibilityElement(children: .combine)

            HStack {
                Text("You can reopen this window from the Help menu.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Continue to Editor", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 610)
    }

    private func welcomeAction(
        _ title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 28)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

struct EnglishPackPromptView: View {
    @EnvironmentObject private var beneparPack: BeneparLanguagePackManager

    let onNotNow: () -> Void
    let onInstalled: () -> Void

    @State private var installTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Enable Better Local Analysis")
                        .font(.title2.bold())
                    Text("Download Kistulentz’s English structural-analysis pack.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("More precise clause, phrase-depth, subordination, coordination, fragment, adverb, and passive-voice signals", systemImage: "checkmark.circle")
                Label("Automatically used after installation—there is no separate switch to remember", systemImage: "bolt.circle")
                Label("Runs entirely on this Mac and never uploads your writing", systemImage: "lock.shield")
            }
            .font(.callout)

            Text("The download includes a local runtime and the Benepar English model. It needs more than 1 GB of storage. Native Kistulentz analysis remains available if you choose Not Now.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if beneparPack.isInstalling {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                    Text(beneparPack.activityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if let error = beneparPack.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                if beneparPack.isInstalling {
                    Button("Cancel Download", role: .cancel) {
                        installTask?.cancel()
                    }
                } else {
                    Button("Not Now", role: .cancel, action: onNotNow)
                }
                Spacer()
                Button(beneparPack.errorMessage == nil ? "Download and Enable" : "Try Again") {
                    beneparPack.errorMessage = nil
                    installTask = Task {
                        await beneparPack.install()
                        if beneparPack.isInstalled { onInstalled() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(beneparPack.isInstalling)
            }
        }
        .padding(26)
        .frame(minWidth: 580, idealWidth: 620)
        .interactiveDismissDisabled(beneparPack.isInstalling)
        .onDisappear {
            if !beneparPack.isInstalled { installTask?.cancel() }
        }
    }
}
