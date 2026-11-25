import SwiftUI
import AppKit
import Foundation

private enum OverlayMetrics {
    /// Panel and pill share the same bounds — no transparent margins,
    /// so nothing stray can cast a shadow.
    static let cardHeight: CGFloat = 56
    static let cardTint: Double = 0.28
    static let panelSize = NSSize(width: 280, height: cardHeight + 2)   // запас по бокам под тряску
    static let pillHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 14
}

/// Сколько островок остаётся на экране после результата.
enum OverlayTiming {
    static let dictationSuccessHold: TimeInterval = 1.2   // успеть доиграть схлопывание волны
    static let dictationWarningHold: TimeInterval = 3.5
    static let fileSuccessHold: TimeInterval = 2.0
    static let fileWarningHold: TimeInterval = 6.0        // успеть прочитать причину и имя файла
}

enum OverlayStyle {
    /// Диктовка с микрофона: пока идёт запись — сфера. После остановки (расшифровка, успех, ошибка) —
    /// волна из точек. false — сфера на всех этапах, как раньше.
    static let dictationUsesWave = true

    /// Закрепление окна в отдельном Space через приватный SkyLight: островок не пропадает при
    /// переключении полноэкранных Space и жестах трекпада. Аварийно выключить:
    /// defaults write <bundle id> overlayPinnedSpace -bool NO
    static var usesPinnedSpace: Bool {
        UserDefaults.standard.object(forKey: "overlayPinnedSpace") as? Bool ?? true
    }
}

/// Какой файл обрабатывается и какой он по счёту в очереди (index с 1).
struct OverlayFileContext: Equatable {
    let name: String
    let index: Int
    let total: Int
}

enum OverlayPhase: Equatable {
    case idle
    case recording
    case transcribing
    case processing(progress: Double)
    case warning(String)
    case success

    var contentWidth: CGFloat { OverlayMetrics.panelSize.width }
}

@MainActor
@Observable
final class OverlayPanelState {
    private(set) var phase: OverlayPhase = .idle
    private(set) var elapsedSeconds = 0
    private(set) var samples: [Float] = Array(repeating: 0.15, count: 18)
    /// Не nil — идёт работа с файлом (кольцо); nil — диктовка с микрофона (волна).
    private(set) var file: OverlayFileContext?
    /// Вторая строка под предупреждением (имя файла).
    private(set) var detail: String?
    /// Растёт при каждой ошибке: запускает пружинную тряску карточки.
    private(set) var shakeTick = 0
    /// Управляет появлением/исчезновением в SwiftUI. Окно само всегда alpha 1.
    var isShown = false

    func showRecording() {
        file = nil
        detail = nil
        phase = .recording
        elapsedSeconds = 0
        samples = Array(repeating: 0.15, count: 18)
    }

    func updateRecording(elapsedSeconds: Int, samples: [Float]) {
        guard phase == .recording else { return }
        if self.elapsedSeconds != elapsedSeconds {
            self.elapsedSeconds = elapsedSeconds
        }
        if self.samples != samples {
            self.samples = samples
        }
    }

    func showTranscribing() {
        file = nil
        detail = nil
        phase = .transcribing
    }

    func showProcessing(progress: Double, file: OverlayFileContext) {
        if self.file != file { self.file = file }
        detail = nil
        let clamped = min(max(progress, 0), 1)
        if case .processing(let current) = phase, abs(current - clamped) < 0.001 { return }
        phase = .processing(progress: clamped)
    }

    func showWarning(_ message: String, detail: String?, file: OverlayFileContext?) {
        self.file = file
        self.detail = detail
        phase = .warning(message)
    }

    func showSuccess(file: OverlayFileContext?) {
        self.file = file
        detail = nil
        phase = .success
    }

    func triggerShake() {
        shakeTick &+= 1
    }

    func reset() {
        phase = .idle
        file = nil
        detail = nil
        elapsedSeconds = 0
        samples = Array(repeating: 0.15, count: 18)
    }
}

// MARK: - Отдельный Space (SkyLight)

