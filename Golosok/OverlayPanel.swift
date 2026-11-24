import SwiftUI
import AppKit
import Foundation

private enum OverlayMetrics {
    /// Panel and pill share the same bounds — no transparent margins,
    /// so nothing stray can cast a shadow.
    static let cardHeight: CGFloat = 72
    static let cardTint: Double = 0.45
    static let panelSize = NSSize(width: 240, height: cardHeight + 2)
    static let pillHeight: CGFloat = 40
    static let horizontalPadding: CGFloat = 14
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
    /// Управляет появлением/исчезновением в SwiftUI. Окно само всегда alpha 1.
    var isShown = false

    func showRecording() {
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
        phase = .transcribing
    }

    func showProcessing(progress: Double) {
        let clamped = min(max(progress, 0), 1)
        if case .processing(let current) = phase, abs(current - clamped) < 0.001 { return }
        phase = .processing(progress: clamped)
    }

    func showWarning(_ message: String) {
        phase = .warning(message)
    }

    func showSuccess() {
        phase = .success
    }

    func reset() {
        phase = .idle
        elapsedSeconds = 0
        samples = Array(repeating: 0.15, count: 18)
    }
}

@MainActor
final class OverlayPanelManager {
    static let shared = OverlayPanelManager()

    private let state = OverlayPanelState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// Растёт при каждом present()/hide(). Отложенные действия сверяются с ним
    /// и молча отменяются, если за это время случилось что-то новое.
    private var presentGeneration: UInt64 = 0

    private init() {}

    func showRecording() {
        state.showRecording()
        present()
    }

    func updateRecording(elapsedSeconds: Int, samples: [Float]) {
        state.updateRecording(elapsedSeconds: elapsedSeconds, samples: samples)
        // Самолечение: идёт запись, а панели на экране нет.
        if state.phase == .recording, panel?.isVisible != true {
            AppLogger.shared.warn("Overlay", "панель пропала во время записи — возвращаю",
                                  details: "visible \(panel?.isVisible ?? false), shown \(state.isShown)")
            present()
        }
    }

    func showTranscribing() {
        state.showTranscribing()
        present()
    }

    func showProcessing(progress: Double) {
        state.showProcessing(progress: progress)
        present()
    }

    func showWarning(message: String) {
        state.showWarning(message)
        SoundEffect.playWarning()
        present()
        scheduleHide(after: 3.5)
    }

    func showSuccess() {
        state.showSuccess()
        present()
    }

    func scheduleHide(after delay: TimeInterval) {
        hideTask?.cancel()
        let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.hideOverlay()
        }
    }

    func hideOverlay() {
        hideTask?.cancel()
        hideTask = nil
        presentGeneration &+= 1
        let generation = presentGeneration

        guard let panel, panel.isVisible else {
            state.isShown = false
            state.reset()
            return
        }

        state.isShown = false   // SwiftUI проигрывает исчезновение
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self, !Task.isCancelled, generation == self.presentGeneration else { return }
            self.panel?.orderOut(nil)
            self.state.reset()
            self.hideTask = nil
        }
    }

    private func present() {
        hideTask?.cancel()
        hideTask = nil
        presentGeneration &+= 1
        let generation = presentGeneration

        if panel == nil { createPanel() }

        guard let panel, let screen = currentTargetScreen() else {
            AppLogger.shared.error("Overlay", "present: нет панели или экрана",
                                   details: "screens: \(NSScreen.screens.count), phase \(state.phase)")
            return
        }

        let wasVisible = panel.isVisible
        let targetFrame = preferredFrame(on: screen)
        if panel.frame != targetFrame { panel.setFrame(targetFrame, display: true) }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

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

    /// Вернуть панель на экран после сна, смены Space или конфигурации экранов.
    private func reassert() {
        guard let panel, state.phase != .idle, state.isShown,
              let screen = currentTargetScreen() else { return }
        panel.setFrame(preferredFrame(on: screen), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
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
        newPanel.isReleasedWhenClosed = false
        newPanel.level = .statusBar
        newPanel.isFloatingPanel = true
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
        observers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main, using: reassertBlock))
        observers.append(ws.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main, using: reassertBlock))
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
        let hasCameraHousing = screen.safeAreaInsets.top > 0
        let topInset = hasCameraHousing ? 6.0 : 4.0
        let topEdge = hasCameraHousing
            ? screen.frame.maxY - topInset
            : screen.visibleFrame.maxY + topInset

        return NSRect(
            x: screen.frame.midX - (size.width / 2),
            y: topEdge - size.height,
            width: size.width,
            height: size.height
        )
    }
}

enum OverlayPanelPresenter {
    static func showRecording() {
        perform { OverlayPanelManager.shared.showRecording() }
    }

