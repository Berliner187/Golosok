import SwiftUI

// MARK: - Палитра для Canvas
//
// В Canvas динамические цвета надёжнее подставлять явно, поэтому палитра собирается из colorScheme.
// `dark: true` — палитра для тёмной поверхности (светлый текст, яркий синий).

struct DashPalette {
    let ink: Color
    let soft: Color
    let faint: Color
    let signal: Color
    let background: Color

    init(dark: Bool) {
        if dark {
            ink = Color(hex: "#fafafa")
            soft = Color(hex: "#a1a1aa")
            faint = Color(hex: "#27272a")
            signal = Color(hex: "#3D8BFF")
            background = Color(hex: "#0a0a0a")
        } else {
            ink = Color(hex: "#0a0a0a")
            soft = Color(hex: "#737373")
            faint = Color(hex: "#e5e5e5")
            signal = Color(hex: "#0A5CFF")
            background = Color(hex: "#ffffff")
        }
    }
}

enum DashFormat {
    static func number(_ v: Int) -> String { v.formatted(.number) }

    static func delta(_ d: Double) -> String {
        let pct = Int((abs(d) * 100).rounded())
        return "\(d >= 0 ? "▲" : "▼") \(pct)%"
    }

    static func hourSpan(_ h: Int) -> String { String(format: "%02d:00–%02d:00", h, (h + 1) % 24) }
}

// MARK: - Мелкие элементы

struct DashLabel: View {
    let text: LocalizedStringKey
    var color: Color = .uiMidGray