/// Приватный API WindowServer. Обычное окно с `canJoinAllSpaces` в момент переключения между
/// полноэкранными Space (жест трекпада, Ctrl+стрелки) на время пропадает. Окно, которое целиком
/// переехало в собственное «пространство» с максимальным абсолютным уровнем, остаётся на экране всегда.
/// Все символы берутся через dlsym: если их нет (другая версия macOS) — тихий откат на обычное окно.
/// Закрепление каждый раз ПРОВЕРЯЕТСЯ (в каких Space сейчас окно), а не принимается на веру.
@MainActor
private enum PinnedSpace {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int, CFDictionary?) -> Int
    private typealias SetLevelFn = @convention(c) (Int32, Int, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Void
    private typealias AddWindowsFn = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias RemoveWindowsFn = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias AddRemoveFn = @convention(c) (Int32, Int, CFArray, Int32) -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static var connection: Int32 = 0
    private static var space = 0
    private static var setLevel: SetLevelFn?
    private static var showSpaces: ShowSpacesFn?
    private static var addWindows: AddWindowsFn?
    private static var removeWindows: RemoveWindowsFn?
    private static var addAndRemove: AddRemoveFn?
    private static var copySpaces: CopySpacesFn?
    private static var prepared = false
    private(set) static var isUnavailable = false
    /// Результат последней проверки — для лога.
    private(set) static var diagnostics = ""

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ names: [String], as type: T.Type) -> T? {
        for name in names {
            if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: T.self) }
        }
        return nil
    }

    private static func giveUp(_ reason: String) -> Bool {
        isUnavailable = true
        AppLogger.shared.warn("Overlay", "SkyLight недоступен — островок остаётся обычным окном", details: reason)
        return false
    }

    /// Создаёт Space заранее (на запуске): раньше он создавался в тот же момент, когда в него клали
    /// первое окно, и первые записи после запуска закреплялись не всегда.
    @discardableResult
    static func warmUp() -> Bool { prepare() }

    private static func prepare() -> Bool {
        if prepared { return true }
        if isUnavailable { return false }

        let paths = ["/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
                     "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"]
        guard let handle = paths.lazy.compactMap({ dlopen($0, RTLD_LAZY) }).first else {
            return giveUp("не удалось загрузить SkyLight")
        }
        guard let mainConnection = symbol(handle, ["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnectionFn.self),
              let create = symbol(handle, ["SLSSpaceCreate", "CGSSpaceCreate"], as: SpaceCreateFn.self),
              let level = symbol(handle, ["SLSSpaceSetAbsoluteLevel", "CGSSpaceSetAbsoluteLevel"], as: SetLevelFn.self),
              let show = symbol(handle, ["SLSShowSpaces", "CGSShowSpaces"], as: ShowSpacesFn.self)
        else {
            return giveUp("не найдены базовые символы")
        }
        addAndRemove = symbol(handle, ["SLSSpaceAddWindowsAndRemoveFromSpaces"], as: AddRemoveFn.self)
        addWindows = symbol(handle, ["SLSAddWindowsToSpaces", "CGSAddWindowsToSpaces"], as: AddWindowsFn.self)
        removeWindows = symbol(handle, ["SLSRemoveWindowsFromSpaces", "CGSRemoveWindowsFromSpaces"], as: RemoveWindowsFn.self)
        copySpaces = symbol(handle, ["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], as: CopySpacesFn.self)
        guard addAndRemove != nil || addWindows != nil else {
            return giveUp("нет функции добавления окон в Space")
        }

        let cid = mainConnection()
        let newSpace = create(cid, 1, nil)
        guard newSpace != 0 else { return giveUp("не удалось создать Space") }
        _ = level(cid, newSpace, Int32.max)
        show(cid, [newSpace] as CFArray)

        connection = cid
        space = newSpace
        setLevel = level
        showSpaces = show
        prepared = true
        AppLogger.shared.info("Overlay", "Создан отдельный Space для островка (SkyLight)",
                              details: "space \(newSpace), проверка окна: \(copySpaces != nil), перенос: \(addAndRemove != nil ? "AddAndRemove" : "Add+Remove")")
        return true
    }

    private static func spaces(of windowNumber: Int) -> [Int]? {
        guard let copySpaces,
              let result = copySpaces(connection, 7, [windowNumber] as CFArray)?.takeRetainedValue() else { return nil }
        return (result as NSArray).compactMap { ($0 as? NSNumber)?.intValue }
    }

    /// Переносит окно целиком в закреплённый Space и проверяет результат.
    /// true — команда переноса выполнена; false — SkyLight недоступен.
    static func pin(windowNumber: Int) -> Bool {
        guard windowNumber > 0, prepare(), let setLevel, let showSpaces else { return false }
        // Систему могли «передёрнуть» (сон, смена экранов): подтверждаем уровень и показ каждый раз.
        _ = setLevel(connection, space, Int32.max)
        showSpaces(connection, [space] as CFArray)

        let windows = [windowNumber] as CFArray
        if let addAndRemove {
            // Окно добавляется в наш Space и УДАЛЯЕТСЯ из обычных (маска 7: текущий, другие, пользовательские).
            _ = addAndRemove(connection, space, windows, 7)
        } else if let addWindows {
            let before = spaces(of: windowNumber) ?? []
            addWindows(connection, windows, [space] as CFArray)
            let others = before.filter { $0 != space }
            if let removeWindows, !others.isEmpty { removeWindows(connection, windows, others as CFArray) }
        }

        guard let after = spaces(of: windowNumber) else {
            diagnostics = "окно \(windowNumber), проверка недоступна"
            return true
        }
        // Только для лога. Раньше от этого зависело «закреплено / нет», и проверка давала ложный минус
        // (наш Space не виден по этой маске) — окно считалось «пропавшим» и пересоздавалось в цикле.
        diagnostics = "окно \(windowNumber), Space по маске 7: \(after), наш: \(space)"
        return true
    }
}

@MainActor
final class OverlayPanelManager {
    static let shared = OverlayPanelManager()

    private let state = OverlayPanelState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var panelObservers: [NSObjectProtocol] = []
    /// Растёт при каждом present()/hide(). Отложенные действия сверяются с ним
    /// и молча отменяются, если за это время случилось что-то новое.
    private var presentGeneration: UInt64 = 0
    /// Идёт штатное исчезновение (280 мс): сторож в это время не вмешивается.
    private var isHiding = false
    private var unhealthyTicks = 0
    private var lastHealLog = Date.distantPast
    /// Номер окна, уже положенного в закреплённый Space (0 — не закреплено).
    private var pinnedWindowNumber = 0
    private var pinAttempts = 0
    private var lastPinAt = Date.distantPast
    private var lastRebuildAt = Date.distantPast

    /// Выше полноэкранных окон и меню-бара.
    private static let overlayLevel = NSWindow.Level.screenSaver
    /// Зазор между нижней границей чёлки и островком.
    private static let notchGap: CGFloat = 8
    private static let overlayBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]

    private init() {}

    private var isIdle: Bool {
        if case .idle = state.phase { return true }
        return false
    }

    /// В этих фазах отложенное скрытие игнорируется: устаревший scheduleHide
    /// от прошлой записи не должен убирать островок текущей.
    private var isHideBlocked: Bool {
        switch state.phase {
        case .recording, .transcribing: return true
        default: return false
        }
    }

    // MARK: - API

    func showRecording() {
        // Каждая запись — чистое окно: старое могло «протухнуть» в WindowServer
        // (сон, смена Space, полноэкранные приложения, смена мониторов).
        hideTask?.cancel()
        hideTask = nil
        isHiding = false
        state.isShown = false
        destroyPanel()
        state.showRecording()
        present()
    }

    func updateRecording(elapsedSeconds: Int, samples: [Float]) {
        state.updateRecording(elapsedSeconds: elapsedSeconds, samples: samples)
        // Запись идёт, а сторож по какой-то причине остановлен — поднимаем всё заново.
        if case .recording = state.phase, watchdog == nil { present() }
    }

    func showTranscribing() {
        state.showTranscribing()
        present()
    }

    func showProcessing(progress: Double, file: OverlayFileContext) {
        state.showProcessing(progress: progress, file: file)
        present()
    }

    func showWarning(message: String, detail: String?, file: OverlayFileContext?) {
        state.showWarning(message, detail: detail, file: file)
        SoundEffect.playWarning()
        present()
        scheduleHide(after: file == nil ? OverlayTiming.dictationWarningHold : OverlayTiming.fileWarningHold)

        // Тряска чуть позже появления, когда карточка уже видна и ошибка начала проявляться.
        let generation = presentGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, generation == self.presentGeneration, case .warning = self.state.phase else { return }
            self.state.triggerShake()
        }
    }

    func showSuccess(file: OverlayFileContext?) {
        state.showSuccess(file: file)
        present()
    }

    func scheduleHide(after delay: TimeInterval) {
        guard !isHideBlocked else { return }
        hideTask?.cancel()
        let generation = presentGeneration
        let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled,
                  generation == self.presentGeneration,
                  !self.isHideBlocked else { return }
            self.hideOverlay()
        }
    }

    /// Явное скрытие (отмена записи и т.п.) — выполняется всегда.
    func hideOverlay() {
        hideTask?.cancel()
        hideTask = nil
        burstTask?.cancel()
        burstTask = nil
        presentGeneration &+= 1
        let generation = presentGeneration

        guard let panel, panel.isVisible else {
            isHiding = false
            state.isShown = false
            state.reset()
            stopWatchdog()
            return
        }

        isHiding = true
        state.isShown = false   // SwiftUI проигрывает исчезновение
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self, !Task.isCancelled, generation == self.presentGeneration else { return }
            self.panel?.orderOut(nil)
            self.state.reset()
            self.isHiding = false
            self.stopWatchdog()
            self.hideTask = nil
        }
    }

    // MARK: - Показ

    private func present() {
        hideTask?.cancel()
        hideTask = nil
        isHiding = false
        presentGeneration &+= 1
        let generation = presentGeneration

        if panel == nil { createPanel() }

        let wasVisible = panel?.isVisible ?? false
        guard bringToFront() else {
            AppLogger.shared.error("Overlay", "present: нет панели или экрана",
                                   details: "screens: \(NSScreen.screens.count), phase \(state.phase)")
            return
        }
        startWatchdog()
        scheduleReassertBurst()

        guard !state.isShown else { return }
        if wasVisible {
            state.isShown = true
        } else {
            // Даём SwiftUI отрисовать начальное состояние, чтобы появление анимировалось.
            Task { @MainActor [weak self] in
                guard let self, generation == self.presentGeneration else { return }
                self.state.isShown = true
            }
        }
    }

    /// Ставит окно на экран с курсором, на максимальный уровень, поверх всех Space.
    @discardableResult
    private func bringToFront() -> Bool {
        guard let panel, let screen = currentTargetScreen() else { return false }
        let target = preferredFrame(on: screen)
        if panel.frame != target { panel.setFrame(target, display: true) }
        if panel.level != Self.overlayLevel { panel.level = Self.overlayLevel }
        if panel.collectionBehavior != Self.overlayBehavior { panel.collectionBehavior = Self.overlayBehavior }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        pinIfNeeded()
        return true
    }

    /// Один раз на каждое окно (после первого показа, когда у него уже есть реальный номер).
    /// Три переноса на окно с паузой ≥0,35 с: сразу после показа и ещё два раза на тиках сторожа
    /// (повторный перенос безвреден и страхует от гонки при первом показе).
    private func pinIfNeeded() {
        guard OverlayStyle.usesPinnedSpace, !PinnedSpace.isUnavailable, let panel,
              panel.windowNumber > 0, pinAttempts < 3 else { return }
        let now = Date()
        if pinAttempts > 0, now.timeIntervalSince(lastPinAt) < 0.35 { return }
        pinAttempts += 1
        lastPinAt = now
        guard PinnedSpace.pin(windowNumber: panel.windowNumber) else { return }
        pinnedWindowNumber = panel.windowNumber
        if pinAttempts == 3 {
            AppLogger.shared.info("Overlay", "Островок закреплён в отдельном Space", details: PinnedSpace.diagnostics)
        }
    }

    /// Подготовить закреплённый Space заранее, на запуске приложения.
    func warmUp() {
        if OverlayStyle.usesPinnedSpace { PinnedSpace.warmUp() }
    }

    // MARK: - Живучесть

    private var isHealthy: Bool {
        guard let panel else { return false }
        guard panel.alphaValue > 0.99, panel.level == Self.overlayLevel else { return false }
        // Окно в закреплённом Space: isVisible и isOnActiveSpace для него ненадёжны,
        // по ним нельзя судить, что окно «пропало».
        if pinnedWindowNumber == panel.windowNumber { return true }
        return panel.isVisible && panel.isOnActiveSpace
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
        unhealthyTicks = 0
    }

    /// Работает независимо от аудио: пока фаза не idle, окно обязано быть на экране.
    private func watchdogTick() {
        guard !isIdle else { stopWatchdog(); return }
        guard !isHiding else { return }
        pinIfNeeded()
        if isHealthy { unhealthyTicks = 0; return }

        unhealthyTicks += 1
        if Date().timeIntervalSince(lastHealLog) > 5 {
            lastHealLog = Date()
            AppLogger.shared.warn("Overlay", "островок пропал — возвращаю",
                                  details: "visible \(panel?.isVisible ?? false), activeSpace \(panel?.isOnActiveSpace ?? false), " +
                                           "pinned \(pinnedWindowNumber != 0), " +
                                           "level \(panel?.level.rawValue ?? -1), tick \(unhealthyTicks), phase \(state.phase)")
        }
        // Пересоздание окна заново запускает анимацию сферы/волны, поэтому — только если
        // bringToFront несколько тиков подряд не помог, и не чаще раза в 10 с.
        if unhealthyTicks >= 3, Date().timeIntervalSince(lastRebuildAt) > 10 {
            lastRebuildAt = Date()
            rebuildKeepingState()
        } else {
            bringToFront()
        }
    }

    /// Пересоздаёт окно, не трогая состояние записи (секундомер и фаза продолжаются).
    private func rebuildKeepingState() {
        destroyPanel()
        createPanel()
        state.isShown = true
        unhealthyTicks = 0
        bringToFront()
        scheduleReassertBurst()
    }

    /// Смена Space, пробуждение, активация приложения: система в этот момент
    /// перестраивает окна, поэтому возвращаем островок сразу и ещё несколько раз.
    private func reassert() {
        guard panel != nil, !isIdle, !isHiding else { return }
        bringToFront()
        scheduleReassertBurst()
    }

    private func nudgeIfNeeded() {
        guard !isIdle, !isHiding, !isHealthy else { return }
        bringToFront()
    }

    private func scheduleReassertBurst() {
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            for step in [150, 250, 400, 800] as [UInt64] {
                try? await Task.sleep(nanoseconds: step * 1_000_000)
                guard !Task.isCancelled, let self, !self.isIdle, !self.isHiding else { return }
                self.bringToFront()
            }
        }
    }

    // MARK: - Окно

    private func destroyPanel() {
        for o in panelObservers { NotificationCenter.default.removeObserver(o) }
        panelObservers.removeAll()
        pinnedWindowNumber = 0
        pinAttempts = 0
        lastPinAt = .distantPast
        guard let old = panel else { return }
        old.orderOut(nil)
        old.contentView = nil
        old.close()
        panel = nil
    }

    private func createPanel() {
        let size = OverlayMetrics.panelSize
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.canHide = false              // не прячется при Cmd+H и сворачивании приложения
        newPanel.worksWhenModal = true        // виден поверх модальных окон (NSOpenPanel)
        newPanel.isReleasedWhenClosed = false
        newPanel.isMovable = false
        newPanel.animationBehavior = .none
        newPanel.level = Self.overlayLevel
        newPanel.isFloatingPanel = true
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = Self.overlayBehavior
        newPanel.contentMinSize = size
        newPanel.contentMaxSize = size
        newPanel.setContentSize(size)

        let hostingView = NSHostingView(rootView: FloatingWidgetView(state: state)
            .preferredColorScheme(ThemeSettings.shared.current.colorScheme))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        newPanel.contentView = hostingView

        panel = newPanel

        let nudge: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.nudgeIfNeeded() }
        }
        panelObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: newPanel, queue: .main, using: nudge),
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: newPanel, queue: .main, using: nudge)
        ]
        installObservers()
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let reassertBlock: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.reassert() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main, using: reassertBlock))
        let ws = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspaceObservers.append(ws.addObserver(
                forName: name, object: nil, queue: .main, using: reassertBlock))
        }
    }

    /// Экран с курсором; запасной вариант — главный.
    private func currentTargetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return hit
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func preferredFrame(on screen: NSScreen) -> NSRect {
        let size = OverlayMetrics.panelSize
        let notchHeight = screen.safeAreaInsets.top
        let hasCameraHousing = notchHeight > 0
        // С чёлкой: отсчёт от нижней границы выреза, а не от верха экрана.
        // Без чёлки: как раньше, под меню-баром.
        let topEdge = hasCameraHousing
            ? screen.frame.maxY - notchHeight - Self.notchGap
            : screen.visibleFrame.maxY + 4.0

        return NSRect(
            x: screen.frame.midX - (size.width / 2),
            y: topEdge - size.height,
            width: size.width,
            height: size.height
        )
    }
}

