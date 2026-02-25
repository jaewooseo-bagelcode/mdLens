import SwiftUI

struct FileTreeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.fileTree.isEmpty {
            ContentUnavailableView {
                Label("No Folder Open", systemImage: "folder")
            } description: {
                Text("Open a folder to browse files")
            }
        } else {
            List {
                ForEach(appState.fileTree) { node in
                    FileTreeNodeView(node: node)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct FileTreeNodeView: View {
    let node: FileTreeNode
    @Environment(AppState.self) private var appState

    var body: some View {
        if node.isDirectory {
            DisclosureGroup {
                if let children = node.children {
                    ForEach(children) { child in
                        FileTreeNodeView(node: child)
                    }
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .foregroundStyle(.primary)
            }
        } else {
            Button {
                appState.openFile(url: node.url)
            } label: {
                Label(node.name, systemImage: node.isMarkdown ? "doc.text" : "doc")
                    .foregroundStyle(node.isMarkdown ? .primary : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
