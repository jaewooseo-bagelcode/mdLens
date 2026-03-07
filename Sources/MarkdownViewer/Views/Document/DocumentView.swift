import SwiftUI
import WebKit

struct DocumentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        WebViewRepresentable(
            html: MarkdownRenderer.renderHTML(
                from: appState.currentDocument?.content ?? "",
                baseURL: appState.currentDocument?.url.deletingLastPathComponent(),
                theme: appState.theme,
                fontSize: appState.fontSize
            ),
            baseURL: appState.currentDocument?.url.deletingLastPathComponent(),
            scrollToID: appState.scrollToHeadingID,
            onScrollComplete: {
                appState.scrollToHeadingID = nil
            }
        )
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let scrollToID: String?
    let onScrollComplete: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if html != context.coordinator.lastHTML || baseURL != context.coordinator.lastBaseURL {
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            loadContent(webView, context: context)
        }

        if let id = scrollToID {
            let js = "document.getElementById('\(id)')?.scrollIntoView({behavior:'smooth',block:'start'});"
            webView.evaluateJavaScript(js)
            DispatchQueue.main.async {
                onScrollComplete()
            }
        }
    }

    /// Load HTML via a temp file so WKWebView can access local images.
    private func loadContent(_ webView: WKWebView, context: Context) {
        guard let baseURL = baseURL else {
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        // Clean up previous temp file
        if let old = context.coordinator.tempFileURL {
            try? FileManager.default.removeItem(at: old)
            context.coordinator.tempFileURL = nil
        }

        // Write to app-owned temp directory, grant read access to document directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mdlens", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("preview.html")
        do {
            try html.write(to: tempFile, atomically: true, encoding: .utf8)
            context.coordinator.tempFileURL = tempFile
            // Grant read access from root so both temp file and document images are accessible
            webView.loadFileURL(tempFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } catch {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastHTML: String = ""
        var lastBaseURL: URL?
        var tempFileURL: URL?

        deinit {
            if let url = tempFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
