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
    @StateObject private var writingGrowth: WritingGrowthStore
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
        _writingGrowth = StateObject(wrappedValue: WritingGrowthStore(defaults: defaults))

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
        _writingGrowth = StateObject(wrappedValue: WritingGrowthStore())
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
                .environmentObject(writingGrowth)
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
                .environmentObject(writingGrowth)
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
/// A previous fix for quitting with every window already closed -- not just a genuine first-ever
/// launch -- was to have `applicationWillFinishLaunching` unconditionally call
/// `NSDocumentController.shared.openUntitledDocumentAndDisplay(true)`, ahead of DocumentGroup's
/// own "is there anything to resume" decision, so that decision never had a "nothing to resume"
/// condition left to trigger on. That fixed the system panel, but reproduced live against a real
/// installed build, it created a different, easy-to-miss regression: when restoration *did* have
/// something to resume (a normal quit with a saved document still open), secure state restoration
/// reopened that document *and* this unconditional call opened a second, genuinely blank untitled
/// document on top of it -- two separate `NSDocument`s, stacked at the exact same frame, so it
/// visually looked like a single window in every screenshot. Confirmed as two distinct windows via
/// `NSApplication`'s own window list (one carrying the restored document's file proxy icon, one
/// without), not a rendering artifact.
///
/// The natural-looking fix -- move the same call to `applicationDidFinishLaunching`, guarded by
/// `NSDocumentController.shared.documents.isEmpty` -- turned out to still be wrong, confirmed with
/// temporary debug logging of `documents.count` at each lifecycle point against a real installed
/// build: state restoration is asynchronous and had not completed by the time
/// `applicationDidFinishLaunching` ran (`documents.count` was still 0 there in both scenarios), so
/// the guard passed regardless of whether something was about to be restored, and the duplicate
/// returned. `NSApplication.didFinishRestoringWindowsNotification` is the actual, correct signal
/// for "restoration has finished" -- but logging confirmed it only fires when restoration *found*
/// something to restore; when a quit genuinely left nothing open, it never fires at all, so relying
/// on it alone would silently reintroduce the original system-panel bug for that case.
///
/// A second attempt fixed that: listen for `didFinishRestoringWindowsNotification` and a 600ms
/// fallback timer, whichever runs first opens an untitled document if `documents` is still empty
/// at that point, with a flag making the other one a no-op. That passed every test with a *blank*
/// restored document -- but re-tested against a real saved file (which needs an actual disk read
/// plus this app's own analysis pipeline before it is registered), the duplicate came back. Temporary
/// debug logging of `documents.count` at each step showed why: by the time either signal fired --
/// sometimes even by the very start of `applicationDidFinishLaunching` -- a second, blank document
/// already existed alongside the restoring real one. Neither signal's closure had run yet at that
/// point, which rules out this delegate's own code as the source; the remaining explanation is that
/// SwiftUI's `DocumentGroup` opens its own blank document very early in launch as part of its normal
/// scene-creation behavior, independent of and racing with restoration. Flipping
/// `applicationShouldOpenUntitledFile` to false to test that theory made no observed difference,
/// confirming DocumentGroup's own behavior isn't gated by that hook.
///
/// Since the extra document isn't one this delegate creates, tracking "the one I opened" (the first
/// attempt's flag) can't detect it. The actual fix settles on documents' *state* instead, from both
/// signals: if nothing is open at all, open an untitled document by hand (the "quit with zero
/// windows" case); if a file-backed document and an untouched blank one are both open, close the
/// blank one, whoever created it. Verified directly against a real installed build: quit with a
/// saved document open, relaunch, exactly one window, the restored file, even though the blank
/// document reliably appeared alongside it before settling ran; quit with every window closed,
/// relaunch, exactly one window (a fresh blank one, no system panel). `applicationShouldOpenUntitledFile`
/// returning true remains alongside this as the classic, documented AppKit hook for the same intent,
/// kept as a defensive measure even though it has no observed effect of its own either way.
///
/// A separate, related gap: reactivating an already-running Kistulentz with zero windows open --
/// clicking its Dock icon after closing every window without quitting, the classic "close the
/// window, don't quit" habit -- goes through neither `applicationWillFinishLaunching` nor
/// `applicationDidFinishLaunching` (the process never relaunches; nothing about launching runs
/// again). Reproduced live: without handling it, AppKit falls back to the same raw system "Open"
/// panel this whole delegate exists to avoid, just reached through the one lifecycle event that
/// was never covered. `applicationShouldHandleReopen(_:hasVisibleWindows:)` is the hook for
/// exactly this event; when there are no visible windows, it opens an untitled document itself
/// (the same call as the launch-time fix) and returns `false` so AppKit does not also run its own
/// default reopen handling on top of it. Verified directly: close every window without quitting,
/// reactivate via the Dock, Kistulentz's own Welcome/editor UI appears -- no system panel.
///
/// `DocumentGroupLaunchScene` -- Apple's real, purpose-built replacement for this whole fallback --
/// was investigated and ruled out earlier: it is `@available(iOS 18.0, visionOS 2.0, *)` and
/// explicitly `@available(macOS, unavailable)`, confirmed directly against this SDK's
/// SwiftUI.swiftinterface.
///
/// The decision `settleLaunchDocuments()` makes from whatever `NSDocumentController` reports is
/// pulled out as `LaunchDocumentSettlement.decide`, a pure function over plain document-state
/// tuples rather than real `NSDocument`s. `App/` is deliberately still counted in this project's
/// coverage baseline (see `check-coverage.sh`) precisely so untestable AppKit glue like this
/// delegate stays under pressure to shrink rather than being written off wholesale; this is that
/// pressure paying off; the AppKit calls this decision leads to remain here, thin and untested,
/// since they're the part that actually has to touch real documents and windows.
enum LaunchDocumentSettlement: Equatable {
    case openUntitledDocument
    case closeBlankDocuments
    case doNothing

