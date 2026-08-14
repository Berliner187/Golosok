import Foundation

struct AccountVerifyResponse: Codable {
    let valid: Bool
    let subscription: String?
    let features: [String]?
    let expiresAt: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case valid, subscription, features, error
        case expiresAt = "expires_at"
    }
}

enum AccountStatus: Equatable {
    case notConnected
    case verifying
    case connected(subscription: String, expiresAt: Date?)
    case invalid(message: String)
}

final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    static let verifyBaseURL = "https://golosok.space"
    static let loginURL = URL(string: "https://golosok.space/login/")!

    // Гейтинг фич остаётся выключенным до включения оплаты: BYO-ключ бесплатен всегда.
    // Проверка токена при этом — живая, идёт на реальный эндпоинт.
    static let isGatingEnabled = false

    @Published var token: String {
        didSet {
            if token != oldValue {
                if token.isEmpty { KeyStore.delete("account.token") }
                else { KeyStore.set(token, for: "account.token") }
            }
        }
    }

    @Published private(set) var status: AccountStatus = .notConnected
    @Published private(set) var features: [String] = []

    private var verifyTask: URLSessionDataTask?
    private var activeVerifyID: UUID?

    private init() {
        token = KeyStore.get("account.token") ?? ""
        if !token.isEmpty { verify() }
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var subscription: String {
        if case .connected(let sub, _) = status { return sub }
        return "base"
    }

    var tierName: String {
        subscription == "echo" ? String(localized: "Голосок+") : String(localized: "Базовый")
    }

    func hasFeature(_ id: String) -> Bool {
        if !Self.isGatingEnabled { return true }
        return features.contains(id)
    }

    func save(token rawToken: String) {
        let cleaned = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        token = cleaned
        verify()
    }

    func signOut() {
        verifyTask?.cancel()
        verifyTask = nil
        activeVerifyID = nil
        token = ""
        features = []
        status = .notConnected
        AppLogger.shared.info("Account", "Токен удалён")
    }

    func verify() {
        guard !token.isEmpty else {
            status = .notConnected
            features = []
            return
        }
        status = .verifying

        verifyTask?.cancel()
        verifyTask = nil
        let requestID = UUID()
        activeVerifyID = requestID

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.activeVerifyID == requestID else { return }
            self.performVerify(requestID: requestID)
        }
    }

    private func performVerify(requestID: UUID) {
        guard let url = URL(string: "\(Self.verifyBaseURL)/api/v1/auth/verify") else {
            status = .invalid(message: String(localized: "Некорректный адрес сервера"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        AppLogger.shared.info("Account", "Проверка токена", details: "POST \(url.path)")
        verifyTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.activeVerifyID == requestID else { return }
                self.verifyTask = nil

                if let error {
                    self.status = .invalid(message: String(localized: "Сетевая ошибка") + ": \(error.localizedDescription)")
                    AppLogger.shared.warn("Account", "Проверка токена не удалась", details: error.localizedDescription)
                    return
                }
                guard let data else {
                    self.status = .invalid(message: String(localized: "Пустой ответ сервера"))
                    return
                }

                if let decoded = try? JSONDecoder().decode(AccountVerifyResponse.self, from: data) {
                    if decoded.valid {
                        let expires = decoded.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
                        self.features = decoded.features ?? []
                        self.status = .connected(subscription: decoded.subscription ?? "base", expiresAt: expires)
                        AppLogger.shared.info("Account", "Токен подтверждён", details: "subscription=\(decoded.subscription ?? "base"), features=\(self.features.count)")
                        return
                    }
                    self.features = []
                    self.status = .invalid(message: decoded.error ?? String(localized: "Токен отклонён сервером"))
                    AppLogger.shared.warn("Account", "Токен отклонён", details: decoded.error ?? "нет причины")
                    return
                }

                self.features = []
                self.status = .invalid(message: String(localized: "Не удалось разобрать ответ сервера"))
            }
        }
        verifyTask?.resume()
    }
}
