import SwiftUI

@main
struct MarkdownViewerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 500)
                .onOpenURL { url in
                    appState.openFile(url: url)
                }
                .preferredColorScheme(appState.theme.colorScheme)
        }
        .commands {
            AppCommands(appState: appState)
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
