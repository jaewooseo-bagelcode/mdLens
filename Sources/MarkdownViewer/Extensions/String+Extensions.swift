import Foundation
import Markdown

// MARK: - Markup Helpers

func extractPlainText(from markup: any Markup) -> String {
    var result = ""
    for child in markup.children {
        if let text = child as? Markdown.Text {
            result += text.string
        } else if let code = child as? InlineCode {
            result += code.code
        } else {
            result += extractPlainText(from: child)
        }
    }
    return result
}

struct SlugGenerator {
    private var counts: [String: Int] = [:]

    mutating func slug(for text: String) -> String {
        let base = text.slugified
        let count = counts[base, default: 0]
        counts[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }
}

// MARK: - Markdown File Extensions

let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

// MARK: - String Extensions

extension String {
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    var slugified: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return self
            .lowercased()
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { $0 == " " ? "-" : String($0) }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
