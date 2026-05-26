import SwiftUI
import WebKit

struct DocumentView: View {
    /// Content as loaded by DocumentGroup. Used as the baseline until the user reloads.
    let text: String
    /// Original on-disk URL, provided by FileDocumentConfiguration. Needed for
    /// resolving relative image paths and for manual reload.
    let fileURL: URL?

    @Environment(AppSettings.self) private var settings
    @State private var reloadedText: String?

    private var displayText: String { reloadedText ?? text }

    var body: some View {
        VStack(spacing: 0) {
            WebViewRepresentable(
                html: MarkdownRenderer.renderHTML(
                    from: displayText,
                    baseURL: fileURL?.deletingLastPathComponent(),
                    theme: settings.theme,
                    fontSize: settings.fontSize
                ),
                baseURL: fileURL?.deletingLastPathComponent()
            )
            StatusBarView(stats: DocumentStats.compute(from: displayText), fileURL: fileURL)
        }
        // Scene-scoped (not focus-scoped) so the Reload menu command targets the
        // frontmost document window even when no control inside it holds focus.
        .focusedSceneValue(\.reloadAction, reload)
    }

    /// Re-read the file from disk to pick up external edits (Cmd+R).
    private func reload() {
        guard let fileURL else { return }
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        reloadedText = String(decoding: data, as: UTF8.self)
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if html != context.coordinator.lastHTML || baseURL != context.coordinator.lastBaseURL {
            context.coordinator.lastHTML = html
            context.coordinator.lastBaseURL = baseURL
            loadContent(webView, context: context)
        }
    }

    /// Load HTML via a per-window temp file so WKWebView can access local images.
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

        // Each window writes a uniquely named temp file so concurrent windows
        // don't clobber each other's preview.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("mdlens", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent("preview-\(context.coordinator.id.uuidString).html")
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

    class Coordinator: NSObject, WKNavigationDelegate {
        let id = UUID()
        var lastHTML: String = ""
        var lastBaseURL: URL?
        var tempFileURL: URL?

        deinit {
            if let url = tempFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        /// Route link clicks: markdown files open in a new mdLens window, other
        /// local files / web URLs open in their default app, and in-page anchors
        /// scroll within the current document. Programmatic and initial loads
        /// (the temp HTML) pass through untouched.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            switch url.scheme {
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case "file":
                // Same-document anchor (#heading) — let WebKit scroll.
                if url.path == webView.url?.path {
                    decisionHandler(.allow)
                    return
                }
                if markdownExtensions.contains(url.pathExtension.lowercased()) {
                    // Open in this app → DocumentGroup spawns a new window.
                    let cfg = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: cfg)
                } else {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }
    }
}