/// Все вызовы идут через main.async — строго по порядку (FIFO), из любого потока.
/// Раньше `Task { @MainActor }` не гарантировал порядок, и «hide» от прошлой записи
/// мог обогнать «show» новой.
enum OverlayPanelPresenter {
    static func showRecording() {
        perform { OverlayPanelManager.shared.showRecording() }
    }

    static func updateRecording(elapsedSeconds: Int, samples: [Float]) {
        perform { OverlayPanelManager.shared.updateRecording(elapsedSeconds: elapsedSeconds, samples: samples) }
    }

    static func showTranscribing() {
        perform { OverlayPanelManager.shared.showTranscribing() }
    }

    static func showProcessing(progress: Double, file: OverlayFileContext) {
        perform { OverlayPanelManager.shared.showProcessing(progress: progress, file: file) }
    }

    static func showWarning(message: String, detail: String? = nil, file: OverlayFileContext? = nil) {
        perform { OverlayPanelManager.shared.showWarning(message: message, detail: detail, file: file) }
    }

    static func showSuccess(file: OverlayFileContext? = nil) {
        perform { OverlayPanelManager.shared.showSuccess(file: file) }
    }

    static func scheduleHide(after delay: TimeInterval) {
        perform { OverlayPanelManager.shared.scheduleHide(after: delay) }
    }

