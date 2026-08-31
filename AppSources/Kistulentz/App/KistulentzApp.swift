import AppKit
import SwiftUI

@main
struct KistulentzApp: App {
    @NSApplicationDelegateAdaptor(KistulentzAppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var beneparPack = BeneparLanguagePackManager()
    @StateObject private var referenceLibrary = ReferenceLibraryStore()
    @StateObject private var researchLibrary = ResearchLibraryStore()
    @StateObject private var draftRecovery = DraftRecoveryManager.shared

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorWorkspace(document: file.$document, fileURL: file.fileURL)
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
                .environmentObject(researchLibrary)
                .environmentObject(draftRecovery)
                .frame(minWidth: 1_120, minHeight: 680)
        }
        .commands {
            KistulentzSupportCommands()
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Polish Document") {
                    NotificationCenter.default.post(name: .runAIReview, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
                .frame(width: 540)
        }

        Window("Kistulentz System Check", id: "system-check") {
            SystemCheckView()
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
        }
        .defaultSize(width: 700, height: 620)

    }

}

@MainActor
final class KistulentzAppDelegate: NSObject, NSApplicationDelegate {
#if UI_TEST_HOST
    private var uiTestWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["KISTULENTZ_UI_TESTING"] == "1" else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_120, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kistulentz UI Test Workspace"
        window.center()
        window.contentView = NSHostingView(rootView: KistulentzUITestWorkspace())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        uiTestWindow = window
    }
#endif

    func applicationWillTerminate(_ notification: Notification) {
        DraftRecoveryManager.shared.endSession()
    }
}

#if UI_TEST_HOST
private struct KistulentzUITestWorkspace: View {
    @State private var document = MarkdownDocument()
    @StateObject private var settings = AppSettings()
    @StateObject private var beneparPack = BeneparLanguagePackManager()
    @StateObject private var referenceLibrary = ReferenceLibraryStore()
    @StateObject private var researchLibrary = ResearchLibraryStore()
    @StateObject private var draftRecovery = DraftRecoveryManager.shared

    var body: some View {
        EditorWorkspace(document: $document, fileURL: nil)
            .environmentObject(settings)
            .environmentObject(beneparPack)
            .environmentObject(referenceLibrary)
            .environmentObject(researchLibrary)
            .environmentObject(draftRecovery)
            .frame(minWidth: 1_120, minHeight: 680)
    }
}
#endif

private struct KistulentzSupportCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Kistulentz System Check…") {
                openWindow(id: "system-check")
            }
            Divider()
            Button("View Kistulentz License") {
                KistulentzLegal.openLicense()
            }
            Button("Kistulentz Source Code") {
                KistulentzLegal.openSourceCode()
            }
        }
        CommandGroup(after: .help) {
            Button("Welcome to Kistulentz…") {
                NotificationCenter.default.post(name: .showKistulentzWelcome, object: nil)
            }
            Button("Draft Recovery…") {
                NotificationCenter.default.post(name: .showDraftRecovery, object: nil)
            }
        }
    }
}

private enum KistulentzLegal {
    private static let sourceCodeURL = URL(string: "https://github.com/beauregardhenry/kistulentz")!

    static func openLicense() {
        let bundledLicense = Bundle.main.resourceURL?.appendingPathComponent("LICENSE")
        let developmentLicense = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("LICENSE")

        if let bundledLicense, FileManager.default.fileExists(atPath: bundledLicense.path) {
            NSWorkspace.shared.open(bundledLicense)
        } else if FileManager.default.fileExists(atPath: developmentLicense.path) {
            NSWorkspace.shared.open(developmentLicense)
        } else {
            NSWorkspace.shared.open(sourceCodeURL.appendingPathComponent("blob/main/LICENSE"))
        }
    }

    static func openSourceCode() {
        NSWorkspace.shared.open(sourceCodeURL)
    }
}

extension Notification.Name {
    static let runAIReview = Notification.Name("Kistulentz.runAIReview")
    static let showKistulentzWelcome = Notification.Name("Kistulentz.showWelcome")
    static let showDraftRecovery = Notification.Name("Kistulentz.showDraftRecovery")
}
