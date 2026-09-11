import SwiftUI

@main
struct ClassicsPDFAssistantApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import PDF…") {
                    NotificationCenter.default.post(name: .importPDFRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

extension Notification.Name {
    static let importPDFRequested = Notification.Name("importPDFRequested")
}
