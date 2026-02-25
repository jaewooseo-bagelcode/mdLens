import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: Binding(
            get: { appState.isSidebarVisible ? .doubleColumn : .detailOnly },
            set: { appState.isSidebarVisible = ($0 != .detailOnly) }
        )) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            VStack(spacing: 0) {
                if appState.currentDocument != nil {
                    DocumentView()
                    StatusBarView()
                } else {
                    EmptyStateView()
                }
            }
        }
        .navigationTitle(appState.currentDocument?.fileName ?? "mdLens")
        .fileImporter(
            isPresented: $appState.isFileImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "md")!, UTType(filenameExtension: "markdown")!, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                appState.openFile(url: url)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: appState.isFolderImporterPresented) { _, isPresented in
            if isPresented {
                openFolderPanel()
            }
        }
        .sheet(isPresented: $appState.isQuickOpenPresented) {
            QuickOpenPanel(isPresented: $appState.isQuickOpenPresented)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" || ext == "mdown" || ext == "mkd" {
                DispatchQueue.main.async {
                    appState.openFile(url: url)
                }
            }
        }
        return true
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing markdown files"
        panel.begin { response in
            appState.isFolderImporterPresented = false
            if response == .OK, let url = panel.url {
                appState.openFolder(url: url)
            }
        }
    }
}
