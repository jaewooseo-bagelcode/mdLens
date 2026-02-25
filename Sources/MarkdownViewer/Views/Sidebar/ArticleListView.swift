import SwiftUI

struct ArticleListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.articleFiles.isEmpty {
            ContentUnavailableView {
                Label("No Articles", systemImage: "doc.text")
            } description: {
                Text("Open a folder to see markdown files")
            }
        } else {
            List(appState.articleFiles, id: \.self) { url in
                Button {
                    appState.openFile(url: url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                        if let folder = relativePath(for: url) {
                            Text(folder)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.sidebar)
        }
    }

    private func relativePath(for url: URL) -> String? {
        guard let base = appState.currentFolderURL else { return nil }
        let basePath = base.path()
        let filePath = url.deletingLastPathComponent().path()
        if filePath == basePath { return nil }
        return String(filePath.dropFirst(basePath.count))
    }
}
