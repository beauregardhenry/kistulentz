import SwiftUI

@main
struct KistuletzApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorWorkspace(document: file.$document, fileURL: file.fileURL)
                .environmentObject(settings)
                .frame(minWidth: 1_060, minHeight: 680)
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
    static let runAIReview = Notification.Name("Kistuletz.runAIReview")
}