    static func hide() {
        perform { OverlayPanelManager.shared.hideOverlay() }
    }

    private static func perform(_ operation: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(operation)
        }
    }
}

struct FloatingWidgetView: View {
    let state: OverlayPanelState

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cardRadius: CGFloat = 22

    private var cardWidth: CGFloat {
        switch state.phase {
        case .recording, .processing: return 132
        case .warning: return 232
        case .success: return state.file == nil ? 84 : 132
        default: return 84
        }
    }

    var body: some View {
        phaseContent
            .frame(width: cardWidth, height: OverlayMetrics.cardHeight)
            .background {
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                            .fill((scheme == .dark ? Color.black : Color.white).opacity(OverlayMetrics.cardTint))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .stroke((scheme == .dark ? Color.white : Color.black).opacity(0.10), lineWidth: 0.8)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: cardWidth)
            .scaleEffect(state.isShown ? 1 : 0.72, anchor: .top)
            .offset(y: state.isShown ? 0 : -10)
            .opacity(state.isShown ? 1 : 0)
            .animation(
                state.isShown
                    ? .spring(response: 0.42, dampingFraction: 0.68)
                    : .easeInOut(duration: 0.3),
                value: state.isShown
            )
            // Ошибка: резкий толчок и пружинное затухание — пользователь видит её действием, а не только цветом.
            .keyframeAnimator(initialValue: 0.0, trigger: state.shakeTick) { content, x in
                content.offset(x: reduceMotion ? 0 : x)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-12.0, duration: 0.07)
                    SpringKeyframe(0.0, duration: 0.9, spring: Spring(response: 0.3, dampingRatio: 0.25))
                }
            }
            .frame(width: OverlayMetrics.panelSize.width,
                   height: OverlayMetrics.panelSize.height,
                   alignment: .top)
    }

    @ViewBuilder
    private var phaseContent: some View {
        if case .idle = state.phase {
            EmptyView()
        } else {
            OrbCardContent(state: state)
        }
    }
}

