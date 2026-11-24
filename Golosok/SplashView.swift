import SwiftUI

// MARK: - Таймлайн (секунды от старта звука) — должен совпадать с SoundEngine.renderStartup()
//
//  0.10  появляется точка                (звук: тихий стеклянный тик)
//  0.15  точка «раскрывается» в сферу    (звук: разгон + воздух)
//  1.15  сфера собрана — «замок»         (звук: глухой удар + аккорд D)
//  1.30  буквы проявляются по очереди; сфера плавно поднимается
//  3.05  уход: лёгкое увеличение и растворение (звук: выдох)
//  3.60  переход в приложение
private enum SplashTime {
    static let dot = 0.10
    static let bloom = 0.15
    static let bloomLength = 1.0
    static let hit = 1.15
    static let letters = 1.30
    static let exit = 3.05
    static let total = 3.6
}

// MARK: - Easing

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
private func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.4, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

// MARK: - Геометрия сферы (Фибоначчи, как у островка записи)

private struct SplashPoint {
    let x, y, z, delay: Double
}

private enum SplashGeometry {
    static let points: [SplashPoint] = {
        let n = 1100
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let r = (1 - y * y).squareRoot()
            let a = golden * Double(i)
            let h = Double((i &* 2654435761) % 1000) / 1000
            return SplashPoint(x: cos(a) * r, y: y, z: sin(a) * r, delay: h)
        }
    }()
}

// MARK: - Сцена

private struct SplashScene: View {
    let t: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let letters = Array("GOLOSOK")
    private var ink: Color { scheme == .dark ? .white : Color(white: 0.04) }

    var body: some View {
        let lift = easeInOut(clamp01((t - SplashTime.hit) / 1.0))
        let exit = clamp01((t - SplashTime.exit) / 0.5)

        ZStack {
            Canvas { context, size in
                Self.drawSphere(&context, size: size, t: t, ink: ink, calm: reduceMotion)
            }
            .frame(width: 340, height: 340)
            .offset(y: -62 * lift)

            HStack(spacing: 58) {          // интервал как в исходном «Г О Л О С О К» (≈0.9 em)
                ForEach(0..<letters.count, id: \.self) { i in
                    letter(i)
                }
            }
            .offset(y: 116)
        }
        .scaleEffect(1 + 0.04 * exit * exit)
        .blur(radius: 8 * exit)
        .opacity(1 - exit)
    }

    private func letter(_ i: Int) -> some View {
        let local = clamp01((t - SplashTime.letters - Double(i) * 0.06) / 0.6)
        let e = easeOut(local)
        return Text(String(letters[i]))
            .font(Font.custom("HelveticaNeue-UltraLight", size: 64))
            .foregroundColor(.uiInk)
            .opacity(e)
            .blur(radius: (1 - e) * 14)
            .offset(y: (1 - e) * 18)
    }

    /// Накопленный угол вращения: плавный разгон до удара, затем быстрое торможение.
    /// Скорость непрерывна: к моменту удара 2.4 рад/с, после — экспоненциально затухает до базовой.
    private static func yaw(_ t: Double) -> Double {
        let base = 0.35 * t
        if t <= SplashTime.hit {
            let p = clamp01((t - SplashTime.bloom) / SplashTime.bloomLength)
            return base + 0.8 * p * p * p
        }
        let since = t - SplashTime.hit
        return base + 0.8 + 0.6 * (1 - exp(-since / 0.25))
    }

    private static func drawSphere(_ ctx: inout GraphicsContext, size: CGSize, t: Double, ink: Color, calm: Bool) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = Double(min(size.width, size.height)) * 0.31
        let bloom = clamp01((t - SplashTime.bloom) / SplashTime.bloomLength)
        let since = t - SplashTime.hit
        let tt = calm ? 0 : t

        // Органичная «жидкая» поверхность при сборке, после удара — почти ровная, с лёгким дыханием.
        let amp = since < 0 ? 0.10 : 0.035 + 0.065 * exp(-since / 0.45)
        let ang = calm ? 0.4 : yaw(t)
        let pitch = 0.38
        let cp = cos(pitch), sp = sin(pitch)
        let ca = cos(ang), sa = sin(ang)

