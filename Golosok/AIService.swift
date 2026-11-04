import Foundation
import SwiftUI

struct AIChatMessage: Codable {
    let role: String
    let content: String
}

struct AIProviderPreset: Identifiable {
    let id: String
    let name: String
    let hint: LocalizedStringKey
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

enum AIReasoningEffort: String, CaseIterable, Identifiable {
    case off = "off"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Выкл (не передавать)"
        case .low: return "Low (минимальный)"
        case .medium: return "Medium (средний)"
        case .high: return "High (глубокий)"
        }
    }
}

enum AIThinkingBudgetMode: String, CaseIterable, Identifiable {
    case off = "off"
    case fixed1024 = "fixed1024"
    case proportional = "proportional"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .off: return "Выкл (как сейчас)"
        case .fixed1024: return "Фиксированный (1024 токена)"
        case .proportional: return "Текст × 2 токена"
        }
    }
}

struct AIProviderConfig {
    let baseURL: String
    let apiKey: String
    let model: String
    let isProxy: Bool
    let reasoningEffort: AIReasoningEffort
    let thinkingBudgetMode: AIThinkingBudgetMode
    let maxTokens: Int
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
    @Published var baseURL: String {
        didSet {
            Self.defaults.set(baseURL, forKey: "ai.baseURL")
            Self.defaults.set(baseURL, forKey: "ai.provider.\(providerID).baseURL")
        }
    }
    @Published var model: String {
        didSet {
            Self.defaults.set(model, forKey: "ai.model")
            Self.defaults.set(model, forKey: "ai.provider.\(providerID).model")
        }
    }
    @Published var apiKey: String {
        didSet {
            if apiKey != oldValue {
                KeyStore.set(apiKey, for: "ai.apiKey")
                KeyStore.set(apiKey, for: "ai.provider.\(providerID).apiKey")
            }
        }
    }
    @Published var allowInsecureHTTP: Bool { didSet { Self.defaults.set(allowInsecureHTTP, forKey: "ai.allowInsecureHTTP") } }
    @Published var reasoningEffort: AIReasoningEffort { didSet { Self.defaults.set(reasoningEffort.rawValue, forKey: "ai.reasoningEffort") } }
    @Published var thinkingBudgetMode: AIThinkingBudgetMode { didSet { Self.defaults.set(thinkingBudgetMode.rawValue, forKey: "ai.thinkingBudgetMode") } }
    @Published var maxTokensString: String { didSet { Self.defaults.set(maxTokensString, forKey: "ai.maxTokens") } }

    var maxTokens: Int {
        if let val = Int(maxTokensString.trimmingCharacters(in: .whitespaces)), val > 0 {
            return val
        }
        return 4096
    }

    @Published var isTesting = false
    @Published var testResult: String?
    @Published var testOK = false
    @Published var installedModels: [String] = []
    @Published var isLoadingModels = false

    private static let defaults = UserDefaults.standard