private enum OrbMode: Equatable { case listening, thinking, done, failed }

private struct OrbCardContent: View {
    let state: OverlayPanelState

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { scheme == .dark ? .white : Color(white: 0.04) }

    private static let labelTransition = AnyTransition.opacity
        .animation(.easeOut(duration: 0.3).delay(0.25))

    private var mode: OrbMode {
        switch state.phase {
        case .recording: return .listening
        case .success: return .done
        case .warning: return .failed
        default: return .thinking
        }
    }

    private var fileProgress: Double {
        if case .processing(let progress) = state.phase { return progress }
        return 0
    }

    /// Громкость только во время записи; в остальных фазах метеринг не нужен.
    private var level: Double {
        guard state.phase == .recording, !state.samples.isEmpty else { return 0 }
        let avg = state.samples.reduce(0, +) / Float(state.samples.count)
        let raw = min(max((avg - 0.15) / 0.85, 0), 1)
        return pow(Double(raw), 0.6)
    }

    var body: some View {
        HStack(spacing: 4) {
            glyph
            trailing
        }
        // Запись → расшифровка: сфера плавно растворяется, на её месте проявляется волна.
        .animation(.easeInOut(duration: 0.25), value: showsSphere)
    }

    /// Сфера — только пока идёт запись с микрофона (или всегда, если волна выключена).
    private var showsSphere: Bool {
        if state.file != nil { return false }
        if case .recording = state.phase { return true }
        return !OverlayStyle.dictationUsesWave
    }

    @ViewBuilder
    private var glyph: some View {
        if state.file != nil {
            RingGlyph(progress: fileProgress, mode: mode, ink: ink, calm: reduceMotion)
                .frame(width: OverlayMetrics.cardHeight, height: OverlayMetrics.cardHeight)
                .transition(.opacity)
        } else if showsSphere {
            SphereOrb(level: level, mode: mode, ink: ink, calm: reduceMotion)
                .frame(width: OverlayMetrics.cardHeight, height: OverlayMetrics.cardHeight)
                .transition(.opacity)
        } else {
            WaveGlyph(samples: state.samples, mode: mode, ink: ink, calm: reduceMotion)
                .frame(width: 64, height: OverlayMetrics.cardHeight)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state.phase {
        case .recording:
            Text(verbatim: Self.format(state.elapsedSeconds))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(0.85))
                .frame(width: 46, alignment: .leading)
                .transition(.opacity)
        case .processing(let progress):
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.85))
                    .contentTransition(.numericText(value: progress))
                if let file = state.file, file.total > 1 {
                    Text("\(file.index) из \(file.total)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(ink.opacity(0.55))
                }
            }
            .frame(width: 56, alignment: .leading)
            .transition(.opacity)
        case .success:
            if let file = state.file {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Готово")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.85))
                    if file.total > 1 {
                        Text("\(file.total) из \(file.total)")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(ink.opacity(0.55))
                    }
                }
                .frame(width: 56, alignment: .leading)
                .transition(Self.labelTransition)
            }
        case .warning(let message):
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.9))
                    .lineLimit(state.detail == nil ? 2 : 1)
                    .multilineTextAlignment(.leading)
                if let detail = state.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(ink.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 146, alignment: .leading)
            .padding(.trailing, 10)
            .transition(Self.labelTransition)
        default:
            EmptyView()
        }
    }

    private static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Sphere

private final class OrbDriver {
    var level = 0.0
    var think = 0.0
    var collapse = 0.0
    var doneT = 0.0
    var failT = 0.0
    var flat = 0.0       // 0...1 — сплющивание в линию
    var yaw = 0.0
    private var last = 0.0
    private var doneStart: Double?
    private var failStart: Double?

