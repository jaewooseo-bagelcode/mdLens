import Foundation
import Markdown
import MarkdownCore

enum OutlineParser {
    static func parse(markdown: String) -> [OutlineItem] {
        let document = Document(parsing: markdown)
        var items: [OutlineItem] = []
        var slugCounts: [String: Int] = [:]

        for child in document.children {
            guard let heading = child as? Heading else { continue }
            let title = heading.plainText
            let baseSlug = title.slugified
            let count = slugCounts[baseSlug, default: 0]
            slugCounts[baseSlug] = count + 1
            let slug = count == 0 ? baseSlug : "\(baseSlug)-\(count)"

            items.append(OutlineItem(
                id: slug,
                title: title,
                level: heading.level
            ))
        }
        return items
    }
}

private extension Heading {
    var plainText: String {
        children.compactMap { markup -> String? in
            if let text = markup as? Markdown.Text {
                return text.string
            }
            if let code = markup as? InlineCode {
                return code.code
            }
            if let strong = markup as? Strong {
                return strong.children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
            }
            if let emphasis = markup as? Emphasis {
                return emphasis.children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
            }
            return nil
        }.joined()
    }
}