    /// Mirrors the two `NSDocument` properties `settleLaunchDocuments()` actually reads --
    /// `fileURL != nil` and `isDocumentEdited` -- without depending on `NSDocument` itself.
    struct Document: Equatable {
        let hasFileURL: Bool
        let isEdited: Bool
    }

    static func decide(for documents: [Document]) -> LaunchDocumentSettlement {
        guard !documents.isEmpty else { return .openUntitledDocument }
        guard documents.contains(where: { $0.hasFileURL }) else { return .doNothing }
        guard documents.contains(where: { !$0.hasFileURL && !$0.isEdited }) else { return .doNothing }
        return .closeBlankDocuments
    }
}

@MainActor
final class KistulentzAppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true])
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A backstop, not the primary save path: each window's own `EditorWorkspace.onDisappear`
        // already calls `projectStore.saveNow()` on normal teardown. This flushes every open
        // project directly too, in case a window's SwiftUI teardown doesn't run (or hasn't
        // finished) before the process actually exits during Quit -- see OpenProjectRegistry.
        OpenProjectRegistry.shared.flushAll()
        DraftRecoveryManager.shared.endSession()
    }

    /// Settles what documents should be open once launch has had a chance to settle, checked both
    /// when secure state restoration signals it has finished and, since that notification never
    /// fires when a quit genuinely left nothing to restore, from a bounded fallback timer too. See
    /// this type's doc comment for why neither signal alone is sufficient.
    ///
    /// The settling logic itself is keyed off actual document state rather than which signal fired
    /// first, which matters because the untitled document that shows up alongside a slow-to-restore
    /// real one is not one this delegate opens itself -- logging confirmed SwiftUI's `DocumentGroup`
    /// can create its own blank document very early in launch, before either signal below runs, races
    /// restoration, and isn't gated by `applicationShouldOpenUntitledFile` (confirmed by observing no
    /// change with that hook returning `false`). So rather than tracking "the one I opened," settling
    /// prunes any blank, untouched, untitled document whenever a real, file-backed one is also open --
    /// whoever created it -- and only opens an untitled document itself when nothing is open at all.
    private var restorationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        restorationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` above guarantees this closure runs on the main thread, but its type
            // (unlike DispatchQueue.main's) isn't recognized by the compiler as MainActor-isolated,
            // so a synchronous call to a MainActor method here needs an explicit, zero-cost assertion
            // of what's already true at runtime rather than an unnecessary `Task { @MainActor in }` hop.
            MainActor.assumeIsolated {
                self?.settleLaunchDocuments()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(600)) { [weak self] in
            self?.settleLaunchDocuments()
        }
    }

    private func settleLaunchDocuments() {
        let documents = NSDocumentController.shared.documents
        switch LaunchDocumentSettlement.decide(for: documents.map {
            LaunchDocumentSettlement.Document(hasFileURL: $0.fileURL != nil, isEdited: $0.isDocumentEdited)
        }) {
        case .openUntitledDocument:
            _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        case .closeBlankDocuments:
            for document in documents where document.fileURL == nil && !document.isDocumentEdited {
                document.close()
            }
        case .doNothing:
            break
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        return false
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
