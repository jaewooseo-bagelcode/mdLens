import Foundation

struct FileTreeNode: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileTreeNode]?

    var isMarkdown: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown" || ext == "mkd"
    }
}
