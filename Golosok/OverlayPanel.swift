import SwiftUI
import AppKit
import Foundation

private enum OverlayMetrics {
    /// Panel and pill share the same bounds — no transparent margins,
    /// so nothing stray can cast a shadow.
    static let panelSize = NSSize(width: 240, height: 40)
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
    private var targetScreen: NSScreen?
    private var hideTask: Task<Void, Never>?
    private var screenChangeObserver: NSObjectProtocol?
    /// Bumped on every present(). A fade-out completion that sees a newer
    /// generation lost the race to a new present() and must not orderOut/reset.
    private var presentGeneration: UInt64 = 0

    private init() {}

    func showRecording() {
        state.showRecording()
        present()
    }

    func updateRecording(elapsedSeconds: Int, samples: [Float]) {
        state.updateRecording(elapsedSeconds: elapsedSeconds, samples: samples)
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

        guard let panel, panel.isVisible else {
            AppLogger.shared.info("Overlay", "hide: панель не на экране, фаза сброшена", details: "phase \(state.phase)")
            state.reset()
            return
        }

        let generation = presentGeneration
        let currentFrame = panel.frame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(NSPoint(x: currentFrame.minX, y: currentFrame.minY + 6))
        }) { [self, state] in
            guard generation == MainActor.assumeIsolated({ self.presentGeneration }) else {
                // A present() landed while the fade-out was in flight: cancel the
                // fade visually instead of ordering the panel out.
                AppLogger.shared.info("Overlay", "hide: race с present(), отмена скрытия", details: "gen \(generation) -> \(self.presentGeneration)")
                panel.alphaValue = 1
                return
            }
            panel.orderOut(nil)
            // NSAnimationContext completion fires on the main thread.
            MainActor.assumeIsolated { state.reset() }
        }
    }

    private func present() {
        hideTask?.cancel()
        hideTask = nil
        presentGeneration &+= 1

        if panel == nil {
            createPanel()
        }

        guard let screen = currentTargetScreen() else {
            AppLogger.shared.error("Overlay", "present: нет целевого экрана", details: "screens: \(NSScreen.screens.count), phase \(state.phase)")
            return
        }
        guard let panel else { return }

        let targetFrame = preferredFrame(on: screen)

        // Already on screen: update geometry silently. Re-running the entrance
        // fade here makes the pill blink on every progress tick (0% → 25% → …).
        if panel.isVisible {
            AppLogger.shared.info("Overlay", "present: панель уже видима", details: "alpha \(panel.alphaValue), phase \(state.phase), frame \(panel.frame)")
            panel.setFrame(targetFrame, display: true)
            panel.alphaValue = 1
            return
        }

        AppLogger.shared.info("Overlay", "present: показ островка", details: "screen \(screen.localizedName ?? "?"), frame \(targetFrame)")
        panel.alphaValue = 0
        panel.setFrame(targetFrame, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
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
        // No pinned appearance: the pill must follow the system theme
        // automatically when the user switches dark/light mode.
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.level = .statusBar
        newPanel.isFloatingPanel = true
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.contentMinSize = size
        newPanel.contentMaxSize = size
        newPanel.setContentSize(size)

        let hostingView = NSHostingView(rootView: FloatingWidgetView(state: state))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        newPanel.contentView = hostingView

        targetScreen = NSScreen.main ?? NSScreen.screens.first
        observeScreenChanges()
        panel = newPanel
    }

    private func observeScreenChanges() {
        guard screenChangeObserver == nil else { return }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if let screen = self.currentTargetScreen() {
                    panel.setFrame(self.preferredFrame(on: screen), display: true)
                }
            }
        }
    }

    private func currentTargetScreen() -> NSScreen? {
        if let targetScreen, NSScreen.screens.contains(targetScreen) {
            return targetScreen
        }
        targetScreen = NSScreen.main ?? NSScreen.screens.first
        return targetScreen
    }

    private func preferredFrame(on screen: NSScreen) -> NSRect {
        let size = OverlayMetrics.panelSize
        let hasCameraHousing = screen.safeAreaInsets.top > 0
        // With a notch the pill hangs from the camera housing: its top edge sits
        // inside the notch band, so a 300 pt pill visibly peeks out on both sides.
        // Without a notch it tucks 6 pt into the menu bar bottom.
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

    @State private var isAppeared = false

    var body: some View {
        phaseContent
            .padding(.horizontal, OverlayMetrics.horizontalPadding)
            .frame(width: OverlayMetrics.panelSize.width, height: OverlayMetrics.pillHeight)
            .background(PillGlassBackground())
            .overlay(PillBorder(phase: state.phase))
            .scaleEffect(isAppeared ? 1 : 0.72, anchor: .top)
            .offset(y: isAppeared ? 0 : -10)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                    isAppeared = true
                }
            }
            .onDisappear {
                isAppeared = false
            }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .idle:
            EmptyView()
        case .recording:
            RecordingOverlayContent(state: state)
                .transition(.opacity)
        case .transcribing:
            ProcessingOverlayContent(progress: nil)
                .transition(.opacity)
        case .processing(let progress):
            ProcessingOverlayContent(progress: progress)
                .transition(.opacity)
        case .warning(let message):
            WarningOverlayContent(message: message)
                .transition(.opacity)
        case .success:
            SuccessCheckView()
                .transition(.opacity)
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

private struct RecordingOverlayContent: View {
    let state: OverlayPanelState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 6, height: 6)

                Text(verbatim: Self.format(state.elapsedSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(timerColor)
                    .monospacedDigit()
            }
            .frame(height: 20)

            Spacer(minLength: 12)

            WaveformBars(samples: state.samples, tint: Color(hex: "#34D399"))
                .frame(width: 88, height: 18)
        }
    }

    private var timerColor: Color {
        colorScheme == .dark ? Color(hex: "#10B981") : Color(hex: "#047857")
    }

    private static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WaveformBars: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty, size.width > 0, size.height > 0 else { return }

            let count = samples.count
            let stepX = size.width / CGFloat(count)
            let barWidth = min(3, max(1.5, stepX * 0.48))

            for index in samples.indices {
                let value = CGFloat(min(max(samples[index], 0.08), 1))
                let height = max(3, value * size.height)
                let x = CGFloat(index) * stepX + ((stepX - barWidth) / 2)
                let rect = CGRect(
                    x: x,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(tint))
            }
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
