import Foundation
import SwiftUI

/// Статус доступности системной модели Apple (Foundation Models, macOS 26+).
enum AppleLocalAIStatus: Equatable {
    case ready
    case unsupportedOS
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady

    var title: String {
        switch self {
        case .ready:
            return String(localized: "Системная модель Apple готова к работе")
        case .unsupportedOS:
            return String(localized: "Требуется macOS 26 или новее")
        case .deviceNotEligible:
            return String(localized: "Этот Mac не поддерживается — нужен чип Apple Silicon (M1 или новее)")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Apple Intelligence недоступен: включите его и установите язык Siri на English (US) в Системных настройках")
        case .modelNotReady:
            return String(localized: "Модель ещё загружается — подождите несколько минут или перезагрузите Mac")
        }
    }
}

enum AppleLocalAI {
    static let presetID = "apple_local"

    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return true
        }
        #endif
        return false
    }

    static func status() -> AppleLocalAIStatus {
        guard isSupported else { return .unsupportedOS }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            }
        }
        #endif
        return .unsupportedOS
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Нативный доступ к системной модели Apple без сервера и скачивания весов.
@available(macOS 26, *)
final class AppleLocalAIService: @unchecked Sendable {
    static let shared = AppleLocalAIService()

    private let lock = NSLock()
    private var session: LanguageModelSession?

    private init() {}

    private func makeSession() -> LanguageModelSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let fresh = LanguageModelSession()
        session = fresh
        return fresh
    }

    /// Та же сигнатура, что у AIService.chat. Системная модель исторически
    /// генерирует на английском, поэтому инструкции оборачиваем и явно
    /// требуем ответ на языке исходного текста.
    func chat(messages: [AIChatMessage], completion: @escaping (Result<String, AIError>) -> Void) {
        let prompt = Self.composePrompt(messages: messages)
        AppLogger.shared.info("AI", "Запрос к системной модели Apple", details: "токенов в промпте ~\(prompt.count / 4)")
        Task {
            do {
                let response = try await makeSession().respond(to: prompt)
                AppLogger.shared.info("AI", "Системная модель Apple ответила", details: "\(response.content.count) символов")
                completion(.success(response.content))
            } catch {
                AppLogger.shared.warn("AI", "Системная модель Apple вернула ошибку", details: error.localizedDescription)
                completion(.failure(.network(error.localizedDescription)))
            }
        }
    }

    func test(completion: @escaping (Result<Void, AIError>) -> Void) {
        Task {
            do {
                _ = try await makeSession().respond(to: "Reply with the single word: ok")
                completion(.success(()))
            } catch {
                completion(.failure(.network(error.localizedDescription)))
            }
        }
    }

    private static func composePrompt(messages: [AIChatMessage]) -> String {
        var systemParts: [String] = []
        var userParts: [String] = []
        for message in messages {
            if message.role == "system" {
                systemParts.append(message.content)
            } else {
                userParts.append(message.content)
            }
        }
        let system = systemParts.joined(separator: "\n")
        let user = userParts.joined(separator: "\n\n")
        return """
        Follow these instructions and respond ONLY in the same language as the transcript (usually Russian).

        Instructions:
        \(system)

        Input:
        \(user)
        """
    }
}
#endif
