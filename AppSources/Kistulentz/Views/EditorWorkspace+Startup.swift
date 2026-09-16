import AppKit
import Foundation

// Split out of EditorWorkspace.swift: the first-run onboarding / repeat-launch landing-page flow
// (English pack prompt, Welcome, What's New, and Welcome's own "Create a Project"/"Open a
// Document"/"Import Documents"/sample actions). No behavior change from the move itself.
extension EditorWorkspace {
    /// A Kistulentz project is a folder loaded on top of the window's single underlying
    /// document; macOS's own window restoration only ever knows about that document, never the
    /// project, so it's silently lost across a normal quit/relaunch unless Kistulentz reopens it
    /// itself. Called from `onAppear` before `configureDraftRecovery()`, so recovery is evaluated
    /// against the reopened project rather than whatever blank/default document preceded it. A
    /// project that no longer exists at its saved location (moved, deleted, on an unmounted
    /// volume) fails silently -- the stale reference is cleared and launch continues as if there
    /// were none, rather than surfacing an error for something the user didn't just ask to do.
    ///
    /// Suppressed entirely under UI_TEST_HOST: tests that need a project open already have their
    /// own explicit, per-test mechanism (`configureUITestProjectIfNeeded`), and this automatic
    /// path reading whatever a previous local run happened to leave in the real, shared
    /// UserDefaults domain would make launch state nondeterministic between test runs.
    func reopenLastProjectIfNeeded() {
#if UI_TEST_HOST
        return
#else
        guard !projectStore.isOpen, let url = settings.lastOpenedProjectURL else { return }
        do {
            try projectStore.openProject(at: url)
            activateProject()
        } catch {
            settings.clearLastOpenedProject()
        }
#endif
    }

    func presentStartupIfNeeded() {
        guard !didPresentStartup else { return }
        didPresentStartup = true
        if !draftRecovery.pendingEntries.isEmpty {
            presentation.present(.draftRecovery)
        } else {
            presentNextStartupStep()
        }
    }

    func presentWelcomeAfterRecovery() {
        presentNextStartupStep()
    }

    /// Welcome now doubles as Kistulentz's landing page: once onboarding is complete, it's shown
    /// again on every later launch, in front of whatever document or project macOS's own window
    /// restoration reopens -- "Continue to Editor" is how you dismiss it and get to that work. The
    /// mandatory first-run branch (`!hasCompletedOnboarding`) is untouched and always wins: a user
    /// who has never onboarded always sees Welcome, independent of the landing-page suppression
    /// switch below (which exists only to keep existing tests landing straight in the editor, the
    /// way they did before repeat-launch landing pages existed).
    func presentNextStartupStep() {
        beneparPack.refresh()
        if !beneparPack.isInstalled, settings.claimEnglishPackPrompt() {
            presentation.present(.englishPackPrompt)
        } else if !settings.hasCompletedOnboarding {
            presentation.present(.welcome)
        } else if settings.shouldPresentWhatsNew(for: AppSettings.appVersion()) {
            presentation.present(.whatsNew)
        } else if Self.shouldPresentLandingPageOnLaunch {
            presentation.present(.welcome)
        }
    }

    /// Always true in production. Almost every existing interface test launches expecting to land
    /// directly in the editor -- exercising that setup, not this screen -- so the shared test
    /// harness suppresses the landing page by default via this environment variable, the same
    /// `#if UI_TEST_HOST` + env var convention used for every other test-only escape hatch in this
    /// app (see `MacFilePanel`, `KistulentzApp`'s font-registration scope, and so on).
    static var shouldPresentLandingPageOnLaunch: Bool {
#if UI_TEST_HOST
        ProcessInfo.processInfo.environment["KISTULENTZ_UI_TEST_SUPPRESS_LANDING_PAGE"] != "1"
#else
        true
#endif
    }

    func finishEnglishPackPrompt() {
        settings.acknowledgeEnglishPackPrompt()
        presentation.dismiss(.englishPackPrompt)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            presentNextStartupStep()
        }
    }

    func completeWelcome() {
        settings.completeOnboarding()
        settings.acknowledgeWhatsNew(for: AppSettings.appVersion())
        presentation.dismiss(.welcome)
    }

    func finishWhatsNew() {
        settings.acknowledgeWhatsNew(for: AppSettings.appVersion())
        presentation.dismiss(.whatsNew)
    }

    func beginProjectFromWelcome() {
        completeWelcome()
        requestProjectFolder(.createInParent)
    }

    func openDocumentFromWelcome() {
        completeWelcome()
        let panel = NSOpenPanel()
        panel.title = "Open a Markdown Document"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.markdownDocument, .plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImportedMarkdown(url)
    }

    func beginImportFromWelcome() {
        completeWelcome()
        presentation.present(.projectImportAssistant)
    }

    func createSampleProject(_ kind: WritingProjectKind) {
        completeWelcome()
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder for the \(kind.title) Sample"
        panel.message = "Kistulentz will create a new editable sample-project folder here without replacing existing files."
        panel.prompt = "Create Sample Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        do {
            let root = try SampleProjectBuilder.create(in: parent, kind: kind)
            try projectStore.openProject(at: root)
            activateProject()
        } catch {
            projectStore.errorMessage = error.localizedDescription
        }
    }
}
