import Cocoa
import Markdown
import MarkdownCore

enum MarkdownTextRenderer {

    static func render(_ markdown: String, fontSize: CGFloat = 15) -> NSAttributedString {
        let document = Document(parsing: markdown)
        var visitor = RichTextVisitor(fontSize: fontSize)
        return visitor.visit(document)
    }
}

// MARK: - Visitor

private struct RichTextVisitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let fontSize: CGFloat
    private var listDepth = 0
    private var blockQuoteDepth = 0
    private var nextListPrefix = ""

    private static let bullets = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
    private static let codeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1.0)
            : NSColor(white: 0.95, alpha: 1.0)
    }

    init(fontSize: CGFloat) {
        self.fontSize = fontSize
    }

    // MARK: Fonts

    private func body() -> NSFont { .systemFont(ofSize: fontSize) }

    private func headingFont(level: Int) -> NSFont {
        let scales: [CGFloat] = [1.8, 1.4, 1.2, 1.05, 0.95, 0.85]
        let s = scales[min(level - 1, scales.count - 1)]
        return .systemFont(ofSize: fontSize * s, weight: .bold)
    }

    private func mono(_ size: CGFloat? = nil) -> NSFont {
        .monospacedSystemFont(ofSize: size ?? fontSize * 0.88, weight: .regular)
    }

    private func bold(_ attr: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.font, in: range(m)) { val, r, _ in
            if let f = val as? NSFont {
                let descriptor = f.fontDescriptor.withSymbolicTraits(.bold)
                m.addAttribute(.font, value: NSFont(descriptor: descriptor, size: f.pointSize) ?? f, range: r)
            }
        }
        return m
    }

    private func italic(_ attr: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.font, in: range(m)) { val, r, _ in
            if let f = val as? NSFont {
                let descriptor = f.fontDescriptor.withSymbolicTraits(.italic)
                m.addAttribute(.font, value: NSFont(descriptor: descriptor, size: f.pointSize) ?? f, range: r)
            }
        }
        return m
    }

    // MARK: Helpers

    private func base() -> [NSAttributedString.Key: Any] {
        [.font: body(), .foregroundColor: NSColor.textColor]
    }

    private func str(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: base())
    }

    private func range(_ s: NSAttributedString) -> NSRange {
        NSRange(location: 0, length: s.length)
    }

    private mutating func children(of m: any Markup) -> NSAttributedString {
        let r = NSMutableAttributedString()
        for child in m.children { r.append(visit(child)) }
        return r
    }

    private static func plainText(from m: any Markup) -> String {
        var r = ""
        for child in m.children {
            if let t = child as? Markdown.Text { r += t.string }
            else if let c = child as? InlineCode { r += c.code }
            else { r += plainText(from: child) }
        }
        return r
    }

    // MARK: Block Elements

    mutating func defaultVisit(_ markup: any Markup) -> NSAttributedString {
        children(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var first = true
        for child in document.children {
            if !first { result.append(str("\n")) }
            result.append(visit(child))
            first = false
        }
        return result
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let content = children(of: heading)
        let result = NSMutableAttributedString(attributedString: content)
        let font = headingFont(level: heading.level)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = fontSize * 1.0
        style.paragraphSpacing = fontSize * 0.3

        let r = range(result)
        result.addAttribute(.font, value: font, range: r)
        result.addAttribute(.foregroundColor, value: NSColor.textColor, range: r)
        result.addAttribute(.paragraphStyle, value: style, range: r)

        if heading.level <= 2 {
            let sepStyle = NSMutableParagraphStyle()
            sepStyle.paragraphSpacing = fontSize * 0.2
            result.append(str("\n"))
            result.append(NSAttributedString(
                string: String(repeating: "\u{2500}", count: 30),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 2),
                    .foregroundColor: NSColor.separatorColor,
                    .paragraphStyle: sepStyle,
                ]
            ))
        }
        result.append(str("\n"))
        return result
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let content = children(of: paragraph)
        let result = NSMutableAttributedString(attributedString: content)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = fontSize * 0.5
        style.lineSpacing = fontSize * 0.35

        let r = range(result)
        result.enumerateAttribute(.paragraphStyle, in: r) { val, sub, _ in
            if val == nil { result.addAttribute(.paragraphStyle, value: style, range: sub) }
        }
        result.enumerateAttribute(.font, in: r) { val, sub, _ in
            if val == nil { result.addAttribute(.font, value: body(), range: sub) }
        }
        result.append(str("\n"))
        return result
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code = String(code.dropLast()) }

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = fontSize * 0.5
        style.paragraphSpacing = fontSize * 0.5
        style.headIndent = fontSize
        style.firstLineHeadIndent = fontSize
        style.tailIndent = -fontSize

        let result = NSMutableAttributedString(string: code, attributes: [
            .font: mono(fontSize * 0.82),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: Self.codeBackground,
            .paragraphStyle: style,
        ])
        result.append(str("\n"))
        return result
    }

    mutating func visitBlockQuote(_ bq: BlockQuote) -> NSAttributedString {
        blockQuoteDepth += 1
        defer { blockQuoteDepth -= 1 }

        let content = children(of: bq)
        let result = NSMutableAttributedString()

        let indent = CGFloat(blockQuoteDepth) * fontSize * 2.0
        let style = NSMutableParagraphStyle()
        style.headIndent = indent
        style.firstLineHeadIndent = indent - fontSize * 1.5
        style.paragraphSpacing = fontSize * 0.3

        let bar = String(repeating: "\u{258E} ", count: blockQuoteDepth)
        result.append(NSAttributedString(string: bar, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.separatorColor,
            .paragraphStyle: style,
        ]))

        let mc = NSMutableAttributedString(attributedString: content)
        let r = range(mc)
        mc.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
        mc.addAttribute(.paragraphStyle, value: style, range: r)
        result.append(mc)
        return result
    }

    mutating func visitThematicBreak(_ tb: ThematicBreak) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = fontSize * 0.8
        style.paragraphSpacing = fontSize * 0.8
        style.alignment = .center
        return NSAttributedString(
            string: String(repeating: "\u{2500}", count: 40) + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 4),
                .foregroundColor: NSColor.separatorColor,
                .paragraphStyle: style,
            ]
        )
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        listDepth += 1
        defer { listDepth -= 1 }
        let result = NSMutableAttributedString()
        for child in list.children {
            guard let item = child as? ListItem else { continue }
            if let cb = item.checkbox {
                nextListPrefix = cb == .checked ? "\u{2611} " : "\u{2610} "
            } else {
                nextListPrefix = Self.bullets[min(listDepth - 1, Self.bullets.count - 1)] + " "
            }
            result.append(renderListItem(item))
        }
        return result
    }

    mutating func visitOrderedList(_ list: OrderedList) -> NSAttributedString {
        listDepth += 1
        defer { listDepth -= 1 }
        let result = NSMutableAttributedString()
        var idx = list.startIndex
        for child in list.children {
            guard let item = child as? ListItem else { continue }
            nextListPrefix = "\(idx). "
            result.append(renderListItem(item))
            idx += 1
        }
        return result
    }

    private mutating func renderListItem(_ item: ListItem) -> NSAttributedString {
        let indent = CGFloat(listDepth) * fontSize * 1.5
        let style = NSMutableParagraphStyle()
        style.headIndent = indent
        style.firstLineHeadIndent = indent - fontSize * 1.2
        style.paragraphSpacing = fontSize * 0.15
        style.lineSpacing = fontSize * 0.25

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: nextListPrefix, attributes: [
            .font: body(),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]))

        let content = children(of: item)
        let mc = NSMutableAttributedString(attributedString: content)
        mc.addAttribute(.paragraphStyle, value: style, range: range(mc))

        while mc.string.hasSuffix("\n\n") {
            mc.deleteCharacters(in: NSRange(location: mc.length - 1, length: 1))
        }
        result.append(mc)
        if !result.string.hasSuffix("\n") { result.append(str("\n")) }
        return result
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.2

        let headers = table.head.cells.map { Self.plainText(from: $0) }
        let headerLine = "\u{2502} " + headers.joined(separator: " \u{2502} ") + " \u{2502}"
        result.append(NSAttributedString(string: headerLine + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: style,
        ]))

        let sep = "\u{251C}" + headers.map { String(repeating: "\u{2500}", count: $0.count + 2) }.joined(separator: "\u{253C}") + "\u{2524}"
        result.append(NSAttributedString(string: sep + "\n", attributes: [
            .font: mono(fontSize * 0.75),
            .foregroundColor: NSColor.separatorColor,
            .paragraphStyle: style,
        ]))

        for row in table.body.rows {
            let cells = row.cells.map { Self.plainText(from: $0) }
            let rowLine = "\u{2502} " + cells.joined(separator: " \u{2502} ") + " \u{2502}"
            result.append(NSAttributedString(string: rowLine + "\n", attributes: [
                .font: body(),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style,
            ]))
        }
        result.append(str("\n"))
        return result
    }

    // MARK: Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> NSAttributedString {
        NSAttributedString(string: EmojiMap.convert(text.string), attributes: base())
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        italic(children(of: emphasis))
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        bold(children(of: strong))
    }

    mutating func visitStrikethrough(_ s: Strikethrough) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: children(of: s))
        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range(result))
        return result
    }

    mutating func visitInlineCode(_ code: InlineCode) -> NSAttributedString {
        let pad = NSAttributedString(string: "\u{2009}", attributes: [.font: mono()])
        let codeStr = NSAttributedString(string: code.code, attributes: [
            .font: mono(),
            .foregroundColor: NSColor.textColor,
            .backgroundColor: Self.codeBackground,
        ])
        let result = NSMutableAttributedString()
        result.append(pad)
        result.append(codeStr)
        result.append(pad)
        return result
    }

    mutating func visitLink(_ link: Markdown.Link) -> NSAttributedString {
        let content = children(of: link)
        let result = NSMutableAttributedString(attributedString: content)
        let r = range(result)
        result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: r)
        result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        if let dest = link.destination, let url = URL(string: dest) {
            result.addAttribute(.link, value: url, range: r)
        }
        return result
    }

    mutating func visitImage(_ image: Markdown.Image) -> NSAttributedString {
        let alt = Self.plainText(from: image)
        return NSAttributedString(string: "[\(alt.isEmpty ? "image" : alt)]", attributes: [
            .font: body(),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    mutating func visitSoftBreak(_ sb: SoftBreak) -> NSAttributedString { str(" ") }
    mutating func visitLineBreak(_ lb: LineBreak) -> NSAttributedString { str("\n") }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        let stripped = html.rawHTML.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return str("") }
        return NSAttributedString(string: text + "\n", attributes: [
            .font: body(), .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> NSAttributedString {
        let tag = html.rawHTML.lowercased()
        if tag == "<br>" || tag == "<br/>" || tag == "<br />" {
            return str("\n")
        }
        return str("")
    }
}
