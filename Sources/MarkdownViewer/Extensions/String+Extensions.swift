import Foundation

extension String {
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
