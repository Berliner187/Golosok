import SwiftUI
import AppKit

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    
    func showOverlay() {
        DispatchQueue.main.async {
            if self.panel == nil {
                let newPanel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 140, height: 42),
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
                let x = screenRect.midX - 70
                let y = screenRect.maxY - 70
                self.panel?.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            self.panel?.orderFrontRegardless()
        }
    }

    func hideOverlay() {
        DispatchQueue.main.async {
            self.panel?.orderOut(nil)
        }
    }
}

struct FloatingWidgetView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    
    let greenColor = Color(hex: "#10B981")
    let purpleColor = Color(hex: "#8B5CF6")
    
    var body: some View {
        HStack(spacing: 3.5) {
            if audioCapture.transcribedText == "Расшифровка..." {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSince1970 * 4.5
                    HStack(spacing: 3.5) {
                        ForEach(0..<9, id: \.self) { i in
                            let height = sin(time + Double(i) * 0.7) * 8 + 13
                            RoundedRectangle(cornerRadius: 2)
                                .fill(purpleColor)
                                .frame(width: 3.5, height: height)
                        }
                    }
                }
            } else {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(greenColor)
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
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}
