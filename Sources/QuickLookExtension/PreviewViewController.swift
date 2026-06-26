import Cocoa
import Quartz
import WebKit
import MarkdownCore

/// Quick Look preview: renders `.md` through the shared MarkdownRenderer and
/// `.html` directly, both in a WKWebView. JavaScript runs in the QL host as long
/// as the .appex is signed with only the minimal sandbox entitlements
/// (app-sandbox + files.user-selected.read-only + network.client) — so
/// highlight.js / KaTeX / Mermaid render at full fidelity, matching the app.
@objc(PreviewViewController)
class PreviewViewController: NSViewController, QLPreviewingController {

    private var webView: WKWebView!
    /// Temp HTML written for the markdown path; cleaned up on the next preview/deinit.
    private var tempPreviewURL: URL?

    override var nibName: NSNib.Name? { nil }

    deinit {
        if let tempPreviewURL {
            try? FileManager.default.removeItem(at: tempPreviewURL)
        }
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.autoresizingMask = [.width, .height]
        self.view = webView
    }

    /// Guard against pathological files locking up the preview host.
    private static let maxFileSize = 10_000_000 // 10MB

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Clean up any temp HTML from a prior preview on this controller, regardless
        // of which branch this preview takes (md → html reuse leaves no leak).
        if let old = tempPreviewURL {
            try? FileManager.default.removeItem(at: old)
            tempPreviewURL = nil
        }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension.lowercased()

        // Raw HTML: load straight from disk so its own resources resolve.
        if ext == "html" || ext == "htm" {
            webView.loadFileURL(url, allowingReadAccessTo: dir)
            handler(nil)
            return
        }

        // Markdown: read (size-capped), render via the shared pipeline, load as a
        // temp file so relative document resources can resolve by absolute file URL.
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = handle.readData(ofLength: Self.maxFileSize)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            let html = MarkdownRenderer.renderHTML(from: text, baseURL: dir, theme: .auto, fontSize: 16)
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mdlens-ql-\(UUID().uuidString).html")
            try html.write(to: tmp, atomically: true, encoding: .utf8)
            tempPreviewURL = tmp
            // Broad read scope so the document's absolute file:// images load too.
            webView.loadFileURL(tmp, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
