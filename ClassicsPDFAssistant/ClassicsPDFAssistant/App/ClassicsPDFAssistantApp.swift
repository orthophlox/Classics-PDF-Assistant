import Sparkle
import SwiftUI

@main
struct ClassicsPDFAssistantApp: App {
    @StateObject private var appState = AppState()

    // Starts Sparkle's background update-checking immediately (subject to
    // Info.plist's SUEnableAutomaticChecks/SUScheduledCheckInterval); see
    // README.md "자동 업데이트 설정하기" for the signing/appcast setup this
    // needs before it can find and install a real update.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .appSettings) {
                Divider()
                Button("Uninstall Classics PDF Assistant…") {
                    UninstallFlow.run()
                }
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
