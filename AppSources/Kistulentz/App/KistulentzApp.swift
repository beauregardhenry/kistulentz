import AppKit
import SwiftUI

@main
struct KistulentzApp: App {
    @NSApplicationDelegateAdaptor(KistulentzAppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var beneparPack = BeneparLanguagePackManager()
    @StateObject private var customFonts: CustomFontStore
    @StateObject private var referenceLibrary: ReferenceLibraryStore
    @StateObject private var researchLibrary: ResearchLibraryStore
    @StateObject private var draftRecovery = DraftRecoveryManager.shared
#if UI_TEST_HOST
    @State private var uiTestDocument: MarkdownDocument
    @State private var uiTestUndoManager = UndoManager()
#endif

    init() {
#if UI_TEST_HOST
        let environment = ProcessInfo.processInfo.environment
        let defaults: UserDefaults
        if let suiteName = environment["KISTULENTZ_UI_TEST_DEFAULTS_SUITE"],
           !suiteName.isEmpty,
           let isolatedDefaults = UserDefaults(suiteName: suiteName) {
            defaults = isolatedDefaults
        } else {
            defaults = .standard
        }
        _referenceLibrary = StateObject(
            wrappedValue: ReferenceLibraryStore(defaults: defaults)
        )
        _researchLibrary = StateObject(
            wrappedValue: ResearchLibraryStore(defaults: defaults)
        )
        // .process scope registers a font only for this run, not the system-wide, persists-across-
        // launches registration a real "Add Font File" click uses -- a UI test exercising that
        // button must never leave a real font behind in Font Book on whatever Mac runs it.
        _customFonts = StateObject(wrappedValue: CustomFontStore(scope: .process))

        let text: String
        if let path = environment["KISTULENTZ_UI_TEST_DOCUMENT_PATH"],
           let loaded = try? String(contentsOfFile: path, encoding: .utf8) {
            text = loaded
        } else if let supplied = environment["KISTULENTZ_UI_TEST_DOCUMENT_TEXT"] {
            text = supplied
        } else {
            text = MarkdownDocument().text
        }
        _uiTestDocument = State(initialValue: MarkdownDocument(text: text))
#else
        _referenceLibrary = StateObject(wrappedValue: ReferenceLibraryStore())
        _researchLibrary = StateObject(wrappedValue: ResearchLibraryStore())
        _customFonts = StateObject(wrappedValue: CustomFontStore())
#endif
    }

    @SceneBuilder
    var body: some Scene {
#if UI_TEST_HOST
        WindowGroup("Kistulentz UI Test Workspace") {
            EditorWorkspace(
                document: $uiTestDocument,
                fileURL: ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_DOCUMENT_PATH"]
                    .map { URL(fileURLWithPath: $0) },
                suppliedUndoManager: uiTestUndoManager
            )
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
                .environmentObject(researchLibrary)
                .environmentObject(draftRecovery)
                .environmentObject(customFonts)
                .frame(minWidth: 1_120, minHeight: 680)
        }
        .commands {
            KistulentzSupportCommands()
            KistulentzPolishCommands()
        }
#else
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorWorkspace(document: file.$document, fileURL: file.fileURL)
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
                .environmentObject(researchLibrary)
                .environmentObject(draftRecovery)
                .environmentObject(customFonts)
                .frame(minWidth: 1_120, minHeight: 680)
        }
        .commands {
            KistulentzSupportCommands()
            KistulentzPolishCommands()
        }
#endif

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
                .environmentObject(customFonts)
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

/// A DocumentGroup-based Mac app can fall back to AppKit's own generic "nothing to resume, so ask
/// the user" panel -- the plain system Open dialog, complete with its own "New Document" button --
/// ahead of anything Kistulentz itself ever draws, Welcome landing page included. Reported
/// directly, then reproduced against a real installed build through repeated quit/relaunch cycles
/// (identically reproducible in Apple's own TextEdit under the same "nothing to resume" condition,
/// confirming this is normal AppKit/DocumentGroup behavior, not a Kistulentz-specific defect).
///
/// What actually helps, verified empirically against a real build:
/// - `applicationSupportsSecureRestorableState` returning true is the load-bearing fix. Since
///   macOS 12, AppKit treats an app delegate that omits this method as opting out of state
///   restoration -- without it, there is never anything to resume, so the "nothing to resume"
///   system panel appears on every single launch, not only a genuine first-ever one. This was
///   missed in the first pass at this fix (0.22.0): NSQuitAlwaysKeepsWindows and
///   applicationShouldOpenUntitledFile both only matter once restorable state exists in the first
///   place, and without this method it never did. Confirmed directly against a real installed
///   build: before this method existed, a saved document never reopened after a clean quit from
///   the menu -- the system panel appeared every time instead. After adding it, the same
///   quit/relaunch cycle reopens the last saved document automatically, with no system panel (a
///   ~/Library/Saved Application State/ directory for this bundle ID still does not appear either
///   way on this OS version -- DocumentGroup's document-resume path evidently does not depend on
///   that particular directory existing, whatever the underlying mechanism actually is).
/// - Registering NSQuitAlwaysKeepsWindows as a genuine NSUserDefaults default (not an Info.plist
///   declaration, which measurably did not change anything) additionally covers a user whose own
///   System Settings has "Close windows when quitting applications" on, which otherwise disables
///   window resumption process-wide for every app unless an app registers its own override.
/// - `applicationShouldOpenUntitledFile` returning true is the classic, documented AppKit hook for
///   exactly this case, kept as a defensive measure even though it did not, on its own, change the
///   observed behavior for SwiftUI's DocumentGroup in testing.
///
/// What this does NOT fix: a truly first-ever launch (nothing has ever existed to resume) can
/// still show the system panel once. `DocumentGroupLaunchScene` -- Apple's real, purpose-built
/// replacement for this fallback -- was investigated and ruled out: it is
/// `@available(iOS 18.0, visionOS 2.0, *)` and explicitly `@available(macOS, unavailable)`,
/// confirmed directly against this SDK's SwiftUI.swiftinterface. Eliminating the residual
/// first-launch case on macOS would mean replacing DocumentGroup with hand-rolled window and file
/// management -- a real rewrite, scoped separately, not folded into this fix.
@MainActor
final class KistulentzAppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true])
    }

    func applicationWillTerminate(_ notification: Notification) {
        DraftRecoveryManager.shared.endSession()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

private struct KistulentzPolishCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Polish Document") {
                NotificationCenter.default.post(name: .runAIReview, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

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
            Button("View Third-party Notices") {
                KistulentzLegal.openThirdPartyNotices()
            }
            Button("Kistulentz Source Code") {
                KistulentzLegal.openSourceCode()
            }
        }
        CommandGroup(after: .help) {
            Button("Welcome to Kistulentz…") {
                NotificationCenter.default.post(name: .showKistulentzWelcome, object: nil)
            }
            Button("What’s New in Kistulentz…") {
                NotificationCenter.default.post(name: .showKistulentzWhatsNew, object: nil)
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

    static func openThirdPartyNotices() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("THIRD_PARTY_NOTICES.md")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("THIRD_PARTY_NOTICES.md")

        if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
            NSWorkspace.shared.open(bundled)
        } else if FileManager.default.fileExists(atPath: development.path) {
            NSWorkspace.shared.open(development)
        } else {
            NSWorkspace.shared.open(sourceCodeURL.appendingPathComponent("blob/main/THIRD_PARTY_NOTICES.md"))
        }
    }

    static func openSourceCode() {
        NSWorkspace.shared.open(sourceCodeURL)
    }
}

extension Notification.Name {
    static let runAIReview = Notification.Name("Kistulentz.runAIReview")
    static let showKistulentzWelcome = Notification.Name("Kistulentz.showWelcome")
    static let showKistulentzWhatsNew = Notification.Name("Kistulentz.showWhatsNew")
    static let showDraftRecovery = Notification.Name("Kistulentz.showDraftRecovery")
}
