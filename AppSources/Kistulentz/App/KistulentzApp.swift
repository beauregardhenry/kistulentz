import AppKit
import SwiftUI

@main
struct KistulentzApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var beneparPack = BeneparLanguagePackManager()
    @StateObject private var referenceLibrary = ReferenceLibraryStore()
    @StateObject private var researchLibrary = ResearchLibraryStore()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorWorkspace(document: file.$document, fileURL: file.fileURL)
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .environmentObject(referenceLibrary)
                .environmentObject(researchLibrary)
                .frame(minWidth: 1_120, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("View Kistulentz License") {
                    KistulentzLegal.openLicense()
                }
                Button("Kistulentz Source Code") {
                    KistulentzLegal.openSourceCode()
                }
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Run AI Review") {
                    NotificationCenter.default.post(name: .runAIReview, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(beneparPack)
                .frame(width: 540)
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
}
