import SwiftUI

@main
struct MarkdownViewerApp: App {
    @State private var settings = AppSettings()

    init() {
        Updater.shared.start()
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

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
