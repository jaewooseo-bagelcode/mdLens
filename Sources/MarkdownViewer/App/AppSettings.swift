import SwiftUI

/// App-global, cross-window preferences. Intentionally a single shared instance
/// (unlike document state, which is per-window via DocumentGroup). Persists to
/// UserDefaults so settings survive relaunch.
@Observable
final class AppSettings {
    static let themeKey = "theme"
    static let fontSizeKey = "fontSize"

    var theme: AppThemeMode {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    var fontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(fontSize), forKey: Self.fontSizeKey) }
    }

    init() {
        theme = AppThemeMode(rawValue: UserDefaults.standard.string(forKey: Self.themeKey) ?? "") ?? .auto
        let stored = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = stored == 0 ? 16 : CGFloat(stored)
    }
}
