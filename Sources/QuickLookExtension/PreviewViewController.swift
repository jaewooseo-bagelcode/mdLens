import Cocoa
import Quartz

@objc(PreviewViewController)
class PreviewViewController: NSViewController, QLPreviewingController {

    private var textView: NSTextView!

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = true

        textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor

        scrollView.documentView = textView
        self.view = scrollView
    }

    private static let maxFileSize = 10_000_000 // 10MB

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = handle.readData(ofLength: Self.maxFileSize)
                let markdown = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                let attributed = MarkdownTextRenderer.render(markdown, fontSize: 15)
                DispatchQueue.main.async {
                    self.textView.textStorage?.setAttributedString(attributed)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async { handler(error) }
            }
        }
    }
}
