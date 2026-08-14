import Foundation

struct AIChatMessage: Codable {
    let role: String
    let content: String
}

struct AIProviderPreset: Identifiable {
    let id: String
    let name: String
    let hint: String
    let baseURL: String
    let defaultModel: String
    let needsKey: Bool
    var isProxy: Bool = false
}

enum AIProviderPresets {
    static let all: [AIProviderPreset] = [
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            hint: "gpt-4o-mini, gpt-4o",
            baseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            needsKey: true
        ),
        AIProviderPreset(
            id: "groq",
            name: "Groq",
            hint: "llama-3.3-70b-versatile",
            baseURL: "https://api.groq.com/openai/v1",
            defaultModel: "llama-3.3-70b-versatile",
            needsKey: true
        ),
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            hint: "deepseek-chat",
            baseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            needsKey: true
        ),
        AIProviderPreset(
            id: "ollama",
            name: "Ollama (локально)",
            hint: "LM Studio / локальный сервер",
            baseURL: "http://localhost:11434/v1",
            defaultModel: "gemma3:1b",
            needsKey: false
        ),
        AIProviderPreset(
            id: "golosok_proxy",
            name: "Голосок+",
            hint: "Облачные модели на серверах Голоска — по подписке",
            baseURL: "https://golosok.space/api/v1",
            defaultModel: "",
            needsKey: false,
            isProxy: true
        )
    ]

    static func preset(id: String) -> AIProviderPreset? {
        all.first { $0.id == id }
    }
}

struct AIProviderConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let isProxy: Bool
}

enum AIError: LocalizedError {
    case notConfigured
    case invalidURL
    case network(String)
    case http(Int, String)
    case emptyResponse
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "ИИ-провайдер не настроен")
        case .invalidURL:
            return String(localized: "Некорректный baseURL")
        case .network(let message):
            return String(localized: "Сетевая ошибка") + ": \(message)"
        case .http(let code, let message):
            return String(localized: "Ошибка сервера") + " \(code): \(message)"
        case .emptyResponse:
            return String(localized: "Модель вернула пустой ответ")
        case .parse(let message):
            return String(localized: "Не удалось разобрать ответ") + ": \(message)"
        }
    }
}

final class AIProviderStore: ObservableObject {
    static let shared = AIProviderStore()

    @Published var providerID: String { didSet { Self.defaults.set(providerID, forKey: "ai.providerID") } }
    @Published var baseURL: String { didSet { Self.defaults.set(baseURL, forKey: "ai.baseURL") } }
    @Published var model: String { didSet { Self.defaults.set(model, forKey: "ai.model") } }
    @Published var apiKey: String { didSet { if apiKey != oldValue { KeyStore.set(apiKey, for: "ai.apiKey") } } }

    @Published var isTesting = false
    @Published var testResult: String?
    @Published var testOK = false
    @Published var installedModels: [String] = []
    @Published var isLoadingModels = false

    private static let defaults = UserDefaults.standard

    private init() {
        let initialPreset = AIProviderPresets.preset(id: Self.defaults.string(forKey: "ai.providerID") ?? "") ?? AIProviderPresets.all[0]
        providerID = Self.defaults.string(forKey: "ai.providerID") ?? initialPreset.id
        baseURL = Self.defaults.string(forKey: "ai.baseURL") ?? initialPreset.baseURL
        model = Self.defaults.string(forKey: "ai.model") ?? initialPreset.defaultModel
        apiKey = KeyStore.get("ai.apiKey") ?? ""
    }

    var currentPreset: AIProviderPreset? {
        AIProviderPresets.preset(id: providerID)
    }

    var config: AIProviderConfig {
        let isProxy = currentPreset?.isProxy ?? false
        return AIProviderConfig(
            baseURL: baseURL,
            apiKey: isProxy ? AccountStore.shared.token : apiKey,
            model: model,
            isProxy: isProxy
        )
    }

    var isConfigured: Bool {
        if currentPreset?.isProxy == true {
            return true
        }
        return !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
            && (apiKey.isEmpty ? !(currentPreset?.needsKey ?? true) : true)
    }

    func apply(_ preset: AIProviderPreset) {
        providerID = preset.id
        baseURL = preset.baseURL
        model = preset.defaultModel
        testResult = nil
        testOK = false
        installedModels = []
        if preset.id == "ollama" {
            refreshModels()
        }
        AppLogger.shared.info("AI", "Выбран провайдер \(preset.name)", details: preset.baseURL)
    }

