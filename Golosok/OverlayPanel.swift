import SwiftUI
import AppKit

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        if AudioCapture.shared.aiStatusText != nil {
            DispatchQueue.main.async {
                AudioCapture.shared.isHoveringAICancel = true
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async {
            AudioCapture.shared.isHoveringAICancel = false
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Во время ИИ-обработки перехватываем мышь для наведения и отмены
        if AudioCapture.shared.aiStatusText != nil {
            return super.hitTest(point)
        }
        // Во время обычной записи пропускаем клики сквозь оверлей
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        if AudioCapture.shared.aiStatusText != nil {
            AppLogger.shared.info("AISelection", "Клик по оверлею — отмена генерации")
            AISelectionManager.shared.cancelCurrentOperation()
            return
        }
        super.mouseDown(with: event)
    }
}

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    private var pendingHideWorkItem: DispatchWorkItem?
    
    func showOverlay(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            self.pendingHideWorkItem?.cancel()
            self.pendingHideWorkItem = nil
            AudioCapture.shared.isSuccessDone = false
            
            if self.panel == nil {
                let newPanel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                newPanel.isOpaque = false
                newPanel.backgroundColor = .clear
                newPanel.hasShadow = false
                newPanel.appearance = NSApp.effectiveAppearance
                newPanel.hidesOnDeactivate = false
                newPanel.isReleasedWhenClosed = false
                newPanel.level = .popUpMenu
                newPanel.isFloatingPanel = true
                newPanel.acceptsMouseMovedEvents = true
                newPanel.ignoresMouseEvents = false
                newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                
                let view = FloatingWidgetView()
                let hostingView = OverlayHostingView(rootView: view)
                hostingView.wantsLayer = true
                hostingView.layer?.backgroundColor = NSColor.clear.cgColor
                hostingView.layer?.isOpaque = false
                
                newPanel.contentView = hostingView
                self.panel = newPanel
            }
            
            let mouseLoc = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first {
                let panelWidth: CGFloat = 240
                let x = screen.frame.midX - (panelWidth / 2.0)
                let targetY = screen.visibleFrame.maxY - 44
                
                self.panel?.alphaValue = 0.0
                self.panel?.setFrameOrigin(NSPoint(x: x, y: targetY + 10))
                self.panel?.orderFrontRegardless()
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel?.animator().alphaValue = 1.0
                    self.panel?.animator().setFrameOrigin(NSPoint(x: x, y: targetY))
                }
            }
            
            completion?()
        }
    }
    
    func showWarning(message: String) {
        DispatchQueue.main.async {
            self.pendingHideWorkItem?.cancel()
            AudioCapture.shared.warningMessage = message
            AudioCapture.shared.isProcessingFile = false
            SoundEffect.playWarning()
            self.showOverlay {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.hideOverlay()
                }
                self.pendingHideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
            }
        }
    }
    
    func scheduleHide(after delay: Double) {
        DispatchQueue.main.async {
            self.pendingHideWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in self?.hideOverlay() }
            self.pendingHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    func hideOverlay() {
        DispatchQueue.main.async {
            self.pendingHideWorkItem?.cancel()
            self.pendingHideWorkItem = nil
            
            guard let panel = self.panel else { return }
            let currentFrame = panel.frame
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
                panel.animator().setFrameOrigin(NSPoint(x: currentFrame.minX, y: currentFrame.minY + 6))
            }) {
                panel.orderOut(nil)
                AudioCapture.shared.warningMessage = nil
                AudioCapture.shared.isSuccessDone = false
            }
        }
    }

    func keepFront() {
        guard let panel = self.panel, panel.alphaValue > 0, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }
}

struct CircularProgressView: View {
    var progress: Double
    let progressGradient = LinearGradient(colors: [Color(hex: "#38BDF8"), Color(hex: "#10B981")], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: "#6366F1").opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(progressGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
        }
        .frame(width: 18, height: 18)
    }
}

struct RotatingGlowBorder: View {
    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height) * 2.0
            TimelineView(.animation) { timeline in
                let angle = (timeline.date.timeIntervalSince1970 * 360.0 / 1.5).truncatingRemainder(dividingBy: 360)
                ZStack {
                    AngularGradient(
                        gradient: Gradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1"), Color(hex: "#38BDF8"), Color(hex: "#10B981"), Color(hex: "#C084FC")]),
                        center: .center
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(angle))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .mask(Capsule().stroke(lineWidth: 1.5))
            }
        }
    }
}

struct SuccessCheckView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#34D399").opacity(0.45), lineWidth: 2)
                .frame(width: 24, height: 24)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(appeared ? 1.0 : 0.2)
        .offset(y: appeared ? 0 : -10)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.52)) {
                appeared = true
            }
        }
    }
}