    var body: some View {
        Text(text)
            .font(UIStyleFont.body(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(color)
    }
}

struct DashDeltaChip: View {
    let delta: Double
    let palette: DashPalette

    var body: some View {
        let up = delta >= 0
        let tint = up ? palette.signal : palette.soft
        Text(DashFormat.delta(delta))
            .font(UIStyleFont.body(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// Время в виде «12 ч 40 мин». Цифры меняются нативным numericText (работает внутри withAnimation).
struct DurationText: View {
    let minutes: Int
    let numberSize: CGFloat
    let unitSize: CGFloat
    let color: Color
    let unitColor: Color
    var tracking: CGFloat = -1

    var body: some View {
        let h = minutes / 60
        let m = minutes % 60
        HStack(alignment: .firstTextBaseline, spacing: numberSize * 0.24) {
            if h > 0 { group(h, "ч") }
            if h == 0 || m > 0 { group(m, "мин") }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func group(_ value: Int, _ unit: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: unitSize * 0.3) {
            Text("\(value)")
                .font(UIStyleFont.display(size: numberSize, weight: .bold))
                .tracking(tracking)
                .monospacedDigit()
                .foregroundColor(color)
                .contentTransition(.numericText())
            Text(unit)
                .font(UIStyleFont.body(size: unitSize, weight: .medium))
                .foregroundColor(unitColor)
        }
    }
}

/// Проигрывает «проявление» заново при смене `trigger` (например, диапазона), без мигания.
struct ReplayReveal<T: Equatable>: ViewModifier {
    let trigger: T
    @Binding var revealed: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { revealed = true }
            .onChange(of: trigger) {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { revealed = false }
                DispatchQueue.main.async { revealed = true }
            }
    }
}

// MARK: - Спарклайн (Canvas, проявляется слева направо)

struct DashSparkline: View, Animatable {
    let values: [Double]
    let line: Color
    let dots: Color
    var zeroBased = true
    var filled = true
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            guard w > 0, h > 0 else { return }

            // Фоновая точечная сетка — тот же язык, что и у сферы
            var grid = Path()
            var gx: CGFloat = 4
            while gx < w {
                for r in 1...3 {
                    let gy = h * CGFloat(r) / 4
                    grid.addEllipse(in: CGRect(x: gx - 0.7, y: gy - 0.7, width: 1.4, height: 1.4))
                }
                gx += 9
            }
            context.fill(grid, with: .color(dots.opacity(0.32)))

            guard values.count > 1 else { return }
            let hi = values.max() ?? 1
            let lo = zeroBased ? 0 : (values.min() ?? 0)
            let span = hi - lo
            let flat = span < 0.0001
            let padX: CGFloat = 10, padY: CGFloat = 8

            let pts: [CGPoint] = values.indices.map { i in
                let px = padX + (w - padX * 2) * CGFloat(i) / CGFloat(values.count - 1)
                let py = flat ? h / 2 : h - padY - CGFloat((values[i] - lo) / span) * (h - padY * 2)
                return CGPoint(x: px, y: py)
            }

            var path = Path()
            path.move(to: pts[0])
            for i in 0..<(pts.count - 1) {
                let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: min(max(p1.y + (p2.y - p0.y) / 6, 0), h))
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: min(max(p2.y - (p3.y - p1.y) / 6, 0), h))
                path.addCurve(to: p2, control1: c1, control2: c2)
            }

            let p = min(max(progress, 0), 1)
            var clipped = context
            clipped.clip(to: Path(CGRect(x: 0, y: 0, width: w * CGFloat(p), height: h)))

            if filled {
                var area = path
                area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
                area.addLine(to: CGPoint(x: pts[0].x, y: h))
                area.closeSubpath()
                clipped.fill(area, with: .linearGradient(
                    Gradient(colors: [line.opacity(0.32), line.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
            }
            clipped.stroke(path, with: .color(line.opacity(0.18)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            clipped.stroke(path, with: .color(line),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            let dotA = min(max((p - 0.9) / 0.1, 0), 1)
            if dotA > 0, let last = pts.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)),
                             with: .color(line.opacity(0.22 * dotA)))
                context.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)),
                             with: .color(line.opacity(dotA)))
            }
        }
    }
}

// MARK: - Тепловая карта точками

struct HeatPos: Equatable {
    let w: Int
    let d: Int
}

/// Единая геометрия для отрисовки и для определения ячейки под курсором.
struct HeatLayout {
    static let weeks = DashboardBuilder.heatWeeks
    /// ширина = (weeks + 1.3) · cw, высота = 0.9 · cw + 7 · 0.8 · cw = 6.5 · cw
    static let aspect: CGFloat = (CGFloat(DashboardBuilder.heatWeeks) + 1.3) / 6.5

    let cw: CGFloat
    let ch: CGFloat
    let labelW: CGFloat
    let topH: CGFloat

    init(size: CGSize) {
        cw = size.width / (CGFloat(Self.weeks) + 1.3)
        ch = cw * 0.8
        labelW = cw * 1.3
        topH = cw * 0.9
    }

    var maxRadius: CGFloat { min(cw, ch) * 0.36 }

    func center(_ w: Int, _ d: Int) -> CGPoint {
        CGPoint(x: labelW + (CGFloat(w) + 0.5) * cw, y: topH + (CGFloat(d) + 0.5) * ch)
    }

    func position(at p: CGPoint) -> HeatPos? {
        guard p.x >= labelW, p.y >= topH else { return nil }
        let w = Int((p.x - labelW) / cw)
        let d = Int((p.y - topH) / ch)
        guard w >= 0, w < Self.weeks, d >= 0, d < 7 else { return nil }
        return HeatPos(w: w, d: d)
    }
}

struct HeatmapCanvas: View, Animatable {
    let weeks: [HeatWeek]
    let maxCount: Int
    let hover: HeatPos?
    let palette: DashPalette
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let monthSymbols: [String] = DateFormatter().shortMonthSymbols ?? []
    private static let weekdaySymbols: [String] = Calendar.current.shortWeekdaySymbols

    private static func level(_ count: Int, _ top: Int) -> Int {
        guard count > 0, top > 0 else { return 0 }
        return max(1, Int((Double(count) / Double(top) * 4).rounded(.up)))
    }

    var body: some View {
        Canvas { context, size in
            let L = HeatLayout(size: size)
            let maxR = L.maxRadius
            let factors: [CGFloat] = [0.16, 0.42, 0.62, 0.82, 1.0]
            var levels = [Path](repeating: Path(), count: 5)

            for (wi, week) in weeks.enumerated() {
                // Волна проявления слева направо
                let local = min(max(progress * 1.5 - Double(wi) / Double(HeatLayout.weeks) * 0.5, 0), 1)
                let e = CGFloat(1 - pow(1 - local, 3))
                for (di, day) in week.days.enumerated() where !day.isFuture {
                    let lv = min(4, Self.level(day.count, maxCount))
                    let r = maxR * factors[lv] * e
                    let c = L.center(wi, di)
                    levels[lv].addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
            }
            let fills: [Color] = [
                palette.ink.opacity(0.14),
                palette.signal.opacity(0.30), palette.signal.opacity(0.52),
                palette.signal.opacity(0.76), palette.signal
            ]
            for i in 0..<5 { context.fill(levels[i], with: .color(fills[i])) }

            if let h = hover {
                let c = L.center(h.w, h.d)
                let r = maxR * 1.35
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(palette.ink.opacity(0.55)), lineWidth: 1.2)
            }

            // Подписи: месяцы сверху, дни недели слева
            let fontSize = max(8, L.cw * 0.36)
            var lastMonth = -1
            var lastLabelWeek = -10
            for (wi, week) in weeks.enumerated() {
                guard let first = week.days.first else { continue }
                let m = Calendar.current.component(.month, from: first.date)
                if m != lastMonth {
                    if wi - lastLabelWeek >= 3, m >= 1, m <= Self.monthSymbols.count {
                        context.draw(
                            Text(Self.monthSymbols[m - 1]).font(.system(size: fontSize, weight: .medium)).foregroundColor(palette.soft),
                            at: CGPoint(x: L.labelW + CGFloat(wi) * L.cw, y: L.topH * 0.5), anchor: .leading)
                        lastLabelWeek = wi
                    }
                    lastMonth = m
                }
            }
            for d in [0, 2, 4] {
                context.draw(
                    Text(Self.weekdaySymbols[(d + 1) % 7]).font(.system(size: fontSize, weight: .medium)).foregroundColor(palette.soft),
                    at: CGPoint(x: 0, y: L.topH + (CGFloat(d) + 0.5) * L.ch), anchor: .leading)
            }
        }
    }
}

struct DashHeatmapCard: View {
    let stats: DashboardStats
    @Environment(\.colorScheme) private var scheme
    @State private var revealed = false
    @State private var hover: HeatPos?

    var body: some View {
        let pal = DashPalette(dark: scheme == .dark)
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    DashLabel(text: "АКТИВНОСТЬ")
                    Spacer()
                    legend(pal)
                }
                HeatmapCanvas(weeks: stats.heat, maxCount: stats.heatMax, hover: hover, palette: pal,
                              progress: revealed ? 1 : 0)
                    .animation(.easeOut(duration: 1.0), value: revealed)
                    .aspectRatio(HeatLayout.aspect, contentMode: .fit)
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let p): hover = HeatLayout(size: geo.size).position(at: p)
                                    case .ended: hover = nil
                                    }
                                }
                        }
                    )
                Text(caption)
                    .font(UIStyleFont.body(size: 12, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .monospacedDigit()
                    .frame(height: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(ReplayReveal(trigger: stats.range, revealed: $revealed))
    }

    private var caption: String {
        if let h = hover, stats.heat.indices.contains(h.w), stats.heat[h.w].days.indices.contains(h.d) {
            let day = stats.heat[h.w].days[h.d]
            if !day.isFuture {
                let date = day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                return String(format: String(localized: "%@ · заметок: %d"), date, day.count)
            }
        }
        return String(format: String(localized: "Активных дней: %d из %d"), stats.heatActiveDays, stats.heatElapsedDays)
    }

    private func legend(_ pal: DashPalette) -> some View {
        HStack(spacing: 6) {
            Text("меньше").font(UIStyleFont.body(size: 10, weight: .regular)).foregroundColor(.uiMidGray)
            ForEach(0..<5, id: \.self) { i in
                let size: CGFloat = [3, 5, 7, 9, 11][i]
                Circle()
                    .fill(i == 0 ? pal.ink.opacity(0.14) : pal.signal.opacity([0, 0.30, 0.52, 0.76, 1.0][i]))
                    .frame(width: size, height: size)
            }
            Text("больше").font(UIStyleFont.body(size: 10, weight: .regular)).foregroundColor(.uiMidGray)
        }
    }
}

// MARK: - Время суток (24 столбца)

struct HourlyCanvas: View, Animatable {
    let counts: [Int]
    let peak: Int?
    let hover: Int?
    let palette: DashPalette
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let labelH: CGFloat = 16
            let w = size.width
            let h = size.height - labelH
            guard w > 0, h > 8, counts.count == 24 else { return }
            let slot = w / 24
            let barW = slot * 0.56
            let maxC = CGFloat(max(counts.max() ?? 1, 1))

            for i in 0..<24 {
                let local = min(max(progress * 1.6 - Double(i) / 24.0 * 0.6, 0), 1)
                let e = CGFloat(1 - pow(1 - local, 3))
                let frac = CGFloat(counts[i]) / maxC
                let bh = 3 + (h - 7) * frac * e
                let rect = CGRect(x: slot * CGFloat(i) + (slot - barW) / 2, y: h - bh, width: barW, height: bh)
                let color: Color
                if i == peak { color = palette.signal }
                else if i == hover { color = palette.ink.opacity(0.55) }
                else { color = palette.ink.opacity(counts[i] == 0 ? 0.08 : 0.2) }
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(color))
            }
            for hr in [0, 6, 12, 18] {
                context.draw(
                    Text("\(hr)").font(.system(size: 10, weight: .medium)).foregroundColor(palette.soft),
                    at: CGPoint(x: slot * (CGFloat(hr) + 0.5), y: h + labelH * 0.62), anchor: .center)
            }
        }
    }
}

