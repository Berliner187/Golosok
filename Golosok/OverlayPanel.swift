import SwiftUI
import AppKit

class OverlayPanelManager {
    static let shared = OverlayPanelManager()
    private var panel: NSPanel?
    private var warningHideWorkItem: DispatchWorkItem?
    
    func showOverlay() {
        DispatchQueue.main.async {
            if AudioCapture.shared.warningMessage == nil {
                self.warningHideWorkItem?.cancel()
                self.warningHideWorkItem = nil
            }
            AudioCapture.shared.isSuccessDone = false
            
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
        }
    }
    
    func showWarning(message: String) {
        DispatchQueue.main.async {
            self.warningHideWorkItem?.cancel()
            
            AudioCapture.shared.warningMessage = message
            AudioCapture.shared.isProcessingFile = false
            SoundEffect.playWarning()
            self.showOverlay()
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.hideOverlay()
            }
            self.warningHideWorkItem = workItem
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
        }
    }
    
    func hideOverlay() {
        DispatchQueue.main.async {
            self.warningHideWorkItem?.cancel()
            self.warningHideWorkItem = nil
            
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

struct FloatingWidgetView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @State private var isAppeared = false
    
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
                    ZStack {
                        Circle()
                            .stroke(Color(hex: "#34D399").opacity(0.45), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: "#10B981"))
                            .frame(width: 7, height: 7)
                            .shadow(color: Color(hex: "#10B981").opacity(0.8), radius: 3, x: 0, y: 0)
                        
                        Text(audioCapture.formattedRecordingTime)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
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
                    if audioCapture.transcribedText == String(localized: "Расшифровка...") || audioCapture.isProcessingFile {
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
        if audioCapture.isProcessingFile { return 110 }
        if audioCapture.isRecording { return 200 }
        if audioCapture.isSuccessDone { return 150 }
        return 130
    }
    
    private func getGlowColor() -> Color {
        if audioCapture.warningMessage != nil { return Color(hex: "#F59E0B") }
        if audioCapture.isProcessingFile || audioCapture.transcribedText == String(localized: "Расшифровка...") { return Color(hex: "#6366F1") }
        if audioCapture.isSuccessDone { return Color(hex: "#10B981") }
        return Color(hex: "#10B981")
    }
}
