import SwiftUI
import Combine
import MarkdownCore

enum SidebarTab: String, CaseIterable {
    case files = "Files"
    case outline = "Outline"
    case articles = "Articles"

    var icon: String {
        switch self {
        case .files: return "folder"
        case .outline: return "list.bullet.indent"
        case .articles: return "doc.text"
        }
    }
}

@Observable
final class AppState {
    var currentDocument: MarkdownDocument?
    var currentFolderURL: URL?
    var fileTree: [FileTreeNode] = []
    var outline: [OutlineItem] = []
    var stats: DocumentStats?
    var sidebarTab: SidebarTab = .outline
    var isSidebarVisible: Bool = false
    var recentFiles: [URL] = []
    var articleFiles: [URL] = []
    var theme: AppThemeMode = .auto
    var fontSize: CGFloat = 16
    var isFileImporterPresented: Bool = false
    var isFolderImporterPresented: Bool = false
    var scrollToHeadingID: String?
    var isQuickOpenPresented: Bool = false

    private var fileWatcher: FileWatcher?

    init() {
        loadRecentFiles()
    }

    func openFile(url: URL) {
        guard let document = FileService.loadDocument(from: url) else { return }
        currentDocument = document
        outline = OutlineParser.parse(markdown: document.content)
        stats = DocumentStats.compute(from: document.content)
        addToRecentFiles(url)
        startWatching(url: url)
    }

    func openFolder(url: URL) {
        currentFolderURL = url
        fileTree = FileService.buildFileTree(at: url)
        articleFiles = FileService.findMarkdownFiles(in: url)
        sidebarTab = .files
    }

    func scrollToHeading(_ id: String) {
        scrollToHeadingID = id
    }

    private func startWatching(url: URL) {
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) { [weak self] in
            self?.reloadCurrentDocument()
        }
        fileWatcher?.start()
    }

    private func reloadCurrentDocument() {
        guard let url = currentDocument?.url else { return }
        guard let document = FileService.loadDocument(from: url) else { return }
        currentDocument = document
        outline = OutlineParser.parse(markdown: document.content)
        stats = DocumentStats.compute(from: document.content)
    }

    private func addToRecentFiles(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 20 {
            recentFiles = Array(recentFiles.prefix(20))
        }
        saveRecentFiles()
    }

    private func saveRecentFiles() {
        let bookmarks = recentFiles.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope)
        }
        UserDefaults.standard.set(bookmarks, forKey: "recentFiles")
    }

    private func loadRecentFiles() {
        guard let bookmarks = UserDefaults.standard.array(forKey: "recentFiles") as? [Data] else { return }
        recentFiles = bookmarks.compactMap { data -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale) else { return nil }
            guard !isStale else { return nil }
            return url
        }
    }
}
