import SwiftUI

// КОМПОНЕНТ ПУЛЬСИРУЮЩЕГО ОРЕОЛА
struct PulsingHaloRing: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince1970
            let angle = (time * 120.0).truncatingRemainder(dividingBy: 360)
            let pulse = sin(time * 3.5) * 0.12 + 1.05
            
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "#064E3B"),
                            Color(hex: "#10B981"),
                            Color(hex: "#A7F3D0"),
                            Color(hex: "#10B981"),
                            Color(hex: "#064E3B")
                        ]),
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: 10
                )
                .frame(width: 90, height: 90)
                .scaleEffect(pulse)
        }
    }
}

struct SplashView: View {
    @Binding var isFinished: Bool
    
    // Фазы анимации
    @State private var phase: Int = 0
    
    // Точка и Орбиты
    @State private var centerDotSize: CGFloat = 16
    @State private var satelliteDistance: CGFloat = 0
    @State private var satelliteRotation: Double = 0
    @State private var dotRotation: Double = 0
    @State private var perspective3D: Double = 60
    
    // Ударные волны
    @State private var shockwaveScale1: CGFloat = 0.5
    @State private var shockwaveScale2: CGFloat = 0.5
    @State private var shockwaveOpacity: Double = 0.0
    
    // Ореол
    @State private var haloScale: CGFloat = 0.01
    @State private var haloOpacity: Double = 0.0
    @State private var haloBlur: CGFloat = 0.0
    
    // Тексты и Фон
    @State private var logoOpacity: Double = 0.0
    @State private var subtitleOpacity: Double = 0.0
    @State private var splashScale: CGFloat = 1.0
    @State private var splashBlur: CGFloat = 0.0
    
    // Фон Авраа
    @State private var aurora1Offset: CGSize = CGSize(width: 100, height: -100)
    @State private var aurora2Offset: CGSize = CGSize(width: -100, height: 100)
    @State private var auroraOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            
            ZStack {
                Circle()
                    .fill(Color(hex: "#10B981").opacity(0.18))
                    .frame(width: 420, height: 420)
                    .offset(aurora1Offset)
                    .blur(radius: 90)
                
                Circle()
                    .fill(Color(hex: "#C084FC").opacity(0.15))
                    .frame(width: 520, height: 520)
                    .offset(aurora2Offset)
                    .blur(radius: 120)
            }
            .opacity(auroraOpacity)
            
            VStack(spacing: 32) {
                
                ZStack {
                    PulsingHaloRing()
                        .blur(radius: haloBlur)
                        .scaleEffect(haloScale)
                        .opacity(haloOpacity)
                    
                    if phase < 2 {
                        ZStack {
                            Circle().stroke(Color.uiInk.opacity(0.15), lineWidth: 1).frame(width: 80, height: 80).scaleEffect(shockwaveScale1)
                            Circle().stroke(Color(hex: "#10B981").opacity(0.3), lineWidth: 2).frame(width: 80, height: 80).scaleEffect(shockwaveScale2)
                        }
                        .opacity(shockwaveOpacity)
                        
                        ZStack {
                            Circle().fill(Color.uiInk).frame(width: centerDotSize, height: centerDotSize)
                            ForEach(0..<4, id: \.self) { i in
                                Circle()
                                    .fill(Color.uiInk)
                                    .frame(width: 8, height: 8)
                                    .offset(y: -satelliteDistance)
                                    .rotationEffect(.degrees(Double(i) * 90))
                            }
                        }
                        .rotationEffect(.degrees(satelliteRotation))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 8)
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color(hex: "#E5E5E5"), lineWidth: 1))
                            
                            Circle().fill(Color(hex: "#1E1E1E")).frame(width: 44, height: 44)
                        }
                        .rotation3DEffect(.degrees(dotRotation), axis: (x: 0, y: 1, z: 0))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 120)
                
                VStack(spacing: 14) {
                    Text("Г О Л О С О К")
                        .font(Font.custom("HelveticaNeue-UltraLight", size: 42))
                        .tracking(14.0)
                        .foregroundColor(.uiInk)
                        .opacity(logoOpacity)
                        .rotation3DEffect(.degrees(perspective3D), axis: (x: 1, y: 0, z: 0))
                        .offset(y: logoOpacity == 1.0 ? 0 : 20)
                    
                    VStack(spacing: 6) {
                        Text("Голосовой ввод и транскрибация на Вашем Mac")
                            .font(UIStyleFont.body(size: 13, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.uiMidGray)
                        
                        Text("APPLE SILICON • GIGAAM V3 • NEURAL ENGINE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(Color(hex: "#10B981"))
                    }
                    .opacity(subtitleOpacity)
                    .offset(y: subtitleOpacity == 1.0 ? 0 : 10)
                }
            }
            .scaleEffect(splashScale)
            .blur(radius: splashBlur)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            runMasterSequence()
            startAuroraBreathing()
        }
    }
    
    private func startAuroraBreathing() {
        withAnimation(.easeIn(duration: 1.2)) { auroraOpacity = 1.0 }
        withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
            aurora1Offset = CGSize(width: -80, height: 100)
            aurora2Offset = CGSize(width: 80, height: -100)
        }
    }
    
    private func runMasterSequence() {
        // 0.1s — ПЕРВЫЙ УДАР БАСА
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            StartupSoundSynth.playTeslaChime()
            
            withAnimation(.easeOut(duration: 1.0)) {
                shockwaveScale1 = 3.5; shockwaveScale2 = 2.5; shockwaveOpacity = 1.0
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                centerDotSize = 8; satelliteDistance = 55
            }
            withAnimation(.easeOut(duration: 0.8)) {
                satelliteRotation = 270
            }
        }
        
        // 0.6s — Стяжка точек
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                satelliteDistance = 0; centerDotSize = 24; shockwaveOpacity = 0.0
            }
        }
        
        // 1.0s — ВТОРОЙ БАСОВЫЙ УДАР
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                phase = 2
                dotRotation = 360
                logoOpacity = 1.0
                perspective3D = 0
                
                // Вспышка
                haloScale = 1.3
                haloOpacity = 1.0
                haloBlur = 15.0
            }
            
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5).delay(0.2)) {
                haloScale = 1.0
                haloBlur = 10.0
            }
        }
        
        // 1.8s — Тексты
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.5)) { subtitleOpacity = 1.0 }
        }
        
        // 3.1s — Уход
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            withAnimation(.easeInOut(duration: 0.5)) {
                splashScale = 1.12
                splashBlur = 12.0
                auroraOpacity = 0.0
                haloOpacity = 0.0
            }
        }
        
        // 3.6s — Переход в приложение
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            withAnimation(.easeInOut(duration: 0.3)) { isFinished = true }
        }
    }
}
