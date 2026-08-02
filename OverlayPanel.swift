import SwiftUI
import AppKit

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    
    func showOverlay() {
        DispatchQueue.main.async {
            if self.panel == nil {
                let newPanel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                newPanel.isOpaque = false
                newPanel.backgroundColor = .clear
                newPanel.hasShadow = false
                newPanel.level = .screenSaver
                newPanel.isFloatingPanel = true
                newPanel.ignoresMouseEvents = true
                newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                
                let view = FloatingWidgetView()
                let hostingView = NSHostingView(rootView: view)
                hostingView.wantsLayer = true
                hostingView.layer?.backgroundColor = NSColor.clear.cgColor
                hostingView.layer?.isOpaque = false
                
                newPanel.contentView = hostingView
                self.panel = newPanel
            }
            
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let x = screenRect.midX - 110
                let targetY = screenRect.maxY - 80
                
                self.panel?.alphaValue = 0.0
                self.panel?.setFrameOrigin(NSPoint(x: x, y: targetY + 15))
                self.panel?.orderFrontRegardless()
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel?.animator().alphaValue = 1.0
                    self.panel?.animator().setFrameOrigin(NSPoint(x: x, y: targetY))
                }
            }
        }
    }
    
    func showWarning(message: String) {
        DispatchQueue.main.async {
            AudioCapture.shared.warningMessage = message
            AudioCapture.shared.isProcessingFile = false
            SoundEffect.playCancel()
            self.showOverlay()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                AudioCapture.shared.warningMessage = nil
                self.hideOverlay()
            }
        }
    }
    
    func hideOverlay() {
        DispatchQueue.main.async {
            guard let panel = self.panel else { return }
            let currentFrame = panel.frame
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
                panel.animator().setFrameOrigin(NSPoint(x: currentFrame.minX, y: currentFrame.minY + 10))
            }) {
                panel.orderOut(nil)
            }
        }
    }
}

// КРУГОВОЙ ПРОГРЕСС БАР ДЛЯ ФАЙЛОВ
struct CircularProgressView: View {
    var progress: Double
    
    let progressGradient = LinearGradient(
        colors: [Color(hex: "#38BDF8"), Color(hex: "#10B981")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#6366F1").opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(progressGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
        }
        .frame(width: 18, height: 18)
    }
}

// ВРАЩАЮЩАЯСЯ РАМКА СТРОГО ПО КОНТУРУ
struct RotatingGlowBorder: View {
    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height) * 2.0
            
            TimelineView(.animation) { timeline in
                let angle = (timeline.date.timeIntervalSince1970 * 360.0 / 1.5).truncatingRemainder(dividingBy: 360)
                
                ZStack {
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "#C084FC"),
                            Color(hex: "#6366F1"),
                            Color(hex: "#38BDF8"),
                            Color(hex: "#10B981"),
                            Color(hex: "#C084FC")
                        ]),
                        center: .center
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(angle))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .mask(
                    Capsule().stroke(lineWidth: 1.5)
                )
            }
        }
    }
}

struct FloatingWidgetView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    
    let greenGradient = LinearGradient(colors: [Color(hex: "#34D399"), Color(hex: "#059669")], startPoint: .top, endPoint: .bottom)
    let purpleGradient = LinearGradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1")], startPoint: .top, endPoint: .bottom)
    
    var body: some View {
        ZStack {
            Color.clear
            
            // ОСНОВНОЙ КОНТЕНТ КАПСУЛЫ
            HStack(spacing: 8) {
                if let warningText = audioCapture.warningMessage {
                    // 1. ЖЕЛТЫЙ ВАРНИНГ ОШИБКИ
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#F59E0B"))
                        Text(warningText)
                            .font(UIStyleFont.body(size: 12, weight: .semibold))
                            .foregroundColor(Color.dynamic(light: "#0a0a0a", dark: "#fafafa"))
                            .lineLimit(1)
                    }
                } else if audioCapture.isProcessingFile {
                    // 2. ИМПОРТ ФАЙЛА: КРУГОВОЙ ПРОГРЕСС И %
                    HStack(spacing: 10) {
                        CircularProgressView(progress: audioCapture.fileProcessingProgress)
                        
                        Text("\(Int(audioCapture.fileProcessingProgress * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.dynamic(light: "#0a0a0a", dark: "#fafafa"))
                    }
                } else if audioCapture.isRecording {
                    // 3. МИКРОФОН ЗАПИСЬ: Зеленый эквалайзер
                    HStack(spacing: 4.5) {
                        ForEach(0..<9, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(greenGradient)
                                .frame(width: 3.5, height: CGFloat(audioCapture.audioSamples[i]) * 24)
                                .animation(.spring(response: 0.15, dampingFraction: 0.5), value: audioCapture.audioSamples[i])
                        }
                    }
                } else {
                    // 4. МИКРОФОН РАСШИФРОВКА И ЗАКРЫТИЕ: Фиолетовые волны
                    HStack(spacing: 4.5) {
                        TimelineView(.animation) { timeline in
                            let time = timeline.date.timeIntervalSince1970 * 4.5
                            HStack(spacing: 4.5) {
                                ForEach(0..<9, id: \.self) { i in
                                    let height = sin(time + Double(i) * 0.7) * 7 + 12
                                    RoundedRectangle(cornerRadius: 2).fill(purpleGradient).frame(width: 3.5, height: height)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(width: getWidth(), height: 38)
            .background(.regularMaterial)
                .background(
                    Capsule()
                        .fill(Color.uiPaper.opacity(0.85))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.15), Color.black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.0
                    )
                )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: getWidth())
        }
        .frame(width: 220, height: 46)
    }
    
    private func getWidth() -> CGFloat {
        if audioCapture.warningMessage != nil { return 210 }
        if audioCapture.isProcessingFile { return 110 }
        return 130
    }
    
    private func getGlowColor() -> Color {
        if audioCapture.warningMessage != nil { return Color(hex: "#F59E0B") }
        if audioCapture.isRecording { return Color(hex: "#10B981") }
        return Color(hex: "#6366F1")
    }
}
