import SwiftUI
import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case ru = "ru"
    case en = "en"
    var id: String { rawValue }
}

final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()

    @AppStorage("appLanguage") var rawLanguage: String = AppLanguage.system.rawValue

    var current: AppLanguage {
        AppLanguage(rawValue: rawLanguage) ?? .system
    }

    private init() {
        apply()
    }

    func apply() {
        switch current {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .ru:
            UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    func select(_ language: AppLanguage) {
        guard current != language else { return }
        rawLanguage = language.rawValue
        apply()
        relaunch()
    }

    private func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let script = "sleep 1; open \"\(bundlePath)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }
}