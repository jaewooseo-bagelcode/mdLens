import Foundation

struct DocumentStats: Equatable {
    let wordCount: Int
    let charCount: Int
    let lineCount: Int
    let readingTimeMinutes: Int

    static func compute(from content: String) -> DocumentStats {
        let lines = content.components(separatedBy: .newlines)
        let words = content.split { $0.isWhitespace || $0.isNewline }
        let wordsPerMinute = 200

        return DocumentStats(
            wordCount: words.count,
            charCount: content.count,
            lineCount: lines.count,
            readingTimeMinutes: max(1, words.count / wordsPerMinute)
        )
    }
}
