import Foundation

struct FileTreeNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeNode]?

    var name: String { url.lastPathComponent }

    var isMarkdown: Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }
}
