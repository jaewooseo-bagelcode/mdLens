import SwiftUI
import MarkdownCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView {
            Form {
                Picker("Theme", selection: $appState.theme) {
                    ForEach(AppThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                HStack {
                    Text("Font Size")
                    Slider(value: $appState.fontSize, in: 12...24, step: 1) {
                        Text("Font Size")
                    }
                    Text("\(Int(appState.fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            .padding(20)
        }
        .frame(width: 400, height: 180)
    }
}
