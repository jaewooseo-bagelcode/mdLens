import Foundation

struct OutlineItem: Identifiable, Hashable {
    let id: String
    let title: String
    let level: Int  // 1-6 for h1-h6

    var indentLevel: Int {
        max(0, level - 1)
    }
}
