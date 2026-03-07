import Foundation
import Markdown

enum OutlineParser {
    static func parse(markdown: String) -> [OutlineItem] {
        let document = Document(parsing: markdown)
        var items: [OutlineItem] = []
        var slugGen = SlugGenerator()

        for child in document.children {
            guard let heading = child as? Heading else { continue }
            let title = extractPlainText(from: heading)
            let slug = slugGen.slug(for: title)

            items.append(OutlineItem(
                id: slug,
                title: title,
                level: heading.level
            ))
        }
        return items
    }
}