    func step(target: Double, mode: OrbMode, now: Double, calm: Bool) {
        let dt = min(max(now - last, 0), 0.1)
        last = now
        level += (target - level) * (1 - exp(-(target > level ? 22.0 : 5.0) * dt))
        think += ((mode == .thinking ? 1.0 : 0.0) - think) * (1 - exp(-4 * dt))
        if !calm { yaw += dt * (0.42 + 0.9 * think) * (mode == .failed ? 0.3 : 1) }

        if mode == .done {
            if doneStart == nil { doneStart = now }
            doneT = now - (doneStart ?? now)
            collapse = min(1, doneT / 0.22)
        } else {
            doneStart = nil
            doneT = 0
            collapse += (0 - collapse) * (1 - exp(-8 * dt))
        }

        if mode == .failed {
            if failStart == nil { failStart = now }
            failT = now - (failStart ?? now)
            let u = min(max((failT - 0.15) / 0.5, 0), 1)
            flat = 1 - pow(1 - u, 3)
        } else {
            failStart = nil
            failT = 0
            flat += (0 - flat) * (1 - exp(-8 * dt))
        }
    }
}

private struct OrbPoint {
    let x, y, z, delay: Double
}

private enum OrbGeometry {
    /// Сфера Фибоначчи: равномерное распределение без «полюсов».
    static let points: [OrbPoint] = {
        let n = 560
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let r = (1 - y * y).squareRoot()
            let a = golden * Double(i)
            let h = Double((i &* 2654435761) % 1000) / 1000
            return OrbPoint(x: cos(a) * r, y: y, z: sin(a) * r, delay: h)
        }
    }()
}

private struct SphereOrb: View {
    let level: Double
    let mode: OrbMode
    let ink: Color
    let calm: Bool

