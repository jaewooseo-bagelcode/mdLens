import Foundation
import Markdown

// MARK: - Feature Detection

private struct FeatureFlags {
    var needsKaTeX: Bool = false
    var needsMermaid: Bool = false
}

private func detectFeatures(in markdown: String) -> FeatureFlags {
    var flags = FeatureFlags()
    flags.needsKaTeX = markdown.contains("$")
    flags.needsMermaid = markdown.contains("```mermaid")
    return flags
}

// MARK: - Footnote Preprocessor

private struct FootnoteData {
    var definitions: [(id: String, content: String)] = []

    mutating func extractDefinitions(from markdown: String) -> String {
        let pattern = #"^\[\^([^\]]+)\]:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return markdown
        }
        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let id = nsString.substring(with: match.range(at: 1))
            let content = nsString.substring(with: match.range(at: 2))
            definitions.append((id: id, content: content))
        }

        // Remove definitions from source
        var result = regex.stringByReplacingMatches(in: markdown, range: NSRange(location: 0, length: nsString.length), withTemplate: "")
        // Clean up blank lines left behind
        result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return result
    }

    func renderSection() -> String {
        guard !definitions.isEmpty else { return "" }
        var html = "<section class=\"footnotes\"><hr><ol>"
        for def in definitions {
            html += "<li id=\"fn-\(def.id)\"><p>\(def.content) <a href=\"#fnref-\(def.id)\" class=\"footnote-backref\">\u{21A9}\u{FE0F}</a></p></li>"
        }
        html += "</ol></section>"
        return html
    }
}

// MARK: - Main Renderer

public enum MarkdownRenderer {
    public static func renderHTML(from markdown: String, theme: AppThemeMode = .auto, fontSize: CGFloat = 16, offline: Bool = false) -> String {
        let features = detectFeatures(in: markdown)

        // Pre-process: emoji shortcodes
        var processed = EmojiMap.convert(markdown)

        // Pre-process: extract footnote definitions
        var footnotes = FootnoteData()
        processed = footnotes.extractDefinitions(from: processed)

        // Parse & render AST
        let document = Document(parsing: processed, options: [.parseBlockDirectives, .parseMinimalDoxygen])
        var renderer = HTMLVisitor()
        var bodyHTML = renderer.visit(document)

        // Post-process: footnote references [^id] → superscript links
        bodyHTML = processFootnoteReferences(bodyHTML)

        // Post-process: admonitions (GitHub-style alerts)
        bodyHTML = processAdmonitions(bodyHTML)

        // Append footnotes section
        bodyHTML += footnotes.renderSection()

        return wrapInFullHTML(body: bodyHTML, theme: theme, fontSize: fontSize, features: features, offline: offline)
    }

    // MARK: - Footnote References

