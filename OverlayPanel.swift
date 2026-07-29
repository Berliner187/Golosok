import SwiftUI
import AppKit

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    
    func showOverlay() {
        DispatchQueue.main.async {
            if self.panel == nil {
                // Размеры окна чуть больше самой капсулы под 3D-тень
                let newPanel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 150, height: 50),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                newPanel.isOpaque = false
                newPanel.backgroundColor = .clear
                // Включаем нативную 3D-тень macOS строго по контуру капсулы!
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
                let x = screenRect.midX - 75
                let targetY = screenRect.maxY - 70
                
                self.panel?.alphaValue = 0.0
                self.panel?.setFrameOrigin(NSPoint(x: x, y: targetY + 12))
                self.panel?.makeKeyAndOrderFront(nil)
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel?.animator().alphaValue = 1.0
                    self.panel?.animator().setFrameOrigin(NSPoint(x: x, y: targetY))
                }
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
                panel.animator().setFrameOrigin(NSPoint(x: currentFrame.minX, y: currentFrame.minY + 8))
            }) {
                panel.orderOut(nil)
            }
        }
    }
}

struct FloatingWidgetView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    
    let greenGradient = LinearGradient(
        colors: [Color(hex: "#34D399"), Color(hex: "#059669")],
        startPoint: .top, endPoint: .bottom
    )
    let purpleGradient = LinearGradient(
        colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1")],
        startPoint: .top, endPoint: .bottom
    )
    
    var body: some View {
        ZStack {
            Color.clear
            
            HStack(spacing: 8) {
                if audioCapture.isProcessingFile {
                    // ОБРАБОТКА ДЛИННОГО ФАЙЛА С ЖИВЫМИ %
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSince1970 * 4.5
                        HStack(spacing: 2.5) {
                            ForEach(0..<5, id: \.self) { i in
                                let height = sin(time + Double(i) * 0.7) * 6 + 10
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(purpleGradient)
                                    .frame(width: 3, height: height)
                            }
                        }
                    }
                    
                    // БЕГУЩИЙ ПРОЦЕНТ ВЫПОЛНЕНИЯ
                    Text("\(Int(audioCapture.fileProcessingProgress * 100))%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.dynamic(light: "#0a0a0a", dark: "#fafafa"))
                        
                } else if audioCapture.transcribedText == "Расшифровка..." {
                    // ОБЫЧНАЯ ДИКТОВКА (Фиолетовая волна)
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSince1970 * 4.5
                        HStack(spacing: 3.5) {
                            ForEach(0..<9, id: \.self) { i in
                                let height = sin(time + Double(i) * 0.7) * 8 + 13
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(purpleGradient)
                                    .frame(width: 3.5, height: height)
                            }
                        }
                    }
                } else {
                    // ЗАПИСЬ С МИКРОФОНА (Зеленый эквалайзер)
                    ForEach(0..<9, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(greenGradient)
                            .frame(width: 3.5, height: CGFloat(audioCapture.audioSamples[i]) * 26)
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: audioCapture.audioSamples[i])
                    }
                }
            }
            .frame(width: 130, height: 38)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.15), Color.black.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
        }
        .frame(width: 150, height: 50)
    }
}