struct FloatingWidgetView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAppeared = false
    @State private var isHoveringCancel = false
    
    let greenGradient = LinearGradient(colors: [Color(hex: "#34D399"), Color(hex: "#059669")], startPoint: .top, endPoint: .bottom)
    let purpleGradient = LinearGradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1")], startPoint: .top, endPoint: .bottom)
    let glassBorderGradient = LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
    
    var body: some View {
        ZStack {
            Color.clear
            
            Capsule()
                .fill(getGlowColor())
                .frame(width: getWidth() - 10, height: 28)
                .blur(radius: 12)
                .opacity(0.4)
            
            HStack(alignment: .center, spacing: 10) {
                if let warningText = audioCapture.warningMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#F59E0B"))
                        Text(warningText)
                            .font(UIStyleFont.body(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                } else if audioCapture.isProcessingFile {
                    HStack(spacing: 8) {
                        CircularProgressView(progress: audioCapture.fileProcessingProgress)
                        Text("\(Int(audioCapture.fileProcessingProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                } else if let aiStatus = audioCapture.aiStatusText {
                    let isHovering = audioCapture.isHoveringAICancel
                    HStack(spacing: 8) {
                        Image(systemName: isHovering ? "xmark.circle.fill" : "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isHovering ? Color(hex: "#F43F5E") : Color(hex: "#C084FC"))
                        Text(isHovering ? LocalizedStringKey("Отменить") : LocalizedStringKey(aiStatus))
                            .font(UIStyleFont.body(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .help(String(localized: "Нажмите, чтобы отменить генерацию"))
                } else if audioCapture.transcribedText == String(localized: "Расшифровка...") {
                    HStack(spacing: 2.0) {
                        TimelineView(.animation) { timeline in
                            let time = timeline.date.timeIntervalSince1970 * 4.5
                            HStack(spacing: 2.0) {
                                ForEach(0..<18, id: \.self) { i in
                                    let height = sin(time + Double(i) * 0.5) * 7 + 11
                                    RoundedRectangle(cornerRadius: 1).fill(purpleGradient).frame(width: 2.0, height: height)
                                }
                            }
                        }
                    }
                } else if audioCapture.isSuccessDone {
                    SuccessCheckView()
                        .transition(.opacity)
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#10B981"))
                            .frame(width: 7, height: 7)
                            .shadow(color: Color(hex: "#10B981").opacity(0.8), radius: 3, x: 0, y: 0)
                        
                        Text(audioCapture.formattedRecordingTime)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(timerColor)
                            .shadow(color: timerColor.opacity(0.55), radius: 2, x: 0, y: 0)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 2.0) {
                        ForEach(0..<18, id: \.self) { i in
                            let sampleVal = i < audioCapture.audioSamples.count ? audioCapture.audioSamples[i] : 0.15
                            
                            RoundedRectangle(cornerRadius: 1)
                                .fill(greenGradient)
                                .frame(width: 2.0, height: CGFloat(sampleVal) * 22)
                                .animation(.spring(response: 0.12, dampingFraction: 0.55), value: sampleVal)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(width: getWidth(), height: 36)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Group {
                    if audioCapture.transcribedText == String(localized: "Расшифровка...") || audioCapture.isProcessingFile || audioCapture.aiStatusText != nil {
                        RotatingGlowBorder()
                    } else if audioCapture.warningMessage != nil {
                        Capsule().stroke(Color(hex: "#F59E0B").opacity(0.6), lineWidth: 1.2)
                    } else if audioCapture.isSuccessDone {
                        Capsule().stroke(Color(hex: "#34D399").opacity(0.75), lineWidth: 1.2)
                    } else {
                        Capsule().stroke(glassBorderGradient, lineWidth: 1.0)
                    }
                }
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: getWidth())
        }
        .scaleEffect(isAppeared ? 1.0 : 0.65)
        .offset(y: isAppeared ? 0 : -14)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.55)) {
                isAppeared = true
            }
        }
        .onDisappear {
            isAppeared = false
        }
        .frame(width: 240, height: 60)
    }
    
    private func getWidth() -> CGFloat {
        if audioCapture.warningMessage != nil { return 210 }
        if audioCapture.aiStatusText != nil {
            return audioCapture.isHoveringAICancel ? 150 : 175
        }
        if audioCapture.isProcessingFile { return 110 }
        if audioCapture.isRecording { return 200 }
        if audioCapture.isSuccessDone { return 150 }
        return 130
    }
    
    private func getGlowColor() -> Color {
        if audioCapture.warningMessage != nil { return Color(hex: "#F59E0B") }
        if audioCapture.aiStatusText != nil { return Color(hex: "#C084FC") }
        if audioCapture.isProcessingFile || audioCapture.transcribedText == String(localized: "Расшифровка...") { return Color(hex: "#6366F1") }
        if audioCapture.isSuccessDone { return Color(hex: "#10B981") }
        return Color(hex: "#10B981")
    }

    private var timerColor: Color {
        colorScheme == .dark ? Color(hex: "#10B981") : Color(hex: "#047857")
    }
}
