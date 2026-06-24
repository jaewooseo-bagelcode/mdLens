import SwiftUI

public enum AppThemeMode: String, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    public var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light, .sepia: return .light
        case .dark: return .dark
        }
    }

    public var backgroundColor: Color {
        switch self {
        case .sepia: return Color(red: 0.98, green: 0.95, blue: 0.89)
        default: return Color(.textBackgroundColor)
        }
    }
}