    private init() {
        let initialPreset = AIProviderPresets.preset(id: Self.defaults.string(forKey: "ai.providerID") ?? "") ?? AIProviderPresets.all[0]
        let currentID = Self.defaults.string(forKey: "ai.providerID") ?? initialPreset.id
        providerID = currentID
        baseURL = Self.defaults.string(forKey: "ai.provider.\(currentID).baseURL")
            ?? Self.defaults.string(forKey: "ai.baseURL")
            ?? initialPreset.baseURL
        model = Self.defaults.string(forKey: "ai.provider.\(currentID).model")
            ?? Self.defaults.string(forKey: "ai.model")
            ?? initialPreset.defaultModel
        apiKey = KeyStore.get("ai.provider.\(currentID).apiKey")
            ?? KeyStore.get("ai.apiKey")
            ?? ""
        allowInsecureHTTP = Self.defaults.object(forKey: "ai.allowInsecureHTTP") as? Bool ?? true

        if let rawEffort = Self.defaults.string(forKey: "ai.reasoningEffort"),
           let effort = AIReasoningEffort(rawValue: rawEffort) {
            reasoningEffort = effort
        } else {
            reasoningEffort = .low
        }

        if let rawBudget = Self.defaults.string(forKey: "ai.thinkingBudgetMode"),
           let budget = AIThinkingBudgetMode(rawValue: rawBudget) {
            thinkingBudgetMode = budget
        } else {
            thinkingBudgetMode = .fixed1024
        }

        maxTokensString = Self.defaults.string(forKey: "ai.maxTokens") ?? "4096" 
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
            isProxy: isProxy,
            reasoningEffort: reasoningEffort,
            thinkingBudgetMode: thinkingBudgetMode,
            maxTokens: maxTokens
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
        guard providerID != preset.id else {
            // Если выбран тот же пресет, не сбрасываем пользовательские настройки
            return
        }

        providerID = preset.id

        // Восстанавливаем ранее сохраненные настройки именно для этого провайдера,
        // либо берем дефолтные значения пресета
        baseURL = Self.defaults.string(forKey: "ai.provider.\(preset.id).baseURL") ?? preset.baseURL
        model = Self.defaults.string(forKey: "ai.provider.\(preset.id).model") ?? preset.defaultModel
        apiKey = KeyStore.get("ai.provider.\(preset.id).apiKey") ?? (preset.needsKey ? "" : "")

        testResult = nil
        testOK = false
        installedModels = []
        if preset.id == "ollama" {
            refreshModels()
        }
        AppLogger.shared.info("AI", "Выбран провайдер \(preset.name)", details: baseURL)
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
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmedURL.hasPrefix("http://") && !allowInsecureHTTP {
            testOK = false
            testResult = String(localized: "HTTP запрещён. Включите разрешение HTTP или используйте HTTPS.")
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

    private struct ChatThinking: Codable {
        let type: String?
        let budget_tokens: Int?
    }

    private struct ChatRequest: Codable {
        let model: String?
        let messages: [AIChatMessage]
        let temperature: Double
        let max_tokens: Int?
        let max_completion_tokens: Int?
        let reasoning_effort: String?
        let thinking: ChatThinking?
        let max_thinking_tokens: Int?
        let stream: Bool?
    }

    @discardableResult
    func chatStream(
        messages: [AIChatMessage],
        using config: AIProviderConfig,
        promptLength: Int? = nil,
        onChunk: @escaping (String, String?) -> Void,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> URLSessionDataTask? {
        guard let url = url(config.baseURL, path: "chat/completions") else {
            completion(.failure(.invalidURL))
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        addProxyHeaders(&request, config: config)

        let userMaxTokens = config.maxTokens > 0 ? config.maxTokens : 4096
        let chars = promptLength ?? messages.reduce(0) { $0 + $1.content.count }
        let approxPromptTokens = max(64, chars / 4)
        let minTokensForOutput = approxPromptTokens + 512

        let reasoningEffortParam: String? = config.reasoningEffort == .off ? nil : config.reasoningEffort.rawValue
        var thinkingParam: ChatThinking? = nil
        var maxThinkingTokensParam: Int? = nil
        var maxTokensParam: Int = userMaxTokens

        switch config.thinkingBudgetMode {
        case .off:
            thinkingParam = nil
            maxThinkingTokensParam = nil
            maxTokensParam = max(userMaxTokens, minTokensForOutput)
        case .fixed1024:
            let budget = 1024
            thinkingParam = ChatThinking(type: "enabled", budget_tokens: budget)
            maxThinkingTokensParam = budget
            maxTokensParam = max(userMaxTokens, budget + minTokensForOutput)
        case .proportional:
            let budget = max(256, approxPromptTokens * 2)
            thinkingParam = ChatThinking(type: "enabled", budget_tokens: budget)
            maxThinkingTokensParam = budget
            maxTokensParam = max(userMaxTokens, budget + minTokensForOutput)
        }

        let body = ChatRequest(
            model: config.isProxy ? nil : config.model,
            messages: messages,
            temperature: 0.3,
            max_tokens: maxTokensParam,
            max_completion_tokens: maxTokensParam,
            reasoning_effort: reasoningEffortParam,
            thinking: thinkingParam,
            max_thinking_tokens: maxThinkingTokensParam,
            stream: true
        )
        guard let data = try? JSONEncoder().encode(body) else {
            completion(.failure(.parse("кодирование запроса")))
            return nil
        }
        request.httpBody = data

        let budgetDesc = maxThinkingTokensParam != nil ? ", thinking_budget=\(maxThinkingTokensParam!)" : ""
        let effortDesc = reasoningEffortParam != nil ? ", effort=\(reasoningEffortParam!)" : ""
        AppLogger.shared.info("AI", "Стриминг-запрос к модели", details: "\(config.baseURL) / \(config.model), max_tokens=\(maxTokensParam)\(effortDesc)\(budgetDesc), токенов в промпте ~\(messages.reduce(0) { $0 + $1.content.count } / 4)")

        return SSEStreamManager.shared.startStream(with: request, onChunk: onChunk, completion: completion)
    }

    @discardableResult
    func chat(messages: [AIChatMessage], using config: AIProviderConfig, promptLength: Int? = nil, completion: @escaping (Result<String, AIError>) -> Void) -> URLSessionDataTask? {
        guard let url = url(config.baseURL, path: "chat/completions") else {
            completion(.failure(.invalidURL))
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        addProxyHeaders(&request, config: config)

        let userMaxTokens = config.maxTokens > 0 ? config.maxTokens : 4096
        let chars = promptLength ?? messages.reduce(0) { $0 + $1.content.count }
        let approxPromptTokens = max(64, chars / 4)
        let minTokensForOutput = approxPromptTokens + 512

        let reasoningEffortParam: String? = config.reasoningEffort == .off ? nil : config.reasoningEffort.rawValue
        var thinkingParam: ChatThinking? = nil
        var maxThinkingTokensParam: Int? = nil
        var maxTokensParam: Int = userMaxTokens

        switch config.thinkingBudgetMode {
        case .off:
            thinkingParam = nil
            maxThinkingTokensParam = nil
            maxTokensParam = max(userMaxTokens, minTokensForOutput)
        case .fixed1024:
            let budget = 1024
            thinkingParam = ChatThinking(type: "enabled", budget_tokens: budget)
            maxThinkingTokensParam = budget
            maxTokensParam = max(userMaxTokens, budget + minTokensForOutput)
        case .proportional:
            let budget = max(256, approxPromptTokens * 2)
            thinkingParam = ChatThinking(type: "enabled", budget_tokens: budget)
            maxThinkingTokensParam = budget
            maxTokensParam = max(userMaxTokens, budget + minTokensForOutput)
        }

        let body = ChatRequest(
            model: config.isProxy ? nil : config.model,
            messages: messages,
            temperature: 0.3,
            max_tokens: maxTokensParam,
            max_completion_tokens: maxTokensParam,
            reasoning_effort: reasoningEffortParam,
            thinking: thinkingParam,
            max_thinking_tokens: maxThinkingTokensParam,
            stream: false
        )
        guard let data = try? JSONEncoder().encode(body) else {
            completion(.failure(.parse("кодирование запроса")))
            return nil
        }
        request.httpBody = data

        let budgetDesc = maxThinkingTokensParam != nil ? ", thinking_budget=\(maxThinkingTokensParam!)" : ""
        let effortDesc = reasoningEffortParam != nil ? ", effort=\(reasoningEffortParam!)" : ""
        AppLogger.shared.info("AI", "Запрос к модели", details: "\(config.baseURL) / \(config.model), max_tokens=\(maxTokensParam)\(effortDesc)\(budgetDesc), токенов в промпте ~\(messages.reduce(0) { $0 + $1.content.count } / 4)")

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                if (error as NSError).code == NSURLErrorCancelled {
                    AppLogger.shared.info("AI", "Запрос к модели отменён пользователем")
                    return
                }
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
        }
        task.resume()
        return task
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

    static func extractError(from data: Data) -> String? {
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

final class SSEStreamManager: NSObject, URLSessionDataDelegate {
    static let shared = SSEStreamManager()

    private class TaskContext {
        var buffer = ""
        var fullContent = ""
        var fullReasoning = ""
        var isInThinkTag = false
        var hasCompleted = false
        var httpStatusCode: Int?
        var errorData: Data?
        let onChunk: (String, String?) -> Void
        let completion: (Result<String, AIError>) -> Void

        init(onChunk: @escaping (String, String?) -> Void, completion: @escaping (Result<String, AIError>) -> Void) {
            self.onChunk = onChunk
            self.completion = completion
        }
    }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var contexts: [Int: TaskContext] = [:]
    private let lock = NSLock()

    func startStream(
        with request: URLRequest,
        onChunk: @escaping (String, String?) -> Void,
        completion: @escaping (Result<String, AIError>) -> Void
    ) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        let context = TaskContext(onChunk: onChunk, completion: completion)
        lock.lock()
        contexts[task.taskIdentifier] = context
        lock.unlock()
        task.resume()
        return task
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let ctx = contexts[dataTask.taskIdentifier]
        lock.unlock()

        if let http = response as? HTTPURLResponse {
            ctx?.httpStatusCode = http.statusCode
            if !(200..<300).contains(http.statusCode) {
                ctx?.errorData = Data()
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let ctx = contexts[dataTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        lock.unlock()

        if let status = ctx.httpStatusCode, !(200..<300).contains(status) {
            ctx.errorData?.append(data)
            return
        }

        guard let text = String(data: data, encoding: .utf8) else { return }
        ctx.buffer.append(text)

        var lines: [String] = []
        while let range = ctx.buffer.range(of: "\n") {
            let line = String(ctx.buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.buffer.removeSubrange(..<range.upperBound)
            if !line.isEmpty {
                lines.append(line)
            }
        }

        for line in lines {
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    completeTask(dataTask.taskIdentifier, with: .success(ctx.fullContent))
                    return
                }
                guard let jsonData = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let delta = firstChoice["delta"] as? [String: Any] else {
                    continue
                }

                let rawContent = delta["content"] as? String
                let rawReasoning = (delta["reasoning_content"] as? String) ?? (delta["thinking"] as? String)

                var contentChunk: String? = nil
                var reasoningChunk: String? = nil

                if let rawReasoning, !rawReasoning.isEmpty {
                    reasoningChunk = rawReasoning
                }

                if var text = rawContent, !text.isEmpty {
                    if text.contains("<think>") {
                        ctx.isInThinkTag = true
                        text = text.replacingOccurrences(of: "<think>", with: "")
                    }
                    if ctx.isInThinkTag {
                        if text.contains("</think>") {
                            ctx.isInThinkTag = false
                            let parts = text.components(separatedBy: "</think>")
                            let thinkPart = parts.first ?? ""
                            let cleanPart = parts.dropFirst().joined(separator: "</think>")
                            if !thinkPart.isEmpty {
                                reasoningChunk = (reasoningChunk ?? "") + thinkPart
                            }
                            if !cleanPart.isEmpty {
                                contentChunk = cleanPart
                            }
                        } else {
                            reasoningChunk = (reasoningChunk ?? "") + text
                        }
                    } else {
                        contentChunk = text
                    }
                }

                if let contentChunk, !contentChunk.isEmpty {
                    ctx.fullContent.append(contentChunk)
                }
                if let reasoningChunk, !reasoningChunk.isEmpty {
                    ctx.fullReasoning.append(reasoningChunk)
                }

                if (contentChunk != nil && !contentChunk!.isEmpty) || (reasoningChunk != nil && !reasoningChunk!.isEmpty) {
                    DispatchQueue.main.async {
                        ctx.onChunk(contentChunk ?? "", reasoningChunk)
                    }
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        lock.lock()
        guard let ctx = contexts[taskID] else {
            lock.unlock()
            return
        }
        lock.unlock()

        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled {
                AppLogger.shared.info("AI", "Стриминг остановлен пользователем", details: "длина текста: \(ctx.fullContent.count)")
                if !ctx.fullContent.isEmpty {
                    completeTask(taskID, with: .success(ctx.fullContent))
                } else {
                    removeTask(taskID)
                }
                return
            }
            completeTask(taskID, with: .failure(.network(error.localizedDescription)))
            return
        }

        if let status = ctx.httpStatusCode, !(200..<300).contains(status) {
            let errorMsg = ctx.errorData.flatMap { AIService.extractError(from: $0) } ?? "HTTP \(status)"
            completeTask(taskID, with: .failure(.http(status, errorMsg)))
            return
        }

        if !ctx.fullContent.isEmpty {
            completeTask(taskID, with: .success(ctx.fullContent))
        } else {
            completeTask(taskID, with: .failure(.emptyResponse))
        }
    }

    private func completeTask(_ id: Int, with result: Result<String, AIError>) {
        lock.lock()
        guard let ctx = contexts[id], !ctx.hasCompleted else {
            lock.unlock()
            return
        }
        ctx.hasCompleted = true
        contexts.removeValue(forKey: id)
        lock.unlock()

        DispatchQueue.main.async {
            ctx.completion(result)
        }
    }

    private func removeTask(_ id: Int) {
        lock.lock()
        contexts.removeValue(forKey: id)
        lock.unlock()
    }
}
