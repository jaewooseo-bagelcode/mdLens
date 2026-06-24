import SwiftUI
import MarkdownCore

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            Form {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                HStack {
                    Text("Font Size")
                    Slider(value: $settings.fontSize, in: 12...24, step: 1) {
                        Text("Font Size")
                    }
                    Text("\(Int(settings.fontSize))pt")
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