    @State private var born = Date()
    @State private var driver = OrbDriver()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let t = max(timeline.date.timeIntervalSince(born), 0)
                driver.step(target: level, mode: mode, now: t, calm: calm)
                Self.draw(&context, size: size, t: t, d: driver, ink: ink, calm: calm)
            }
        }
        .onAppear { born = Date() }
    }

    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

    private static func ring(_ ctx: inout GraphicsContext, c: CGPoint, r: Double,
                             alpha: Double, wob: Double, t: Double, k: Int, ink: Color) {
        if alpha < 0.01 { return }
        var path = Path()
        let seg = 72
        for s in 0...seg {
            let a = Double(s) / Double(seg) * 2 * Double.pi
            let w = 1 + 0.07 * wob * sin(a * 3 + t * 2.2 + Double(k) * 1.7)
                      + 0.04 * wob * sin(a * 5 - t * 1.6)
            let pt = CGPoint(x: Double(c.x) + cos(a) * r * w, y: Double(c.y) + sin(a) * r * w)
            if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(ink.opacity(alpha)), lineWidth: 1)
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             d: OrbDriver, ink: Color, calm: Bool) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = Double(min(size.width, size.height)) * 0.27
        let form = min(max(t - 0.12, 0) / 1.0, 1)   // 0.12 с только точка, затем «взрыв» в сферу
        let tt = calm ? 0 : t
        let think = d.think, collapse = d.collapse

        // В обработке громкости нет — сфера «дышит» синтетическим пульсом.
        let lvl = d.level * (1 - think) + think * (0.30 + 0.10 * sin(tt * 2.4))
        let pitch = 0.38
        let cp = cos(pitch), sp = sin(pitch)
        let amp = 0.05 + 0.32 * lvl
        let twist = think * 1.5 * sin(tt * 1.1)      // скручивание в спираль
        let sweep = sin(tt * 1.7)                    // положение полосы-сканера
        let shrink = 1 - pow(collapse, 2)
        
        let flat = d.flat
        let shake = calm ? 0 : sin(d.failT * 38) * 3.5 * exp(-d.failT * 5)

        var layers = [Path](repeating: Path(), count: 4)
        if collapse < 0.98 {
            for p in OrbGeometry.points {
                let local = min(max((form - p.delay * 0.4) / 0.6, 0), 1)
                if local <= 0 { continue }
                let e = easeOutBack(local)

                let n = sin(p.x * 3.1 + tt * 1.3) * cos(p.y * 2.7 - tt * 1.1)
                      + 0.6 * sin(p.z * 4.0 + tt * 0.9 + p.x * 2)
                let band = think > 0.01 ? think * exp(-pow((p.y - sweep) / 0.22, 2)) : 0
                let rad = e * (1 + amp * n + 0.12 * band) * shrink

                let ang = d.yaw + lvl * 0.4 + twist * p.y
                let ca = cos(ang), sa = sin(ang)
                let x = p.x * rad, y = p.y * rad, z = p.z * rad
                let x1 = x * ca + z * sa
                let z1 = -x * sa + z * ca
                let y2 = y * cp - z1 * sp
                let z2 = y * sp + z1 * cp

                let depth = min(max((z2 / max(rad, 0.001) + 1) / 2, 0), 1)
                let persp = 1 + 0.18 * z2
                let yf = y2 * (1 - 0.95 * flat) + flat * 0.05 * sin(x1 * 6 + tt * 2.6)
                let xf = x1 * (1 + 0.4 * flat)
                let px = Double(c.x) + xf * R * persp + shake
                let py = Double(c.y) + yf * R * persp
                let dia = (1.1 + 1.3 * depth) * (0.4 + 0.6 * local) * (1 + 0.9 * band) * (1 - 0.5 * collapse)
                let bucket = min(3, Int(depth * 4) + (band > 0.4 ? 1 : 0))
                layers[bucket].addEllipse(in: CGRect(x: px - dia / 2, y: py - dia / 2, width: dia, height: dia))
            }
        }
        let alphas = [0.22, 0.40, 0.65, 0.95]
        let amber = Color(hex: "#F59E0B")
        for i in 0..<4 {
            ctx.fill(layers[i], with: .color(ink.opacity(alphas[i] * (1 - flat))))
            if flat > 0.01 { ctx.fill(layers[i], with: .color(amber.opacity(alphas[i] * flat))) }
        }

        // Точка-логотип: в начале растворяется в сферу, в конце — собирается обратно.
        let checkP = easeOut(clamp01((d.doneT - 0.4) / 0.35))
        let dotA = max(max(0, 1 - form * 2.2), pow(collapse, 2) * (1 - checkP))
        if dotA > 0.01 {
            let r = 3.6
            ctx.fill(Path(ellipseIn: CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: r * 2, height: r * 2)),
                     with: .color(ink.opacity(dotA)))
        }

        // Кольца: наружу на голос, внутрь при обработке.
        if !calm && form > 0.6 && collapse < 0.05 {
            let out = min(1, lvl * 1.5) * (1 - think)
            for k in 0..<3 {
                if out > 0.01 {
                    let ph = (t * (0.3 + 0.45 * lvl) + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    ring(&ctx, c: c, r: R * (1.12 + 0.5 * ph), alpha: pow(1 - ph, 1.6) * out * 0.55,
                         wob: lvl, t: t, k: k, ink: ink)
                }
                if think > 0.01 {
                    let ph = (t * 0.55 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    ring(&ctx, c: c, r: R * (1.62 - 0.5 * ph), alpha: sin(Double.pi * ph) * 0.45 * think,
                         wob: 0.3, t: t, k: k, ink: ink)
                }
            }
        }

        // Успех: вспышка-кольцо и галочка, которая «рисуется».
        if d.doneT > 0.38 {
            let u = clamp01((d.doneT - 0.38) / 0.55)
            if u < 1 {
                ring(&ctx, c: c, r: R * (0.25 + 1.2 * u), alpha: 0.5 * (1 - u), wob: 0, t: t, k: 0, ink: ink)
            }
        }
        if checkP > 0 {
            let s = R * 0.62
            var check = Path()
            check.move(to: CGPoint(x: Double(c.x) - 0.55 * s, y: Double(c.y) + 0.05 * s))
            check.addLine(to: CGPoint(x: Double(c.x) - 0.15 * s, y: Double(c.y) + 0.45 * s))
            check.addLine(to: CGPoint(x: Double(c.x) + 0.60 * s, y: Double(c.y) - 0.40 * s))
            ctx.stroke(check.trimmedPath(from: 0, to: checkP), with: .color(ink),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Общие помощники для глифов

private func ovClamp(_ x: Double) -> Double { min(max(x, 0), 1) }
private func ovEaseOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

private let ovAmber = Color(hex: "#F59E0B")

/// Точка с плавным переходом цвета «чернила → янтарь» (mix 0...1).
private func ovDot(_ ctx: inout GraphicsContext, x: Double, y: Double, r: Double,
                   alpha: Double, mix: Double, ink: Color) {
    guard alpha > 0.01, r > 0 else { return }
    let path = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    if mix < 1 { ctx.fill(path, with: .color(ink.opacity(alpha * (1 - mix)))) }
    if mix > 0 { ctx.fill(path, with: .color(ovAmber.opacity(alpha * mix))) }
}

// MARK: - Кольцо (обработка файла)

/// Прогресс-кольцо из точек. Успех: кольцо схлопывается в точку-логотип. Ошибка: часть точек
/// осыпается, остальные гаснут в янтарный (плюс пружинная тряска карточки снаружи).
private final class RingDriver {
    var progress = 0.0        // сглаженный: прогресс приходит кусками по чанкам
    var doneU = 0.0           // 0...1 — схлопывание
    var failU = 0.0           // 0...1 — осыпание
    var failing = false
    private var last = 0.0
    private var doneStart: Double?
    private var failStart: Double?

    func step(target: Double, mode: OrbMode, now: Double) {
        let dt = min(max(now - last, 0), 0.1)
        last = now
        failing = mode == .failed

        switch mode {
        case .failed: break
        case .done: progress += (1 - progress) * (1 - exp(-16 * dt))
        default: progress += (target - progress) * (1 - exp(-6 * dt))
        }

        if mode == .done, progress > 0.985 {
            if doneStart == nil { doneStart = now }
            doneU = min(1, (now - (doneStart ?? now)) / 0.9)
        } else if mode != .done {
            doneStart = nil
            doneU = 0
        }

        if mode == .failed {
            if failStart == nil { failStart = now }
            failU = min(1, (now - (failStart ?? now)) / 1.0)
        } else {
            failStart = nil
            failU = 0
        }
    }
}

private struct RingGlyph: View {
    let progress: Double
    let mode: OrbMode
    let ink: Color
    let calm: Bool

    @State private var born = Date()
    @State private var driver = RingDriver()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let t = max(timeline.date.timeIntervalSince(born), 0)
                driver.step(target: progress, mode: mode, now: t)
                Self.draw(&context, size: size, t: t, d: driver, ink: ink, calm: calm)
            }
        }
        .onAppear { born = Date() }
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             d: RingDriver, ink: Color, calm: Bool) {
        let n = 36
        let sc = Double(min(size.width, size.height)) / 80
        let radius = 22 * sc
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let head = d.failing ? Double(n) : d.progress * Double(n)
        let u = max(d.doneU, d.failU)
        let mix = d.failing ? ovEaseOut(ovClamp(d.failU * 1.5)) : 0

        for i in 0..<n {
            let fi = Double(i)
            let angle = -Double.pi / 2 + fi / Double(n) * 2 * Double.pi
            var rr = radius * (1 + (calm ? 0 : 0.025 * sin(t * 3 + fi * 0.6)))
            var dotSize = 1.5 * sc
            var alpha = 0.22
            var dy = 0.0

            if fi < head { dotSize = 2.3 * sc; alpha = 1 }
            if fi < head, fi > head - 2.5, !d.failing, d.doneU == 0 { dotSize = 3.1 * sc }

            if d.doneU > 0 {
                let l = ovClamp((u - fi / Double(n) * 0.35) / 0.65)
                rr = radius * (1 - ovEaseOut(l))
                dotSize = 2.3 * sc * (1 - 0.35 * l)
                alpha = 1 - ovClamp((l - 0.75) / 0.25)
            } else if d.failing {
                let falls = i >= 8 && i <= 15
                dotSize = 2.3 * sc
                alpha = falls ? 1 : 0.55
                if falls, d.failU > 0 {
                    let l = ovClamp((d.failU - 0.15 - Double(i - 8) * 0.03) / 0.6)
                    dy = l * l * (26 + Double(i % 3) * 8) * sc
                    alpha = 1 - l
                }
            }
            ovDot(&ctx, x: cx + cos(angle) * rr, y: cy + sin(angle) * rr + dy,
                  r: dotSize, alpha: alpha, mix: mix, ink: ink)
        }

        // Точка-логотип: кольцо схлопнулось — она вырастает и один раз пульсирует.
        if d.doneU > 0.5 {
            let k = ovEaseOut(ovClamp((u - 0.55) / 0.4))
            let pulse = u > 0.8 ? 0.25 * max(0, sin((u - 0.8) * 16)) : 0
            ovDot(&ctx, x: cx, y: cy, r: 5.5 * sc * k * (1 + pulse), alpha: 1, mix: 0, ink: ink)
        }
    }
}

// MARK: - Волна (диктовка с микрофона)

/// Ряд точек-волна. Запись: высота точек следует за голосом. Обработка: бегущий блик.
/// Успех: волна выравнивается и сходится в точку-логотип. Ошибка: линия разрывается и провисает.
private final class WaveDriver {
    static let count = 19
    var amps = [Double](repeating: 0, count: 19)
    var think = 0.0
    var doneU = 0.0
    var failU = 0.0
    private var last = 0.0
    private var doneStart: Double?
    private var failStart: Double?

    func step(samples: [Float], mode: OrbMode, now: Double) {
        let dt = min(max(now - last, 0), 0.1)
        last = now
        think += ((mode == .listening ? 0.0 : 1.0) - think) * (1 - exp(-5 * dt))

        for i in 0..<Self.count {
            var target = 0.0
            if mode == .listening, samples.count > 1 {
                let pos = Double(i) / Double(Self.count - 1) * Double(samples.count - 1)
                let lo = Int(pos.rounded(.down))
                let hi = min(lo + 1, samples.count - 1)
                let f = pos - Double(lo)
                let s = Double(samples[lo]) * (1 - f) + Double(samples[hi]) * f
                target = min(max((s - 0.15) / 0.85, 0), 1)
            }
            amps[i] += (target - amps[i]) * (1 - exp(-(target > amps[i] ? 24.0 : 7.0) * dt))
        }

        if mode == .done {
            if doneStart == nil { doneStart = now }
            doneU = min(1, (now - (doneStart ?? now)) / 0.85)
        } else {
            doneStart = nil
            doneU = 0
        }

        if mode == .failed {
            if failStart == nil { failStart = now }
            failU = min(1, (now - (failStart ?? now)) / 1.0)
        } else {
            failStart = nil
            failU = 0
        }
    }
}

private struct WaveGlyph: View {
    let samples: [Float]
    let mode: OrbMode
    let ink: Color
    let calm: Bool

    @State private var born = Date()
    @State private var driver = WaveDriver()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let t = max(timeline.date.timeIntervalSince(born), 0)
                driver.step(samples: samples, mode: mode, now: t)
                Self.draw(&context, size: size, t: t, d: driver, ink: ink, calm: calm)
            }
        }
        .onAppear { born = Date() }
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             d: WaveDriver, ink: Color, calm: Bool) {
        let n = WaveDriver.count
        let mid = n / 2
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let span = Double(size.width) - 14
        let step = span / Double(n - 1)
        let tt = calm ? 0 : t
        let think = d.think
        let u = max(d.doneU, d.failU)
        let flat = u > 0 ? 1 - ovEaseOut(ovClamp(u / 0.35)) : 1
        let mix = d.failU > 0 ? ovEaseOut(ovClamp(d.failU * 1.5)) : 0
        let sweep = (tt * 14).truncatingRemainder(dividingBy: Double(n + 8)) - 4

        for i in 0..<n {
            let fi = Double(i)
            let env = 0.45 + 0.55 * sin(Double.pi * (fi + 0.5) / Double(n))
            let live = 1.5 + 11.0 * d.amps[i]
            let synth = 5.5 * (0.5 + 0.5 * sin(tt * 2.2 + fi * 0.5))
            let amp = (live * (1 - think) + synth * think) * env * flat

            var x = cx - span / 2 + step * fi
            var y = cy + amp * sin(tt * 6.5 + fi * 0.8)
            let glint = exp(-pow((fi - sweep) / 2.6, 2))
            var alpha = (1 - 0.55 * think) + 0.55 * think * glint
            var r = 1.3 * (1 + 0.35 * think * glint)

            if d.doneU > 0 {
                let s = ovEaseOut(ovClamp((d.doneU - 0.3) / 0.6))
                x += (cx - x) * s
                if i == mid {
                    alpha = 1
                    r = 1.3 + 2.3 * s
                    if d.doneU > 0.8 { r *= 1 + 0.25 * max(0, sin((d.doneU - 0.8) * 16)) }
                } else {
                    alpha *= 1 - ovClamp((s - 0.8) / 0.2)
                }
            } else if d.failU > 0 {
                let g = ovEaseOut(ovClamp((d.failU - 0.35) / 0.4))
                x += (i < mid ? -1.0 : (i > mid ? 1.0 : 0.0)) * 2.6 * g
                y += 2.4 * g * sin(fi / Double(n - 1) * Double.pi)
                if i == mid { alpha *= 1 - g }
            }
            ovDot(&ctx, x: x, y: y, r: r, alpha: alpha, mix: mix, ink: ink)
        }
    }
}
