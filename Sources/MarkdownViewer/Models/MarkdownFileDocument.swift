import SwiftUI
import UniformTypeIdentifiers

/// Read-only markdown document for DocumentGroup. The framework loads the file
/// contents into `text`; the original file URL is provided separately via
/// `FileDocumentConfiguration.fileURL` (needed for relative-image baseURL).
struct MarkdownFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = {
        var types: [UTType] = [.plainText]
        for ext in ["md", "markdown", "mdown", "mkd"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        // Raw HTML: rendered directly in WKWebView (markdown pipeline bypassed).
        types.append(.html)
        return types
    }()

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    /// Viewer-only; DocumentGroup(viewing:) never writes. Required by protocol.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
