import SwiftUI
import UniformTypeIdentifiers

struct AppCommands: Commands {
    @FocusedValue(\.reloadAction) private var reloadAction
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // DocumentGroup supplies New / Open / Open Recent natively.
        CommandGroup(replacing: .toolbar) {
            Button("Reload") {
                reloadAction?()
            }
            .keyboardShortcut("r")
            .disabled(reloadAction == nil)
        }

        CommandGroup(after: .appSettings) {
            Divider()
            Button("Set as Default App for .md Files") {
                DefaultAppHelper.setAsDefault()
            }
            Button("Connect Slack…") {
                openWindow(id: slackSetupWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

enum DefaultAppHelper {
    static func setAsDefault() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sugarscone.mdlens"
        let utis = [
            "net.daringfireball.markdown",
            "public.plain-text",
        ]

        for uti in utis {
            LSSetDefaultRoleHandlerForContentType(uti as CFString, .viewer, bundleID as CFString)
        }

        let alert = NSAlert()
        alert.messageText = "mdLens is now the default viewer"
        alert.informativeText = ".md files will open with mdLens."
        alert.alertStyle = .informational
        alert.runModal()
    }
}
