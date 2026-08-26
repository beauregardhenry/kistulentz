import SwiftUI

@main
struct KistulentzApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var referenceLibrary = ReferenceLibraryStore()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorWorkspace(document: file.$document, fileURL: file.fileURL)
                .environmentObject(settings)
                .environmentObject(referenceLibrary)
                .frame(minWidth: 1_120, minHeight: 680)
        }
        .commands {
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
                .frame(width: 540)
        }
    }
}

extension Notification.Name {
    static let runAIReview = Notification.Name("Kistulentz.runAIReview")
}