        // Волна «замка»: фронт идёт снизу вверх по поверхности, плюс короткий упругий «толчок» всей сферы.
        let u = since >= 0 ? clamp01(since / 0.9) : 0
        let wavePos = -1 + 2 * easeOut(u)
        let waveAmp = since >= 0 ? 1 - u : 0
        let thump = since >= 0 ? 0.05 * exp(-since * 9) * cos(since * 22) : 0

        var layers = [Path](repeating: Path(), count: 4)
        if bloom > 0 {
            for p in SplashGeometry.points {
                let local = clamp01((bloom - p.delay * 0.4) / 0.6)
                if local <= 0 { continue }
                let e = easeOutBack(local)

                let n = sin(p.x * 3.1 + tt * 1.3) * cos(p.y * 2.7 - tt * 1.1)
                      + 0.6 * sin(p.z * 4.0 + tt * 0.9 + p.x * 2)
                let band = waveAmp > 0.01 ? waveAmp * exp(-pow((p.y - wavePos) / 0.20, 2)) : 0
                let rad = e * (1 + amp * n + 0.09 * band) * (1 + thump)

                let x = p.x * rad, y = p.y * rad, z = p.z * rad
                let x1 = x * ca + z * sa
                let z1 = -x * sa + z * ca
                let y2 = y * cp - z1 * sp
                let z2 = y * sp + z1 * cp

                let depth = clamp01((z2 / max(rad, 0.001) + 1) / 2)
                let persp = 1 + 0.18 * z2
                let px = Double(c.x) + x1 * R * persp
                let py = Double(c.y) + y2 * R * persp
                let dia = (1.15 + 1.7 * depth) * (0.4 + 0.6 * local) * (1 + 0.8 * band)
                let bucket = min(3, Int(depth * 4) + (band > 0.45 ? 1 : 0))
                layers[bucket].addEllipse(in: CGRect(x: px - dia / 2, y: py - dia / 2, width: dia, height: dia))
            }
        }
        let alphas = [0.22, 0.40, 0.65, 0.95]
        for i in 0..<4 {
            ctx.fill(layers[i], with: .color(ink.opacity(alphas[i])))
        }

        // Точка-зародыш: появляется в 0.10 и растворяется в сферу.
        let dotIn = clamp01((t - SplashTime.dot) / 0.12)
        let dotA = dotIn * (1 - clamp01(bloom * 2.2))
        if dotA > 0.01 {
            let r = 4.0 * (0.6 + 0.4 * easeOutBack(clamp01((t - SplashTime.dot) / 0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: r * 2, height: r * 2)),
                     with: .color(ink.opacity(dotA)))
        }

        // Тонкое кольцо, расходящееся от сферы в момент удара.
        if since >= 0 && u < 1 {
            let rr = R * (1.02 + 0.85 * easeOut(u))
            let ring = Path(ellipseIn: CGRect(x: Double(c.x) - rr, y: Double(c.y) - rr, width: rr * 2, height: rr * 2))
            ctx.stroke(ring, with: .color(ink.opacity(0.35 * (1 - u))), lineWidth: 1)
        }
    }
}

// MARK: - Вью

struct SplashView: View {
    @Binding var isFinished: Bool

    /// Момент старта сплэша: от него идёт весь таймлайн. Звук к нему подстраивается (см. SoundEngine.playStartup).
    @State private var origin: Date?

    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            TimelineView(.animation) { timeline in
                let t = origin.map { max(timeline.date.timeIntervalSince($0), 0) } ?? 0
                SplashScene(t: t)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { start() }
    }

    private func start() {
        guard origin == nil else { return }
        let now = Date()
        origin = now                                   // картинка стартует сразу, звук подхватывается синхронно
        SoundEngine.shared.playStartup(origin: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + SplashTime.total) {
            withAnimation(.easeInOut(duration: 0.3)) { isFinished = true }
        }
    }
}
