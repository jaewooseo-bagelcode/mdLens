import Foundation

struct MarkdownDocument: Equatable {
    let url: URL
    let content: String
    let fileName: String
    let lastModified: Date?

    init(url: URL, content: String) {
        self.url = url
        self.content = content
        self.fileName = url.lastPathComponent
        self.lastModified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