    static func updateRecording(elapsedSeconds: Int, samples: [Float]) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                OverlayPanelManager.shared.updateRecording(elapsedSeconds: elapsedSeconds, samples: samples)
            }
        } else {
            Task { @MainActor in
                OverlayPanelManager.shared.updateRecording(elapsedSeconds: elapsedSeconds, samples: samples)
            }
        }
    }

    static func showTranscribing() {
        perform { OverlayPanelManager.shared.showTranscribing() }
    }

    static func showProcessing(progress: Double) {
        perform { OverlayPanelManager.shared.showProcessing(progress: progress) }
    }

    static func showWarning(message: String) {
        perform { OverlayPanelManager.shared.showWarning(message: message) }
    }

    static func showSuccess() {
        perform { OverlayPanelManager.shared.showSuccess() }
    }

    static func scheduleHide(after delay: TimeInterval) {
        perform { OverlayPanelManager.shared.scheduleHide(after: delay) }
    }

    static func hide() {
        perform { OverlayPanelManager.shared.hideOverlay() }
    }

    private static func perform(_ operation: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(operation)
        } else {
            Task { @MainActor in operation() }
        }
    }
}

struct FloatingWidgetView: View {
    let state: OverlayPanelState

    @Environment(\.colorScheme) private var scheme

    private static let cardRadius: CGFloat = 28

    private var isCard: Bool {
        if case .warning = state.phase { return false }
        return true
    }

    private var cardWidth: CGFloat {
        switch state.phase {
        case .recording, .processing: return 168
        default: return 104
        }
    }

    var body: some View {
        phaseContent
            .padding(.horizontal, isCard ? 0 : OverlayMetrics.horizontalPadding)
            .frame(width: isCard ? cardWidth : 240,
                   height: isCard ? OverlayMetrics.cardHeight : OverlayMetrics.pillHeight)
            .background { islandBackground }
            .overlay { islandBorder }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: cardWidth)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isCard)
            .scaleEffect(state.isShown ? 1 : 0.72, anchor: .top)
            .offset(y: state.isShown ? 0 : -10)
            .opacity(state.isShown ? 1 : 0)
            .animation(
                state.isShown
                    ? .spring(response: 0.42, dampingFraction: 0.68)
                    : .easeIn(duration: 0.22),
                value: state.isShown
            )
            .frame(width: OverlayMetrics.panelSize.width,
                   height: OverlayMetrics.panelSize.height,
                   alignment: .top)
    }

    @ViewBuilder
    private var islandBackground: some View {
        if isCard {
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                        .fill((scheme == .dark ? Color.black : Color.white).opacity(OverlayMetrics.cardTint))
                )
        } else {
            PillGlassBackground()
        }
    }

    @ViewBuilder
    private var islandBorder: some View {
        if isCard {
            RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                .stroke((scheme == .dark ? Color.white : Color.black).opacity(0.10), lineWidth: 0.8)
        } else {
            PillBorder(phase: state.phase)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .warning(let message):
            WarningOverlayContent(message: message)
                .transition(.opacity)
        default:
            OrbCardContent(state: state)
        }
    }
}

private struct PillGlassBackground: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.08))
            .modifier(PillGlassModifier())
    }
}

private struct PillGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

private struct PillBorder: View {
    let phase: OverlayPhase

    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            Capsule()
                .stroke(.white.opacity(0.42), lineWidth: 0.8)
        } else {
            switch phase {
            case .warning:
                Capsule().stroke(Color(hex: "#F59E0B").opacity(0.72), lineWidth: 1.1)
            case .success:
                Capsule().stroke(Color(hex: "#34D399").opacity(0.82), lineWidth: 1.1)
            default:
                Capsule().stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.78), .white.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
        }
    }
}
private enum OrbMode: Equatable { case listening, thinking, done }

private struct OrbCardContent: View {
    let state: OverlayPanelState

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { scheme == .dark ? .white : Color(white: 0.04) }

    private var mode: OrbMode {
        switch state.phase {
        case .recording: return .listening
        case .success: return .done
        default: return .thinking
        }
    }

    /// Средняя громкость 0...1 (нижний порог метеринга — 0.15).
    private var level: Double {
        guard !state.samples.isEmpty else { return 0 }
        let avg = state.samples.reduce(0, +) / Float(state.samples.count)
        return Double(min(max((avg - 0.15) / 0.85, 0), 1))
    }