struct DashHourlyCard: View {
    let stats: DashboardStats
    @Environment(\.colorScheme) private var scheme
    @State private var revealed = false
    @State private var hover: Int?

    var body: some View {
        let pal = DashPalette(dark: scheme == .dark)
        UICard {
            VStack(alignment: .leading, spacing: 12) {
                DashLabel(text: "КОГДА ВЫ ГОВОРИТЕ")
                HourlyCanvas(counts: stats.hourly, peak: stats.peakHour, hover: hover, palette: pal,
                             progress: revealed ? 1 : 0)
                    .animation(.easeOut(duration: 0.9), value: revealed)
                    .frame(height: 104)
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let p):
                                        hover = min(23, max(0, Int(p.x / (geo.size.width / 24))))
                                    case .ended:
                                        hover = nil
                                    }
                                }
                        }
                    )
                Text(caption)
                    .font(UIStyleFont.body(size: 12, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .monospacedDigit()
                    .frame(height: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .modifier(ReplayReveal(trigger: stats.range, revealed: $revealed))
    }

    private var caption: String {
        if let h = hover, stats.hourly.indices.contains(h) {
            return String(format: String(localized: "%@ · заметок: %d"), DashFormat.hourSpan(h), stats.hourly[h])
        }
        if let p = stats.peakHour { return String(format: String(localized: "Пик: %@"), DashFormat.hourSpan(p)) }
        return "—"
    }
}

// MARK: - Скорость распознавания

struct DashSpeedCard: View {
    let stats: DashboardStats
    @Environment(\.colorScheme) private var scheme
    @State private var revealed = false

    var body: some View {
        let pal = DashPalette(dark: scheme == .dark)
        UICard {
            VStack(alignment: .leading, spacing: 12) {
                DashLabel(text: "СКОРОСТЬ РАСПОЗНАВАНИЯ")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stats.speedAvg.map { "×\(Int($0.rounded()))" } ?? "—")
                        .font(UIStyleFont.display(size: 44, weight: .bold))
                        .tracking(-1.5)
                        .monospacedDigit()
                        .foregroundColor(.uiInk)
                    Text("быстрее речи")
                        .font(UIStyleFont.body(size: 12, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
                Spacer(minLength: 4)
                DashSparkline(values: stats.speedSeries, line: pal.signal, dots: pal.soft,
                              zeroBased: false, filled: false, progress: revealed ? 1 : 0)
                    .animation(.easeOut(duration: 1.0), value: revealed)
                    .frame(height: 64)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .modifier(ReplayReveal(trigger: stats.range, revealed: $revealed))
    }
}

// MARK: - Метрики

struct DashKPICard<Value: View>: View {
    let title: LocalizedStringKey
    var delta: Double? = nil
    var note: String? = nil
    let value: Value
    @Environment(\.colorScheme) private var scheme

    init(title: LocalizedStringKey, delta: Double? = nil, note: String? = nil, @ViewBuilder value: () -> Value) {
        self.title = title
        self.delta = delta
        self.note = note
        self.value = value()
    }

    var body: some View {
        let pal = DashPalette(dark: scheme == .dark)
        UICard {
            VStack(alignment: .leading, spacing: 10) {
                DashLabel(text: title)
                value
                Group {
                    if let d = delta {
                        DashDeltaChip(delta: d, palette: pal)
                    } else if let note {
                        Text(note)
                            .font(UIStyleFont.body(size: 11, weight: .regular))
                            .foregroundColor(.uiMidGray)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 20, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DashNumberValue: View {
    let value: Int
    var unit: LocalizedStringKey? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(DashFormat.number(value))
                .font(UIStyleFont.display(size: 28, weight: .bold))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundColor(.uiInk)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(UIStyleFont.body(size: 13, weight: .medium))
                    .foregroundColor(.uiMidGray)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: - Выводы

struct DashInsightsCard: View {
    let insights: [DashboardInsight]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = DashPalette(dark: scheme == .dark)
        UICard {
            VStack(alignment: .leading, spacing: 12) {
                DashLabel(text: "ВЫВОДЫ")
                if insights.isEmpty {
                    Text("Надиктуйте первую заметку — здесь появятся выводы")
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiMidGray)
                } else {
                    ForEach(insights) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(pal.signal)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(pal.signal.opacity(0.14)))
                            Text(item.text)
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Главная карточка

struct DashHeroCard: View {
    let stats: DashboardStats
    @Environment(\.colorScheme) private var scheme
    @State private var shown = 0
    @State private var revealed = false

    private var target: Int { Int(stats.savedMinutes.rounded()) }

    private var subtitle: String {
        if stats.notes == 0 { return String(localized: "Здесь появится статистика после первой диктовки") }
        let pages = Int((Double(stats.words) / 300).rounded())
        return String(format: String(localized: "%d слов · ≈ %d стр. А4"), stats.words, pages)
    }

    var body: some View {
        // Инверсия: тёмная карточка на светлой теме и светлая на тёмной
        let pal = DashPalette(dark: scheme != .dark)
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DashLabel(text: "СЭКОНОМЛЕНО ВРЕМЕНИ", color: pal.soft)
                Spacer()
                if let d = stats.deltaSaved {
                    DashDeltaChip(delta: d, palette: pal)
                    Text("к прошлому периоду")
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(pal.soft)
                } else if stats.range == .all {
                    Text("за всё время")
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(pal.soft)
                }
            }
            DurationText(minutes: shown, numberSize: 64, unitSize: 20, color: pal.ink, unitColor: pal.soft, tracking: -2.5)
                .padding(.top, 10)
            Text(subtitle)
                .font(UIStyleFont.body(size: 13, weight: .regular))
                .foregroundColor(pal.soft)
                .monospacedDigit()
                .padding(.top, 6)
            DashSparkline(values: stats.savedSeries, line: pal.signal, dots: pal.soft,
                          zeroBased: true, filled: true, progress: revealed ? 1 : 0)
                .animation(.easeOut(duration: 1.1), value: revealed)
                .frame(height: 96)
                .padding(.top, 18)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                shape.fill(pal.background)
                RadialGradient(colors: [pal.signal.opacity(0.22), .clear], center: .bottomTrailing,
                               startRadius: 0, endRadius: 380)
                    .clipShape(shape)
            }
        )
        .overlay(shape.stroke(Color.uiHairline, lineWidth: 1))
        .onAppear { withAnimation(.smooth(duration: 1.0)) { shown = target } }
        .onChange(of: target) { withAnimation(.smooth(duration: 0.6)) { shown = target } }
        .modifier(ReplayReveal(trigger: stats.range, revealed: $revealed))
    }
}
