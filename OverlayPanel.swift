import SwiftUI
import AppKit

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    
    func showOverlay() {
        DispatchQueue.main.async {
            if self.panel == nil {
                let newPanel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                newPanel.isOpaque = false
                newPanel.backgroundColor = .clear
                newPanel.hasShadow = true
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
                let targetY = screenRect.maxY - 70
                
                self.panel?.alphaValue = 0.0
                self.panel?.setFrameOrigin(NSPoint(x: x, y: targetY + 10))
                self.panel?.orderFrontRegardless()
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel?.animator().alphaValue = 1.0
                    self.panel?.animator().setFrameOrigin(NSPoint(x: x, y: targetY))
                }
            }
        }
    }
    
    // ЖЕЛТЫЙ DYNAMIC ISLAND ВАРНИНГ
    func showWarning(message: String) {
        DispatchQueue.main.async {
            AudioCapture.shared.warningMessage = message
            AudioCapture.shared.isProcessingFile = false
            SoundEffect.playCancel()
            self.showOverlay()
            
            // Держим желтую плашку 3.5 секунды
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
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
                panel.animator().setFrameOrigin(NSPoint(x: currentFrame.minX, y: currentFrame.minY + 6))
            }) {
                panel.orderOut(nil)
            }
        }
    }
}

struct FloatingWidgetView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @State private var rotateAngle: Double = 0
    
    let greenGradient = LinearGradient(colors: [Color(hex: "#34D399"), Color(hex: "#059669")], startPoint: .top, endPoint: .bottom)
    let purpleGradient = LinearGradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1")], startPoint: .top, endPoint: .bottom)
    
    var body: some View {
        ZStack {
            Color.clear
            
            // ПРИОРИТЕТ 1: ЖЕЛТЫЙ ВАРНИНГ ОШИБКИ
            if let warningText = audioCapture.warningMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "#F59E0B"))
                    
                    Text(warningText)
                        .font(UIStyleFont.body(size: 12, weight: .semibold))
                        .foregroundColor(Color.dynamic(light: "#0a0a0a", dark: "#fafafa"))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color(hex: "#F59E0B").opacity(0.6), lineWidth: 1.2)
                )
            // ПРИОРИТЕТ 2: ОБРАБОТКА ФАЙЛА С ПРОГРЕССОМ %
            } else if audioCapture.isProcessingFile {
                HStack(spacing: 8) {
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSince1970 * 4.5
                        HStack(spacing: 2.5) {
                            ForEach(0..<5, id: \.self) { i in
                                let height = sin(time + Double(i) * 0.7) * 5 + 9
                                RoundedRectangle(cornerRadius: 2).fill(purpleGradient).frame(width: 3, height: height)
                            }
                        }
                    }
                    
                    Text("Файл \(Int(audioCapture.fileProcessingProgress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.dynamic(light: "#0a0a0a", dark: "#fafafa"))
                }
                .frame(width: 170, height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        AngularGradient(gradient: Gradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1"), Color(hex: "#3B82F6"), Color(hex: "#C084FC")]), center: .center, angle: .degrees(rotateAngle)),
                        lineWidth: 1.5
                    )
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { rotateAngle = 360 }
                    }
                )
            // ПРИОРИТЕТ 3: МИКРОФОН РАСШИФРОВКА (ТОЛЬКО ВОЛНЫ, БЕЗ СЛОВА ФАЙЛ)
            } else if audioCapture.transcribedText == "Расшифровка..." {
                HStack(spacing: 2.5) {
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSince1970 * 4.5
                        HStack(spacing: 2.5) {
                            ForEach(0..<9, id: \.self) { i in
                                let height = sin(time + Double(i) * 0.7) * 7 + 12
                                RoundedRectangle(cornerRadius: 2).fill(purpleGradient).frame(width: 3.5, height: height)
                            }
                        }
                    }
                }
                .frame(width: 130, height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        AngularGradient(gradient: Gradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1"), Color(hex: "#3B82F6"), Color(hex: "#C084FC")]), center: .center, angle: .degrees(rotateAngle)),
                        lineWidth: 1.5
                    )
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { rotateAngle = 360 }
                    }
                )
            // ПРИОРИТЕТ 4: МИКРОФОН ЗАПИСЬ
            } else {
                HStack(spacing: 2.5) {
                    ForEach(0..<9, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(greenGradient)
                            .frame(width: 3, height: CGFloat(audioCapture.audioSamples[i]) * 24)
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: audioCapture.audioSamples[i])
                    }
                }
                .frame(width: 130, height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.15), Color.black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.0
                    )
                )
            }
        }
        .frame(width: 220, height: 50)
    }
}