    var body: some View {
        HStack(spacing: 4) {
            SphereOrb(level: level, mode: mode, ink: ink, calm: reduceMotion)
                .frame(width: OverlayMetrics.cardHeight, height: OverlayMetrics.cardHeight)
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state.phase {
        case .recording:
            Text(verbatim: Self.format(state.elapsedSeconds))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(0.85))
                .frame(width: 56, alignment: .leading)
                .transition(.opacity)
        case .processing(let progress):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink.opacity(0.85))
                .contentTransition(.numericText(value: progress))
                .frame(width: 56, alignment: .leading)
                .transition(.opacity)
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
    var level = 0.0      // сглаженная громкость
    var think = 0.0      // 0...1 — режим обработки
    var collapse = 0.0   // 0...1 — схлопывание в точку
    var doneT = 0.0      // секунд с начала успеха
    var yaw = 0.0        // накопленный угол вращения (без рывков при смене скорости)
    private var last = 0.0
    private var doneStart: Double?

    func step(target: Double, mode: OrbMode, now: Double, calm: Bool) {
        let dt = min(max(now - last, 0), 0.1)
        last = now
        // Быстрая атака, медленное затухание.
        level += (target - level) * (1 - exp(-(target > level ? 14.0 : 5.0) * dt))
        think += ((mode == .thinking ? 1.0 : 0.0) - think) * (1 - exp(-4 * dt))
        if !calm { yaw += dt * (0.42 + 0.9 * think) }
        if mode == .done {
            if doneStart == nil { doneStart = now }
            doneT = now - (doneStart ?? now)
            collapse = min(1, doneT / 0.4)
        } else {
            doneStart = nil
            doneT = 0
            collapse += (0 - collapse) * (1 - exp(-8 * dt))
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
                let px = Double(c.x) + x1 * R * persp
                let py = Double(c.y) + y2 * R * persp
                let dia = (1.1 + 1.3 * depth) * (0.4 + 0.6 * local) * (1 + 0.9 * band) * (1 - 0.5 * collapse)
                let bucket = min(3, Int(depth * 4) + (band > 0.4 ? 1 : 0))
                layers[bucket].addEllipse(in: CGRect(x: px - dia / 2, y: py - dia / 2, width: dia, height: dia))
            }
        }
        let alphas = [0.22, 0.40, 0.65, 0.95]
        for i in 0..<4 { ctx.fill(layers[i], with: .color(ink.opacity(alphas[i]))) }

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

private struct ProcessingOverlayContent: View {
    let progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if let progress {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: progress))
                    .frame(height: 20)

                Spacer(minLength: 12)

                LiquidWaveform(isAnimated: !reduceMotion)
                    .frame(width: 92, height: 18)
            } else {
                Spacer(minLength: 0)
                LiquidWaveform(isAnimated: !reduceMotion)
                    .frame(width: 128, height: 18)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Three flowing sine ribbons in the Siri palette — blue, violet, mint —
/// drifting and breathing inside the pill. The amplitude envelope fades to
/// zero at both ends, so the wave dissolves softly instead of being clipped.
private struct LiquidWaveform: View {
    let isAnimated: Bool

    private let waves: [(hue: Double, phaseOffset: Double)] = [
        (0.58, 0.0),
        (0.76, 2.1),
        (0.47, 4.2)
    ]

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                drawWaves(
                    context: &context,
                    size: size,
                    time: isAnimated ? timeline.date.timeIntervalSince1970 : 0
                )
            }
        }
    }

    private func drawWaves(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }
        let midY = size.height / 2
        let segments = max(12, Int(size.width / 3))
        let stepX = size.width / CGFloat(segments)

        for (index, wave) in waves.enumerated() {
            let speed = 2.1 + (Double(index) * 0.55)
            let phase = (time * speed) + wave.phaseOffset
            let amplitude = Double(midY) * (0.6 + (0.32 * sin((time * 1.1) + (Double(index) * 1.7))))
            let frequency = 2.3 + (Double(index) * 0.5)

            var previous = CGPoint(x: 0, y: midY)
            for segment in 1...segments {
                let x = CGFloat(segment) * stepX
                let progress = Double(x / size.width)
                let envelope = sin(.pi * progress)
                let y = midY + CGFloat(
                    amplitude * envelope * sin((progress * frequency * 2 * .pi) - phase)
                )

                var path = Path()
                path.move(to: previous)
                path.addLine(to: CGPoint(x: x, y: y))
                context.stroke(
                    path,
                    with: .color(Color(
                        hue: wave.hue + (0.05 * sin(progress * .pi)),
                        saturation: 0.72,
                        brightness: 0.98
                    ).opacity(0.3 + (0.6 * envelope))),
                    style: StrokeStyle(lineWidth: 2.1, lineCap: .round)
                )
                previous = CGPoint(x: x, y: y)
            }
        }
    }
}

private struct WarningOverlayContent: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: "#F59E0B"))

            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private struct SuccessCheckView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#34D399").opacity(0.48), lineWidth: 2)
                .frame(width: 24, height: 24)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
        }
        .scaleEffect(appeared ? 1 : 0.2)
        .offset(y: appeared ? 0 : -8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.38, dampingFraction: 0.54)) {
                appeared = true
            }
        }
    }
}
