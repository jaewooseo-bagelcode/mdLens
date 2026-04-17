import Foundation
import Markdown

// MARK: - Feature Detection

private struct FeatureFlags {
    var needsKaTeX: Bool = false
    var needsMermaid: Bool = false
}

private func detectFeatures(in markdown: String) -> FeatureFlags {
    var flags = FeatureFlags()
    // Detect actual math delimiters, not currency like $0.014
    // Match: $$...$$, $<non-digit>...$, \(...\), \[...\]
    flags.needsKaTeX = markdown.contains("$$")
        || markdown.range(of: #"\$[^$\d\s].*?\$"#, options: .regularExpression) != nil
        || markdown.contains("\\(") || markdown.contains("\\[")
    flags.needsMermaid = markdown.contains("```mermaid")
    return flags
}

// MARK: - Front Matter Preprocessor

private struct FrontMatter {
    var fields: [(key: String, value: String)] = []

    /// Extract YAML-like front matter delimited by `---` at the very start of the document.
    mutating func extract(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)

        // Opening `---` must be the first line (allow leading whitespace only)
        guard !lines.isEmpty,
              lines[0].trimmingCharacters(in: CharacterSet.whitespaces) == "---" else {
            return markdown
        }

        // Find closing `---` within first 30 lines (reasonable front matter limit)
        let searchEnd = min(lines.count, 30)
        var closingDash: Int?
        for i in 1..<searchEnd {
            if lines[i].trimmingCharacters(in: CharacterSet.whitespaces) == "---" {
                closingDash = i
                break
            }
        }
        guard let closing = closingDash, closing > 1 else { return markdown }

        // Parse key-value pairs; every non-blank line must match `key: value`
        var parsedFields: [(key: String, value: String)] = []
        for i in 1..<closing {
            let cleaned = lines[i].replacingOccurrences(of: "**", with: "")
            let trimmed = cleaned.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.isEmpty { continue }
            guard let colonRange = cleaned.range(of: ":") else {
                // Non-blank line without `:` → not front matter
                return markdown
            }
            let key = String(cleaned[cleaned.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: CharacterSet.whitespaces)
            let value = String(cleaned[colonRange.upperBound...]).trimmingCharacters(in: CharacterSet.whitespaces)
            if key.isEmpty { return markdown }
            parsedFields.append((key: key, value: value))
        }

        // Must have at least one field to be valid front matter
        guard !parsedFields.isEmpty else { return markdown }
        fields = parsedFields

        let remaining = Array(lines[(closing + 1)...]).joined(separator: "\n")
        return remaining
    }

    func renderHTML() -> String {
        guard !fields.isEmpty else { return "" }
        var html = "<div class=\"front-matter\"><dl>"
        for field in fields {
            html += "<dt>\(field.key.htmlEscaped)</dt><dd>\(field.value.htmlEscaped)</dd>"
        }
        html += "</dl></div>"
        return html
    }
}

// MARK: - Footnote Preprocessor

private struct FootnoteData {
    private static let definitionRegex = try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s*(.+)$"#, options: .anchorsMatchLines)
    var definitions: [(id: String, content: String)] = []

    mutating func extractDefinitions(from markdown: String) -> String {
        let regex = Self.definitionRegex
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

enum MarkdownRenderer {
    static func renderHTML(from markdown: String, baseURL: URL? = nil, theme: AppThemeMode = .auto, fontSize: CGFloat = 16) -> String {
        let features = detectFeatures(in: markdown)

        // Pre-process: extract front matter
        var frontMatter = FrontMatter()
        var processed = frontMatter.extract(from: markdown)

        // Pre-process: encode spaces in image/link destinations (CommonMark disallows spaces)
        processed = preprocessLinkDestinations(processed)

        // Pre-process: emoji shortcodes
        processed = EmojiMap.convert(processed)

        // Pre-process: extract footnote definitions
        var footnotes = FootnoteData()
        processed = footnotes.extractDefinitions(from: processed)

        // Parse & render AST
        let document = Document(parsing: processed)
        var renderer = HTMLVisitor(baseURL: baseURL)
        var bodyHTML = frontMatter.renderHTML() + renderer.visit(document)

        // Post-process: footnote references [^id] → superscript links
        bodyHTML = processFootnoteReferences(bodyHTML)

        // Post-process: admonitions (GitHub-style alerts)
        bodyHTML = processAdmonitions(bodyHTML)

        // Append footnotes section
        bodyHTML += footnotes.renderSection()

        return wrapInFullHTML(body: bodyHTML, theme: theme, fontSize: fontSize, features: features)
    }

    // MARK: - Link Destination Preprocessor

    /// Encode spaces in image/link destinations so the CommonMark parser recognizes them.
    /// CommonMark does not allow ASCII spaces in link destinations unless wrapped in `<>`.
    /// Skips links that have a quoted title portion like `[text](url "title")`.
    private static let linkDestRegex = try! NSRegularExpression(pattern: #"(\!?\[[^\]]*\]\()([^)]+)(\))"#, options: .anchorsMatchLines)

    private static func preprocessLinkDestinations(_ markdown: String) -> String {
        let regex = linkDestRegex
        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        var result = markdown as NSString
        for match in matches.reversed() {
            let urlRange = match.range(at: 2)
            let payload = result.substring(with: urlRange)

            // Skip if payload contains a quoted title portion
            if payload.contains("\"") || payload.contains("'") { continue }
            // Only process if payload actually has spaces
            guard payload.contains(" ") else { continue }

            let encoded = payload.replacingOccurrences(of: " ", with: "%20")
            result = result.replacingCharacters(in: urlRange, with: encoded) as NSString
        }
        return result as String
    }

    // MARK: - Footnote References

    private static let footnoteRefRegex = try! NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#)

    private static func processFootnoteReferences(_ html: String) -> String {
        // Replace [^id] with superscript link (these appear as literal text after AST processing)
        let regex = footnoteRefRegex
        let nsString = html as NSString
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: "<sup class=\"footnote-ref\"><a id=\"fnref-$1\" href=\"#fn-$1\">$1</a></sup>"
        )
    }

    // MARK: - Admonitions

    private static let admonitionTypes: [(key: String, label: String, cssClass: String)] = [
        ("NOTE", "Note", "note"), ("TIP", "Tip", "tip"),
        ("IMPORTANT", "Important", "important"), ("WARNING", "Warning", "warning"),
        ("CAUTION", "Caution", "caution"),
    ]
    private static let admonitionOpenRegex: NSRegularExpression = {
        let keys = admonitionTypes.map { NSRegularExpression.escapedPattern(for: "[!\($0.key)]") }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "<blockquote>\\s*<p>\\s*(\(keys))\\s*", options: [.dotMatchesLineSeparators])
    }()
    private static let admonitionCloseRegex = try! NSRegularExpression(pattern: #"(<div class="admonition[^"]*">[\s\S]*?)</blockquote>"#)
    private static let admonitionLookup: [String: (label: String, cssClass: String)] = {
        Dictionary(uniqueKeysWithValues: admonitionTypes.map { ("[!\($0.key)]", (label: $0.label, cssClass: $0.cssClass)) })
    }()

    private static func processAdmonitions(_ html: String) -> String {
        // Single-pass open tag replacement
        let ns = html as NSString
        let matches = admonitionOpenRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result = html as NSString
        for match in matches.reversed() {
            let key = result.substring(with: match.range(at: 1))
            guard let info = admonitionLookup[key] else { continue }
            let replacement = "<div class=\"admonition admonition-\(info.cssClass)\"><p class=\"admonition-title\">\(info.label)</p><p>"
            result = result.replacingCharacters(in: match.range, with: replacement) as NSString
        }
        // Close admonition divs
        let closeMatches = admonitionCloseRegex.matches(in: result as String, range: NSRange(location: 0, length: result.length))
        for match in closeMatches.reversed() {
            let inner = result.substring(with: match.range(at: 1))
            result = result.replacingCharacters(in: match.range, with: inner + "</div>") as NSString
        }
        return result as String
    }

    // MARK: - HTML Template

    private static func wrapInFullHTML(body: String, theme: AppThemeMode, fontSize: CGFloat, features: FeatureFlags) -> String {
        let css = generateCSS(theme: theme, fontSize: fontSize)
        var head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css" media="(prefers-color-scheme: light), (prefers-color-scheme: no-preference)">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css" media="(prefers-color-scheme: dark)">
        """

        if features.needsKaTeX {
            head += """
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.21/dist/katex.min.css">
            """
        }

        var scripts = """
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js"></script>
        <script>hljs.highlightAll();</script>
        <script>
        document.addEventListener('error', function(e) {
            if (e.target.tagName === 'IMG') {
                var alt = e.target.alt;
                if (alt) {
                    var span = document.createElement('span');
                    span.className = 'img-alt-fallback';
                    span.textContent = alt;
                    e.target.replaceWith(span);
                } else {
                    e.target.style.display = 'none';
                }
            }
        }, true);
        </script>
        """

        if features.needsKaTeX {
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

        if features.needsMermaid {
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
            .front-matter { background: \(dark.codeBg); border-color: \(dark.border); }
            .front-matter dt { color: \(dark.blockquoteFg); }
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
            max-width: none;
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
        .img-alt-fallback {
            display: inline-block;
            padding: 2px 6px;
            font-size: 0.85em;
            color: \(blockquoteFg);
            font-style: italic;
        }
        .task-list { list-style: none; padding-left: 0; }
        .task-list li { display: flex; align-items: baseline; gap: 0.4em; }

        /* Front Matter */
        .front-matter {
            margin: 0 0 2em 0; padding: 16px 20px;
            background: \(codeBg); border-radius: 8px;
            border: 1px solid \(borderColor);
        }
        .front-matter dl {
            display: grid; grid-template-columns: auto 1fr;
            gap: 4px 16px; margin: 0;
        }
        .front-matter dt {
            font-weight: 600; color: \(blockquoteFg);
            white-space: nowrap;
        }
        .front-matter dd { margin: 0; }

        /* Table wrapper for responsive overflow */
        .table-wrapper { overflow-x: auto; margin: 1em 0; }
        .table-wrapper table { margin: 0; }
        td { word-break: break-word; }

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

    let baseURL: URL?
    private var slugGen = SlugGenerator()

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    mutating func defaultVisit(_ markup: any Markup) -> String {
        visitChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        visitChildren(of: document, separator: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let content = visitChildren(of: heading)
        let plainText = extractPlainText(from: heading)
        let slug = slugGen.slug(for: plainText)
        return "<h\(heading.level) id=\"\(slug)\">\(content)</h\(heading.level)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let content = visitChildren(of: paragraph)
        return "<p>\(content)</p>"
    }

    mutating func visitText(_ text: Markdown.Text) -> String {
        text.string.htmlEscaped
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
        "<code>\(inlineCode.code.htmlEscaped)</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language ?? ""

        // Mermaid: render as div for mermaid.js
        if lang.lowercased() == "mermaid" {
            return "<pre class=\"mermaid\">\(codeBlock.code.htmlEscaped)</pre>"
        }

        let langClass = lang.isEmpty ? "" : " class=\"language-\(lang.htmlEscaped)\""
        return "<pre><code\(langClass)>\(codeBlock.code.htmlEscaped)</code></pre>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let href = link.destination ?? ""
        let content = visitChildren(of: link)
        return "<a href=\"\(href.htmlEscaped)\">\(content)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let src = image.source ?? ""
        let resolvedSrc = resolveImagePath(src)
        let alt = extractPlainText(from: image)
        return "<img src=\"\(resolvedSrc.htmlEscaped)\" alt=\"\(alt.htmlEscaped)\">"
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
        sanitizeHTML(html.rawHTML)
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        sanitizeHTML(html.rawHTML)
    }

    private static let dangerousTags = ["script", "iframe", "object", "embed", "form", "meta"]
    private static let dangerousTagRegex: NSRegularExpression = {
        let tags = dangerousTags.joined(separator: "|")
        return try! NSRegularExpression(
            pattern: #"<\s*/?\s*(\#(tags)|link\b[^>]*rel\s*=)[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private func sanitizeHTML(_ raw: String) -> String {
        let ns = raw as NSString
        if Self.dangerousTagRegex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) != nil {
            return raw.htmlEscaped
        }
        return raw
    }

    mutating func visitTable(_ table: Table) -> String {
        let alignments = table.columnAlignments
        var result = "<div class=\"table-wrapper\"><table>\n<thead>\n<tr>\n"
        let head = table.head
        for (i, cell) in head.cells.enumerated() {
            let content = visitChildren(of: cell)
            let align = alignmentStyle(alignments, index: i)
            result += "<th\(align)>\(content)</th>\n"
        }
        result += "</tr>\n</thead>\n<tbody>\n"
        for row in table.body.rows {
            result += "<tr>\n"
            for (i, cell) in row.cells.enumerated() {
                let content = visitChildren(of: cell)
                let align = alignmentStyle(alignments, index: i)
                result += "<td\(align)>\(content)</td>\n"
            }
            result += "</tr>\n"
        }
        result += "</tbody>\n</table></div>"
        return result
    }

    private func alignmentStyle(_ alignments: [Table.ColumnAlignment?], index: Int) -> String {
        guard index < alignments.count, let alignment = alignments[index] else { return "" }
        switch alignment {
        case .left: return " style=\"text-align:left\""
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        }
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

    /// Resolve image path to an absolute file URL when baseURL is available.
    /// Remote URLs (http/https/data) are left as-is.
    private func resolveImagePath(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:") {
            return path
        }
        // Decode %20 back to spaces for filesystem resolution, then let URL handle encoding
        let decoded = path.removingPercentEncoding ?? path
        if let base = baseURL {
            let resolved = base.appendingPathComponent(decoded)
            return resolved.absoluteString
        }
        // No baseURL — percent-encode for relative use
        let components = decoded.components(separatedBy: "/")
        let encoded = components.map { component -> String in
            component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
        }
        return encoded.joined(separator: "/")
    }

}
