import SwiftUI
import WebKit

struct DocumentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        WebViewRepresentable(
            html: MarkdownRenderer.renderHTML(
                from: appState.currentDocument?.content ?? "",
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
        let oldHTML = context.coordinator.lastHTML
        if html != oldHTML {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        if let id = scrollToID {
            let js = "document.getElementById('\(id)')?.scrollIntoView({behavior:'smooth',block:'start'});"
            webView.evaluateJavaScript(js)
            DispatchQueue.main.async {
                onScrollComplete()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastHTML: String = ""
    }
}