    func refreshModels() {
        guard !(currentPreset?.isProxy ?? false) else { return }
        isLoadingModels = true
        installedModels = []
        AIService.shared.listModels(using: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingModels = false
                switch result {
                case .success(let models):
                    self.installedModels = models.sorted()
                case .failure:
                    self.installedModels = []
                }
            }
        }
    }

    func testConnection() {
        guard isConfigured else {
            testOK = false
            testResult = currentPreset?.isProxy == true ? String(localized: "Подключите аккаунт") : String(localized: "Заполните baseURL и модель")
            return
        }
        if currentPreset?.isProxy == true {
            testOK = true
            testResult = String(localized: "Сервер доступен через аккаунт")
            return
        }
        isTesting = true
        testResult = nil
        testOK = false
        AIService.shared.test(using: config) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTesting = false
                switch result {
                case .success:
                    self.testOK = true
                    self.testResult = String(localized: "Подключено")
                    AppLogger.shared.info("AI", "Проверка подключения успешна", details: "\(self.baseURL) / \(self.model)")
                case .failure(let error):
                    self.testOK = false
                    self.testResult = error.localizedDescription
                    AppLogger.shared.warn("AI", "Проверка подключения не удалась", details: error.localizedDescription)
                }
            }
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    private struct ChatRequest: Codable {
        let model: String?
        let messages: [AIChatMessage]
        let temperature: Double
    }

    func chat(messages: [AIChatMessage], using config: AIProviderConfig, completion: @escaping (Result<String, AIError>) -> Void) {
        guard let url = url(config.baseURL, path: "chat/completions") else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        addProxyHeaders(&request, config: config)
        let body = ChatRequest(model: config.isProxy ? nil : config.model, messages: messages, temperature: 0.3)
        guard let data = try? JSONEncoder().encode(body) else {
            completion(.failure(.parse("кодирование запроса")))
            return
        }
        request.httpBody = data

        AppLogger.shared.info("AI", "Запрос к модели", details: "\(config.baseURL) / \(config.model), токенов в промпте ~\(messages.reduce(0) { $0 + $1.content.count } / 4)")

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network("нет HTTP-ответа")))
                return
            }
            guard let data else {
                completion(.failure(.emptyResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.http(http.statusCode, Self.extractError(from: data) ?? "HTTP \(http.statusCode)")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.parse("не JSON")))
                return
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.isEmpty else {
                completion(.failure(.emptyResponse))
                return
            }
            completion(.success(content))
        }.resume()
    }

    func test(using config: AIProviderConfig, completion: @escaping (Result<Void, AIError>) -> Void) {
        guard let url = url(config.baseURL, path: "models") else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        addProxyHeaders(&request, config: config)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network("нет HTTP-ответа")))
                return
            }
            if (200..<300).contains(http.statusCode) {
                completion(.success(()))
            } else {
                let message = (data.flatMap { Self.extractError(from: $0) }) ?? "HTTP \(http.statusCode)"
                completion(.failure(.http(http.statusCode, message)))
            }
        }.resume()
    }

    func listModels(using config: AIProviderConfig, completion: @escaping (Result<[String], AIError>) -> Void) {
        guard let url = url(config.baseURL, path: "models") else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        addProxyHeaders(&request, config: config)
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                completion(.failure(.emptyResponse))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.parse("не JSON")))
                return
            }
            var names: [String] = []
            if let dataArr = json["data"] as? [[String: Any]] {
                names = dataArr.compactMap { $0["id"] as? String }
            }
            if names.isEmpty, let models = json["models"] as? [[String: Any]] {
                names = models.compactMap { $0["name"] as? String }
            }
            completion(.success(names))
        }.resume()
    }

    private func url(_ base: String, path: String) -> URL? {
        URL(string: "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))/\(path)")
    }

    private func addProxyHeaders(_ request: inout URLRequest, config: AIProviderConfig) {
        guard config.isProxy else { return }
        request.setValue(Telemetry.shared.deviceID, forHTTPHeaderField: "X-Device-ID")
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            request.setValue(version, forHTTPHeaderField: "X-App-Version")
        }
        request.setValue(ProcessInfo.processInfo.operatingSystemVersionString, forHTTPHeaderField: "X-OS-Version")
    }

    private static func extractError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return nil
    }
}