    private static func processFootnoteReferences(_ html: String) -> String {
        // Replace [^id] with superscript link (these appear as literal text after AST processing)
        let pattern = #"\[\^([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let nsString = html as NSString
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: "<sup class=\"footnote-ref\"><a id=\"fnref-$1\" href=\"#fn-$1\">$1</a></sup>"
        )
    }

    // MARK: - Admonitions

    private static func processAdmonitions(_ html: String) -> String {
        let types: [(pattern: String, label: String, cssClass: String)] = [
            ("\\[!NOTE\\]", "Note", "note"),
            ("\\[!TIP\\]", "Tip", "tip"),
            ("\\[!IMPORTANT\\]", "Important", "important"),
            ("\\[!WARNING\\]", "Warning", "warning"),
            ("\\[!CAUTION\\]", "Caution", "caution"),
        ]

        var result = html
        for type in types {
            let pattern = "<blockquote>\\s*<p>\\s*\(type.pattern)\\s*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            let ns = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "<div class=\"admonition admonition-\(type.cssClass)\"><p class=\"admonition-title\">\(type.label)</p><p>"
            )
        }
        // Close admonition divs (replace matching </blockquote>)
        // After opening an admonition, the next </blockquote> should become </div>
        // Simple approach: replace </blockquote> that follows admonition content
        result = result.replacingOccurrences(
            of: "</blockquote>",
            with: "</blockquote>"  // keep as-is initially
        )
        // More targeted: find admonition divs and fix their closing tags
        let closingPattern = #"(<div class="admonition[^"]*">[\s\S]*?)</blockquote>"#
        if let closeRegex = try? NSRegularExpression(pattern: closingPattern, options: []) {
            var nsResult = result as NSString
            // Iteratively fix from last to first to preserve ranges
            let matches = closeRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                let fullRange = match.range
                let innerRange = match.range(at: 1)
                let inner = nsResult.substring(with: innerRange)
                let replacement = inner + "</div>"
                nsResult = nsResult.replacingCharacters(in: fullRange, with: replacement) as NSString
            }
            result = nsResult as String
        }
        return result
    }

    // MARK: - HTML Template

    private static func wrapInFullHTML(body: String, theme: AppThemeMode, fontSize: CGFloat, features: FeatureFlags, offline: Bool) -> String {
        let css = generateCSS(theme: theme, fontSize: fontSize)
        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        """

        if !offline {
            head += """
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css" media="(prefers-color-scheme: light), (prefers-color-scheme: no-preference)">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css" media="(prefers-color-scheme: dark)">
            """
        }

        if !offline && features.needsKaTeX {
            head += """
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.css">
            """
        }

        var scripts = ""

        if !offline {
            scripts += """
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js"></script>
            <script>hljs.highlightAll();</script>
            """
        }

        if !offline && features.needsKaTeX {
            scripts += """
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/contrib/auto-render.min.js"></script>
            <script>
            renderMathInElement(document.body, {
                delimiters: [
                    {left: '$$', right: '$$', display: true},
                    {left: '$', right: '$', display: false},
                    {left: '\\\\(', right: '\\\\)', display: false},
                    {left: '\\\\[', right: '\\\\]', display: true}
                ],
                throwOnError: false
            });
            </script>
            """
        }

        if !offline && features.needsMermaid {
            scripts += """
            <script type="module">
            import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
            mermaid.initialize({
                startOnLoad: true,
                theme: (window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'default',
                securityLevel: 'loose'
            });
            </script>
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        \(head)
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        \(scripts)
        </body>
        </html>
        """
    }

    // MARK: - CSS

    private static func generateCSS(theme: AppThemeMode, fontSize: CGFloat) -> String {
        if theme == .auto {
            return generateAutoCSS(fontSize: fontSize)
        }
        let (bg, fg, codeBg, borderColor, linkColor, blockquoteBorder, blockquoteFg) = themeColors(theme)
        return baseCSS(fontSize: fontSize, bg: bg, fg: fg, codeBg: codeBg, borderColor: borderColor, linkColor: linkColor, blockquoteBorder: blockquoteBorder, blockquoteFg: blockquoteFg)
    }

    private static func generateAutoCSS(fontSize: CGFloat) -> String {
        let light = themeColors(.light)
        let dark = themeColors(.dark)
        return """
        \(baseCSS(fontSize: fontSize, bg: light.bg, fg: light.fg, codeBg: light.codeBg, borderColor: light.border, linkColor: light.link, blockquoteBorder: light.blockquoteBorder, blockquoteFg: light.blockquoteFg))
        @media (prefers-color-scheme: dark) {
            body { color: \(dark.fg); background: \(dark.bg); }
            h1, h2 { border-bottom-color: \(dark.border); }
            h6 { color: \(dark.blockquoteFg); }
            a { color: \(dark.link); }
            blockquote { border-left-color: \(dark.blockquoteBorder); color: \(dark.blockquoteFg); }
            code { background: \(dark.codeBg); }
            pre { background: \(dark.codeBg); }
            th, td { border-color: \(dark.border); }
            th { background: \(dark.codeBg); }
            hr { border-top-color: \(dark.border); }
            .admonition { border-color: #404040; }
            .footnotes { border-top-color: #404040; }
        }
        """
    }

    private static func baseCSS(fontSize: CGFloat, bg: String, fg: String, codeBg: String, borderColor: String, linkColor: String, blockquoteBorder: String, blockquoteFg: String) -> String {
        """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html { font-size: \(Int(fontSize))px; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            line-height: 1.7;
            color: \(fg);
            background: \(bg);
            padding: 40px;
            max-width: 860px;
            margin: 0 auto;
            -webkit-font-smoothing: antialiased;
        }
        .markdown-body > *:first-child { margin-top: 0; }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em; margin-bottom: 0.5em;
            font-weight: 600; line-height: 1.3;
        }
        h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid \(borderColor); }
        h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid \(borderColor); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: \(blockquoteFg); }
        p { margin: 0.8em 0; }
        a { color: \(linkColor); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        del { text-decoration: line-through; }
        blockquote {
            margin: 1em 0; padding: 0.5em 1em;
            border-left: 4px solid \(blockquoteBorder);
            color: \(blockquoteFg);
        }
        blockquote > *:first-child { margin-top: 0; }
        blockquote > *:last-child { margin-bottom: 0; }
        ul, ol { margin: 0.8em 0; padding-left: 2em; }
        li { margin: 0.3em 0; }
        li > ul, li > ol { margin: 0.2em 0; }
        input[type="checkbox"] { margin-right: 0.4em; }
        code {
            font-family: "SF Mono", "Fira Code", "JetBrains Mono", Menlo, monospace;
            font-size: 0.88em;
            background: \(codeBg);
            padding: 0.15em 0.35em;
            border-radius: 4px;
        }
        pre {
            margin: 1em 0;
            background: \(codeBg);
            border-radius: 8px;
            overflow-x: auto;
            padding: 1em;
        }
        pre code {
            background: none;
            padding: 0;
            font-size: 0.85em;
            line-height: 1.5;
        }
        table {
            border-collapse: collapse;
            margin: 1em 0;
            width: 100%;
            overflow: auto;
        }
        th, td {
            border: 1px solid \(borderColor);
            padding: 8px 12px;
            text-align: left;
        }
        th { font-weight: 600; background: \(codeBg); }
        hr {
            border: none;
            border-top: 1px solid \(borderColor);
            margin: 2em 0;
        }
        img { max-width: 100%; border-radius: 4px; }
        .task-list { list-style: none; padding-left: 0; }
        .task-list li { display: flex; align-items: baseline; gap: 0.4em; }

        /* Mermaid */
        .mermaid { margin: 1em 0; text-align: center; }

        /* Admonitions */
        .admonition {
            margin: 1em 0; padding: 12px 16px;
            border-left: 4px solid; border-radius: 4px;
        }
        .admonition-title {
            font-weight: 700; margin-bottom: 4px;
        }
        .admonition-note { border-color: #0969da; background: rgba(9,105,218,0.08); }
        .admonition-note .admonition-title { color: #0969da; }
        .admonition-tip { border-color: #1a7f37; background: rgba(26,127,55,0.08); }
        .admonition-tip .admonition-title { color: #1a7f37; }
        .admonition-important { border-color: #8250df; background: rgba(130,80,223,0.08); }
        .admonition-important .admonition-title { color: #8250df; }
        .admonition-warning { border-color: #bf8700; background: rgba(191,135,0,0.08); }
        .admonition-warning .admonition-title { color: #bf8700; }
        .admonition-caution { border-color: #cf222e; background: rgba(207,34,46,0.08); }
        .admonition-caution .admonition-title { color: #cf222e; }

        /* Footnotes */
        .footnotes { margin-top: 2em; font-size: 0.9em; }
        .footnotes hr { margin-bottom: 1em; }
        .footnotes ol { padding-left: 1.5em; }
        .footnotes li { margin: 0.5em 0; }
        .footnote-ref a {
            color: \(linkColor);
            text-decoration: none;
            font-weight: 600;
        }
        .footnote-backref { text-decoration: none; margin-left: 4px; }

        /* KaTeX overrides */
        .katex-display { margin: 1em 0; overflow-x: auto; }
        """
    }

    private static func themeColors(_ theme: AppThemeMode) -> (bg: String, fg: String, codeBg: String, border: String, link: String, blockquoteBorder: String, blockquoteFg: String) {
        switch theme {
        case .dark:
            return ("#1e1e1e", "#d4d4d4", "#2d2d2d", "#404040", "#569cd6", "#404040", "#808080")
        case .sepia:
            return ("#faf4e8", "#5b4636", "#f0e6d2", "#d4c5a9", "#8b6914", "#c4a35a", "#8b7355")
        case .light:
            return ("#ffffff", "#24292e", "#f6f8fa", "#e1e4e8", "#0366d6", "#dfe2e5", "#6a737d")
        case .auto:
            return ("#ffffff", "#24292e", "#f6f8fa", "#e1e4e8", "#0366d6", "#dfe2e5", "#6a737d")
        }
    }
}

// MARK: - AST → HTML Visitor

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    private var slugCounts: [String: Int] = [:]

    mutating func defaultVisit(_ markup: any Markup) -> String {
        visitChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        visitChildren(of: document, separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let content = visitChildren(of: heading)
        let plainText = extractAllPlainText(from: heading)
        let baseSlug = plainText.slugified
        let count = slugCounts[baseSlug, default: 0]
        slugCounts[baseSlug] = count + 1
        let slug = count == 0 ? baseSlug : "\(baseSlug)-\(count)"
        return "<h\(heading.level) id=\"\(slug)\">\(content)</h\(heading.level)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = visitChildren(of: paragraph)
        return "<p>\(content)</p>"
    }

    mutating func visitText(_ text: Markdown.Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(visitChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(visitChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(visitChildren(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language ?? ""

        // Mermaid: render as div for mermaid.js
        if lang.lowercased() == "mermaid" {
            return "<pre class=\"mermaid\">\(codeBlock.code)</pre>"
        }

        let langClass = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
        return "<pre><code\(langClass)>\(escapeHTML(codeBlock.code))</code></pre>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = link.destination ?? ""
        let content = visitChildren(of: link)
        return "<a href=\"\(escapeHTML(href))\">\(content)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let src = image.source ?? ""
        let alt = extractAllPlainText(from: image)
        return "<img src=\"\(escapeHTML(src))\" alt=\"\(escapeHTML(alt))\">"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let items = visitChildren(of: unorderedList, separator: "\n")
        let isTaskList = unorderedList.children.contains { child in
            (child as? ListItem)?.checkbox != nil
        }
        let cls = isTaskList ? " class=\"task-list\"" : ""
        return "<ul\(cls)>\n\(items)\n</ul>"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let items = visitChildren(of: orderedList, separator: "\n")
        let start = orderedList.startIndex
        let startAttr = start != 1 ? " start=\"\(start)\"" : ""
        return "<ol\(startAttr)>\n\(items)\n</ol>"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let content = visitChildren(of: listItem)
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked disabled" : " disabled"
            return "<li><input type=\"checkbox\"\(checked)>\(content)</li>"
        }
        return "<li>\(content)</li>"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let content = visitChildren(of: blockQuote, separator: "\n")
        return "<blockquote>\n\(content)\n</blockquote>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        html.rawHTML
    }

    mutating func visitTable(_ table: Table) -> String {
        var result = "<table>\n<thead>\n<tr>\n"
        let head = table.head
        for cell in head.cells {
            let content = visitChildren(of: cell)
            result += "<th>\(content)</th>\n"
        }
        result += "</tr>\n</thead>\n<tbody>\n"
        for row in table.body.rows {
            result += "<tr>\n"
            for cell in row.cells {
                let content = visitChildren(of: cell)
                result += "<td>\(content)</td>\n"
            }
            result += "</tr>\n"
        }
        result += "</tbody>\n</table>"
        return result
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>"
    }

    // MARK: - Helpers

    private mutating func visitChildren(of markup: any Markup, separator: String = "") -> String {
        var parts: [String] = []
        for child in markup.children {
            parts.append(visit(child))
        }
        return parts.joined(separator: separator)
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func extractAllPlainText(from markup: any Markup) -> String {
        var result = ""
        for child in markup.children {
            if let text = child as? Markdown.Text {
                result += text.string
            } else if let code = child as? InlineCode {
                result += code.code
            } else {
                result += extractAllPlainText(from: child)
            }
        }
        return result
    }
}
