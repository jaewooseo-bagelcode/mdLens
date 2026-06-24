import SwiftUI

/// Window scene id for the "Connect Slack" setup window.
let slackSetupWindowID = "slack-setup"

/// Contents of the menu bar item shown while the Slack listener is active.
struct SlackMenuView: View {
    let controller: SlackController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.statusText)

        Divider()

        Button("Reconnect…") {
            openWindow(id: slackSetupWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Create Slack App (manifest)…") {
            ManifestService.openCreateApp()
        }

        Divider()

        Button("Disconnect Slack") {
            controller.disconnect()
        }

        Divider()

        Button("Quit mdLens") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
