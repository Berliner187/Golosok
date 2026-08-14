import Foundation

// Секреты (BYO-ключ, токен аккаунта) хранятся в UserDefaults на локальном диске,
// без Keychain — чтобы не выскакивал системный промпт доступа при каждом запуске.
enum KeyStore {
    private static let prefix = "keystore."

    static func set(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }

    static func get(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + key)
    }

    static func delete(_ key: String) {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}
