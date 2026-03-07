import Foundation

struct MarkdownDocument: Equatable {
    let url: URL
    let content: String

    var fileName: String { url.lastPathComponent }
}
