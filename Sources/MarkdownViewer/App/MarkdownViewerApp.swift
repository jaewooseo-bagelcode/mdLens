import SwiftUI

@main
struct MarkdownViewerApp: App {
    @State private var settings = AppSettings()
    @State private var slack = SlackController.shared

    init() {
        Updater.shared.start()
        // Opt-in: starts a Socket Mode listener only if tokens exist in the
        // Keychain. Unconfigured users stay a pure viewer (zero background).
        SlackController.shared.startIfConfigured()
    }

    var body: some Scene {
        DocumentGroup(viewing: MarkdownFileDocument.self) { config in
            DocumentView(text: config.document.text, fileURL: config.fileURL)
                .environment(settings)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .commands {
            AppCommands()
        }

        // Resident menu bar item, present only while the Slack listener is active.
        MenuBarExtra("mdLens Slack", systemImage: "eyes", isInserted: $slack.isActive) {
            SlackMenuView(controller: slack)
        }

        // "Connect Slack" setup window (opened from the app menu or menu bar item).
        Window("Connect Slack", id: slackSetupWindowID) {
            SlackSetupView(controller: slack)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
