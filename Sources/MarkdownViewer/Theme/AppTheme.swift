import SwiftUI

enum AppThemeMode: String, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light, .sepia: return .light
        case .dark: return .dark
        }
    }

    var backgroundColor: Color {
        switch self {
        case .sepia: return Color(red: 0.98, green: 0.95, blue: 0.89)
        default: return Color(.textBackgroundColor)
        }
    }
}
