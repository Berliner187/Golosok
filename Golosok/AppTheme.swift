import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()

    @AppStorage("appTheme") var rawTheme: String = AppTheme.system.rawValue

    var current: AppTheme {
        AppTheme(rawValue: rawTheme) ?? .system
    }

    private init() {}
}
