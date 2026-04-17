import SwiftUI
import UniformTypeIdentifiers

struct AppCommands: Commands {
    @Bindable var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open...") {
                appState.isFileImporterPresented = true
            }
            .keyboardShortcut("o")

            Button("Open Folder...") {
                appState.isFolderImporterPresented = true
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Menu("Open Recent") {
                ForEach(appState.recentFiles, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        appState.openFile(url: url)
                    }
                }
                if !appState.recentFiles.isEmpty {
                    Divider()
                    Button("Clear Recent") {
                        appState.clearRecentFiles()
                    }
                }
            }
        }

        CommandGroup(replacing: .toolbar) {
            Button("Reload") {
                appState.reloadCurrentDocument()
            }
            .keyboardShortcut("r")
            .disabled(appState.currentDocument == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(appState.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                appState.isSidebarVisible.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Quick Open...") {
                appState.isQuickOpenPresented = true
            }
            .keyboardShortcut("p")
        }

        CommandGroup(after: .appSettings) {
            Divider()
            Button("Set as Default App for .md Files") {
                DefaultAppHelper.setAsDefault()
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
