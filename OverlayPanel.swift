import SwiftUI
import AppKit

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    
    func showOverlay() {
        DispatchQueue.main.async {
            if self.panel == nil {
                let newPanel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 140, height: 46),
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
                let x = screenRect.midX - 70
                let targetY = screenRect.maxY - 68
                
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
    
    // Угол вращения неонового кольца
    @State private var rotateAngle: Double = 0
    
    let greenGradient = LinearGradient(colors: [Color(hex: "#34D399"), Color(hex: "#059669")], startPoint: .top, endPoint: .bottom)
    let purpleGradient = LinearGradient(colors: [Color(hex: "#C084FC"), Color(hex: "#6366F1")], startPoint: .top, endPoint: .bottom)
    
    var body: some View {
        ZStack {
            Color.clear
            
            HStack(spacing: 2.5) {
                if audioCapture.isProcessingFile {
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSince1970 * 4.5
                        HStack(spacing: 2.5) {
                            ForEach(0..<5, id: \.self) { i in
                                let height = sin(time + Double(i) * 0.7) * 5 + 9
                                RoundedRectangle(cornerRadius: 2).fill(purpleGradient).frame(width: 3, height: height)
                            }
                        }
                    }
                    Text("\(Int(audioCapture.fileProcessingProgress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.dynamic(light: "#0a0a0a", dark: "#fafafa"))
                        .padding(.leading, 2)
                        
                } else if audioCapture.transcribedText == "Расшифровка..." {
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSince1970 * 4.5
                        HStack(spacing: 2.5) {
                            ForEach(0..<9, id: \.self) { i in
                                let height = sin(time + Double(i) * 0.7) * 7 + 12
                                RoundedRectangle(cornerRadius: 2).fill(purpleGradient).frame(width: 3, height: height)
                            }
                        }
                    }
                } else {
                    ForEach(0..<9, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(greenGradient)
                            .frame(width: 3, height: CGFloat(audioCapture.audioSamples[i]) * 24)
                            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: audioCapture.audioSamples[i])
                    }
                }
            }
            .frame(width: 120, height: 34)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                // ДИНАМИЧЕСКАЯ РАМКА
                Group {
                    if audioCapture.transcribedText == "Расшифровка..." || audioCapture.isProcessingFile {
                        // ВРАЩАЮЩЕЕСЯ НЕОНОВОЕ КОЛЬЦО (Apple Intelligence Style)
                        Capsule()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "#C084FC"),
                                        Color(hex: "#6366F1"),
                                        Color(hex: "#3B82F6"),
                                        Color(hex: "#10B981"),
                                        Color(hex: "#C084FC")
                                    ]),
                                    center: .center,
                                    angle: .degrees(rotateAngle)
                                ),
                                lineWidth: 2.0
                            )
                            .onAppear {
                                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                    rotateAngle = 360
                                }
                            }
                    } else {
                        // СТАТИЧЕСКИЙ СТЕКЛЯННЫЙ БЛИК ДЛЯ ЗАПИСИ
                        Capsule().stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.white.opacity(0.15), Color.black.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                    }
                }
            )
        }
        .frame(width: 140, height: 46)
    }
}
