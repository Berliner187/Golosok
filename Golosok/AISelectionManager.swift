import Foundation
import AppKit
import Carbon
import ApplicationServices

/// Менеджер глобальной ИИ-обработки выделенного текста.
///
/// Назначение:
/// Реализует сквозной конвейер:
/// 1. Перехват активного приложения пользователя по глобальному хоткею (⌥ + ⇧ + Space).
/// 2. Захват выделенного текста (через Accessibility API с откатом на буфер обмена Cmd+C).
/// 3. Показ компактного всплывающего окна со встроенными и пользовательскими промптами.
/// 4. Отправка запроса в локальный инференс LLM (llama-server / Ollama) или облачный API через `AIService`.
/// 5. Автоматическая замена выделенного текста результатом генерации (через эмуляцию Cmd+V).
final class AISelectionManager {
    static let shared = AISelectionManager()

    private var isBusy = false
    private var currentTask: URLSessionDataTask?
    private var escMonitor: Any?

    private init() {}

    /// Основная точка входа: вызывается при нажатии глобального хоткея
    func trigger() {
        guard !isBusy else {
            AppLogger.shared.info("AISelection", "Запрос пропущен: предыдущая операция еще выполняется")
            return
        }

        // Проверка прав Универсального доступа (Accessibility) для чтения и отправки нажатий клавиш
        guard PermissionManager.shared.isAccessibilityGranted else {
            AppLogger.shared.warn("AISelection", "Отсутствуют права Accessibility")
            AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Включите доступ в Настройках macOS"))
            return
        }

        // Проверка настройки ИИ-провайдера (Ollama, llama-server или облачные API)
        guard AIProviderStore.shared.isConfigured else {
            AppLogger.shared.warn("AISelection", "ИИ-провайдер не настроен")
            AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Настройте ИИ-провайдер в Голоске"))
            return
        }

        // Запоминаем текущее активное приложение, откуда вызван хоткей
        guard let targetApp = NSWorkspace.shared.frontmostApplication else {
            AppLogger.shared.warn("AISelection", "Не удалось определить активное приложение")
            return
        }

        let pid = targetApp.processIdentifier
        AppLogger.shared.info("AISelection", "Старт обработки выделения", details: "Целевое приложение: \(targetApp.localizedName ?? "PID \(pid)")")

        // Извлекаем выделенный текст
        extractSelectedText(from: targetApp) { [weak self] extractedText in
            guard let self else { return }

            guard let text = extractedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                AppLogger.shared.info("AISelection", "Текст не выделен или пуст")
                AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Сначала выделите текст"))
                return
            }

            self.presentPromptPalette(for: text, targetApp: targetApp)
        }
    }

    // MARK: - Извлечение выделенного текста

    /// Извлечение выделенного фрагмента.
    /// Сначала опрашивается Accessibility API (не затирая буфер обмена).
    /// Если приложение не отдаёт атрибут AXSelectedText, используется безопасный fallback через Cmd+C.
    private func extractSelectedText(from app: NSRunningApplication, completion: @escaping (String?) -> Void) {
        let pid = app.processIdentifier

        // Попытка 1: Чтение через AXUIElement
        if let axText = readAXSelectedText(pid: pid), !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(axText)
            return
        }

        // Попытка 2: Симуляция Cmd+C с сохранением и восстановлением предыдущего буфера
        copyViaPasteboard(pid: pid, completion: completion)
    }

    private func readAXSelectedText(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElement = focusedElementRef else {
            return nil
        }

        var selectedTextRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
              let selectedString = selectedTextRef as? String else {
            return nil
        }

        return selectedString
    }

    private func copyViaPasteboard(pid: pid_t, completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        // Сохраняем предыдущий текст буфера для восстановления в случае отсутствия выделения
        let previousString = pasteboard.string(forType: .string)

        // Посылаем Cmd+C целевому приложению (виртуальная клавиша 0x08 = 'C')
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
            completion(nil)
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)

        // Ожидание реакции приложения на копирование
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if pasteboard.changeCount != initialChangeCount,
               let text = pasteboard.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(text)
            } else {
                // Вторая короткая попытка для тяжелых приложений (Electron, браузеры)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                    if pasteboard.changeCount != initialChangeCount,
                       let text = pasteboard.string(forType: .string),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        completion(text)
                    } else {
                        // Ничего не скопировалось — восстанавливаем старый буфер
                        if let prev = previousString {
                            pasteboard.clearContents()
                            pasteboard.setString(prev, forType: .string)
                        }
                        completion(nil)
                    }
                }
            }
        }
    }

    // MARK: - Показ палитры промптов

    private func presentPromptPalette(for text: String, targetApp: NSRunningApplication) {
        let templates = PromptStore.shared.templates
        guard !templates.isEmpty else {
            AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Список промптов пуст"))
            return
        }

        // Привязываем окно палитры к текущей позиции курсора мыши
        let mouseLoc = NSEvent.mouseLocation
        let anchorRect = CGRect(x: mouseLoc.x, y: mouseLoc.y, width: 1, height: 1)

        AISelectionToolbarPresenter.shared.present(
            anchorScreenRect: anchorRect,
            templates: templates,
            onPick: { [weak self] selectedTemplate in
                self?.processText(text, with: selectedTemplate, targetApp: targetApp)
            },
            onClose: {
                AppLogger.shared.info("AISelection", "Палитра промптов закрыта пользователем")
            }
        )
    }

    // MARK: - Выполнение запроса в LLM и вставка результата

    private func processText(_ text: String, with template: AIPromptTemplate, targetApp: NSRunningApplication) {
        isBusy = true
        AppLogger.shared.info("AISelection", "Применение шаблона", details: "\(template.title) для \(text.count) символов")

        // Запуск красивого плавающего оверлея Голоска
        AudioCapture.shared.startAIProcessing(status: String(localized: "ИИ-обработка..."))

        // Подключаем монитор Esc для возможности отмены длинной генерации
        installEscMonitor()

        let messages = template.messages(for: text)
        let config = AIProviderStore.shared.config

        currentTask = AIService.shared.chat(messages: messages, using: config, promptLength: text.count) { [weak self] result in
            guard let self else { return }

            DispatchQueue.main.async {
                self.removeEscMonitor()
                self.currentTask = nil
                self.isBusy = false

                switch result {
                case .success(let generatedText):
                    let clean = generatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else {
                        AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Пустой ответ от модели"))
                        return
                    }

                    self.replaceSelection(originalText: text, with: clean, templateTitle: template.title, in: targetApp)

                case .failure(let error):
                    if case .network(let msg) = error, msg.contains("cancelled") || msg.contains("отмен") {
                        AppLogger.shared.info("AISelection", "Генерация отменена пользователем")
                        AudioCapture.shared.cancelAIProcessing()
                        return
                    }
                    AppLogger.shared.error("AISelection", "Ошибка инференса LLM", details: error.localizedDescription)
                    AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Ошибка ИИ: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancelCurrentOperation()
            }
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }

    func cancelCurrentOperation() {
        AppLogger.shared.info("AISelection", "Отмена операции пользователем")
        currentTask?.cancel()
        currentTask = nil
        removeEscMonitor()
        isBusy = false
        AudioCapture.shared.cancelAIProcessing()
    }

    private func replaceSelection(originalText: String, with newText: String, templateTitle: String, in targetApp: NSRunningApplication) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)

        let pid = targetApp.processIdentifier
        targetApp.activate(options: [.activateIgnoringOtherApps])

        // Небольшая задержка перед вставкой, чтобы целевое приложение успело активироваться
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true), // 0x09 = 'V'
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
                AudioCapture.shared.cancelAIProcessing(warning: String(localized: "Не удалось эмулировать Cmd+V"))
                return
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)

            // Успешный финиш с анимацией галочки и звуком
            AudioCapture.shared.finishAIProcessing()
            AppLogger.shared.info("AISelection", "Выделенный текст успешно заменен", details: "\(targetApp.localizedName ?? "приложение"), вставлено \(newText.count) симв.")

            // Сохраняем в историю заметок Голоска в формате «Было / Стало» с отметкой ИИ
            AudioCapture.shared.addAINote(originalText: originalText, transformedText: newText, templateTitle: templateTitle)
        }
    }
}
