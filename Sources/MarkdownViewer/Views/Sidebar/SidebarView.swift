import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            Picker("", selection: $appState.sidebarTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Image(systemName: tab.icon)
                        .help(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch appState.sidebarTab {
            case .files:
                FileTreeView()
            case .outline:
                OutlineView()
            case .articles:
                ArticleListView()
            }
        }
    }
}
