import SwiftUI

struct SplashView: View {
    @Binding var isFinished: Bool
    
    @State private var phase: Int = 0
    @State private var waveScale1: CGFloat = 0.2
    @State private var waveScale2: CGFloat = 0.2
    @State private var waveScale3: CGFloat = 0.2
    @State private var waveOpacity: Double = 0.0
    
    @State private var dotSize: CGFloat = 20
    @State private var dotRotation: Double = 0
    @State private var perspective3D: Double = 45
    
    @State private var logoOpacity: Double = 0.0
    @State private var subtitleOpacity: Double = 0.0
    @State private var splashScale: CGFloat = 1.0
    @State private var splashBlur: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            
            // 3D ВОЛНЫ
            ZStack {
                Circle()
                    .stroke(Color.uiInk.opacity(0.15), lineWidth: 1.5)
                    .scaleEffect(waveScale1)
                    .opacity(waveOpacity)
                
                Circle()
                    .stroke(Color(hex: "#10B981").opacity(0.3), lineWidth: 2)
                    .scaleEffect(waveScale2)
                    .opacity(waveOpacity)
                
                Circle()
                    .stroke(Color.uiInk.opacity(0.1), lineWidth: 1)
                    .scaleEffect(waveScale3)
                    .opacity(waveOpacity)
            }
            .frame(width: 320, height: 320)
            
            // ЛОГОТИП-ТРАНСФОРМЕР (Точка ➔ Иконка Голоска)
            VStack(spacing: 28) {
                ZStack {
                    if phase < 2 {
                        Circle()
                            .fill(Color.uiInk)
                            .frame(width: dotSize, height: dotSize)
                            .scaleEffect(dotSize / 20.0)
                    } else {
                        // ТВОЯ ИКОНКА (Черный круг в белом квадрате с тенью)
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color(hex: "#E5E5E5"), lineWidth: 1)
                                )
                            
                            Circle()
                                .fill(Color(hex: "#1E1E1E"))
                                .frame(width: 44, height: 44)
                        }
                        .rotation3DEffect(.degrees(dotRotation), axis: (x: 0, y: 1, z: 0))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                
                VStack(spacing: 10) {
                    Text("Г О Л О С О К")
                        .font(.system(size: 38, weight: .bold, design: .default))
                        .tracking(7.0)
                        .foregroundColor(.uiInk)
                        .opacity(logoOpacity)
                        .rotation3DEffect(.degrees(perspective3D), axis: (x: 1, y: 0, z: 0))
                    
                    VStack(spacing: 4) {
                        Text("Быстрый голосовой ввод для Mac")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(2.0)
                            .foregroundColor(.uiMidGray)
                        
                        Text("ЛОКАЛЬНО • БЫСТРО • АВТОНОМНО")
                            .font(UIStyleFont.body(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(Color(hex: "#10B981"))
                    }
                    .opacity(subtitleOpacity)
                }
            }
            .scaleEffect(splashScale)
            .blur(radius: splashBlur)
        }
        .onAppear {
            runMasterSequence()
        }
    }
    
    private func runMasterSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            StartupSoundSynth.playTeslaChime()
            
            withAnimation(.easeOut(duration: 1.0)) {
                waveScale1 = 2.4
                waveScale2 = 1.8
                waveScale3 = 3.2
                waveOpacity = 1.0
            }
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                dotSize = 36
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                dotSize = 18
                waveOpacity = 0.2
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                phase = 2
                dotRotation = 360
                logoOpacity = 1.0
                perspective3D = 0
                waveScale2 = 3.8
                waveOpacity = 0.8
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.5)) {
                subtitleOpacity = 1.0
                waveOpacity = 0.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeInOut(duration: 0.5)) {
                splashScale = 1.12
                splashBlur = 10.0
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isFinished = true
            }
        }
    }
}
