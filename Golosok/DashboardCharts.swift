import SwiftUI
import Charts

// MARK: - Диапазон времени

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return String(localized: "7 дней")
        case .month: return String(localized: "30 дней")
        case .all: return String(localized: "Всё время")
        }
    }

    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .all: return 84
        }
    }
}

// MARK: - Данные графиков

struct TimeOfDayStat: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int

    init(label: String, count: Int) {
        self.id = label
        self.label = label
        self.count = count
    }
}

struct TimelinePoint: Identifiable, Equatable {
    let id: Date
    let date: Date
    let chars: Int
    let minutes: Double
    let speedup: Double

    init(date: Date, chars: Int, minutes: Double, speedup: Double) {
        self.id = date
        self.date = date
        self.chars = chars
        self.minutes = minutes
        self.speedup = speedup
    }
}

struct SizeBucketStat: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int

    init(label: String, count: Int) {
        self.id = label
        self.label = label
        self.count = count
    }
}

struct ActivityPoint: Identifiable, Equatable {
    let id: Date
    let date: Date
    let count: Int

    init(date: Date, count: Int) {
        self.id = date
        self.date = date
        self.count = count
    }
}

struct LevelProgress: Equatable {
    let current: Int
    let nextThreshold: Int
    let nextLevel: String
    let isMaxed: Bool
}

// MARK: - Пустое состояние и шапка карточки

struct ChartEmptyView: View {
    var body: some View {
        Text("НЕТ ДАННЫХ")
            .font(UIStyleFont.body(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.uiMidGray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChartCardHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing

    init(title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    init(title: LocalizedStringKey) where Trailing == EmptyView {
        self.title = title
        self.trailing = EmptyView()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(UIStyleFont.body(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.uiMidGray)
            Spacer()
            if Trailing.self != EmptyView.self { trailing }
        }
    }
}

// MARK: - Кольцо «Когда вы говорите»

struct TimeOfDayChart: View {
    let stats: [TimeOfDayStat]
    let peak: String
    @State private var revealed = false

    private var total: Int { max(1, stats.reduce(0) { $0 + $1.count }) }
    private var peakIndex: Int {
        stats.enumerated().max(by: { $0.element.count < $1.element.count })?.offset ?? 0
    }
    private var palette: [Color] {
        [.uiInk, .uiInk.opacity(0.62), .uiInk.opacity(0.38), .uiInk.opacity(0.18)]
    }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                ChartCardHeader(title: "КОГДА ВЫ ГОВОРИТЕ")

                if stats.allSatisfy({ $0.count == 0 }) {
                    ChartEmptyView().frame(height: 110)
                } else {
                    HStack(spacing: 18) {
                        ring.frame(width: 106, height: 106)
                        legend
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(ringSegments.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start * (revealed ? 1.0 : 0.0), to: seg.end * (revealed ? 1.0 : 0.0))
                    .stroke(seg.color,
                            style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.easeOut(duration: 0.6), value: revealed)
        .overlay(
            VStack(spacing: 0) {
                Text(String(localized: "ПИК"))
                    .font(UIStyleFont.body(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.uiWarn)
                Text(LocalizedStringKey(peak))
                    .font(UIStyleFont.display(size: 16, weight: .bold))
                    .foregroundColor(.uiInk)
            }
        )
    }

    private var ringSegments: [(start: Double, end: Double, color: Color)] {
        var acc = 0.0
        var out: [(start: Double, end: Double, color: Color)] = []
        for i in stats.indices {
            let frac = Double(stats[i].count) / Double(total)
            out.append((acc, acc + frac, i == peakIndex ? Color.uiWarn : palette[i]))
            acc += frac
        }
        return out
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(stats.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Circle().fill(i == peakIndex ? Color.uiWarn : palette[i]).frame(width: 8, height: 8)
                    Text(LocalizedStringKey(stats[i].label))
                        .font(UIStyleFont.body(size: 11, weight: .semibold))
                        .foregroundColor(.uiInk)
                    Spacer()
                    Text("\(stats[i].count)")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .foregroundColor(.uiMidGray)
                }
            }
        }
        .frame(minWidth: 70)
    }
}

// MARK: - Темп (линия + площадь)

enum TempoMetric: String, CaseIterable {
    case chars = "Символы"
    case minutes = "Минуты"
    case speed = "Скорость"
}

struct TempoChart: View {
    let points: [TimelinePoint]
    @State private var metric: TempoMetric = .chars
    @State private var revealed = false

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                ChartCardHeader(title: "ВАШ ТЕМП") {
UIDropdownPicker(selection: $metric, options: TempoMetric.allCases.map { m in
                            .init(LocalizedStringKey(m.rawValue), value: m)
                        }, minWidth: 120)
                }

                if points.count < 2 {
                    ChartEmptyView().frame(height: 110)
                } else {
                    chart
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }

    private var chart: some View {
        Chart(Array(points.enumerated()), id: \.element.id) { index, point in
            let y = revealed ? value(for: point) : 0
            AreaMark(
                x: .value("Номер", index),
                y: .value("Показатель", y)
            )
            .foregroundStyle(Color.uiInk.opacity(0.12))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Номер", index),
                y: .value("Показатель", y)
            )
            .foregroundStyle(Color.uiInk)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)

            PointMark(
                x: .value("Номер", index),
                y: .value("Показатель", y)
            )
            .foregroundStyle(Color.uiInk)
            .symbolSize(16)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .animation(.easeOut(duration: 0.5), value: revealed)
        .frame(height: 110)
    }

    private func value(for point: TimelinePoint) -> Double {
        switch metric {
        case .chars: return Double(point.chars)
        case .minutes: return point.minutes
        case .speed: return point.speedup
        }
    }
}

// MARK: - Размер заметки (кольцо)

struct SizeDonutChart: View {
    let buckets: [SizeBucketStat]
    @State private var revealed = false

    private var total: Int { max(1, buckets.reduce(0) { $0 + $1.count }) }
    private var topIndex: Int {
        buckets.enumerated().max(by: { $0.element.count < $1.element.count })?.offset ?? 0
    }
    private var palette: [Color] {
        [.uiInk, .uiInk.opacity(0.62), .uiInk.opacity(0.38), .uiInk.opacity(0.18), .uiInk.opacity(0.08)]
    }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                ChartCardHeader(title: "РАЗМЕР ЗАМЕТКИ")

                if buckets.allSatisfy({ $0.count == 0 }) {
                    ChartEmptyView().frame(height: 110)
                } else {
                    HStack(spacing: 18) {
                        ring.frame(width: 106, height: 106)
                        legend
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }

    private var ring: some View {
        ZStack {
            ForEach(Array(ringSegments.enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start * (revealed ? 1.0 : 0.0), to: seg.end * (revealed ? 1.0 : 0.0))
                    .stroke(seg.color,
                            style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.easeOut(duration: 0.6), value: revealed)
        .overlay(
            VStack(spacing: 0) {
                Text(String(localized: "ЧАЩЕ"))
                    .font(UIStyleFont.body(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.uiWarn)
                Text(buckets[topIndex].label)
                    .font(UIStyleFont.display(size: 15, weight: .bold))
                    .foregroundColor(.uiInk)
            }
        )
    }

    private var ringSegments: [(start: Double, end: Double, color: Color)] {
        var acc = 0.0
        var out: [(start: Double, end: Double, color: Color)] = []
        for i in buckets.indices {
            let frac = Double(buckets[i].count) / Double(total)
            out.append((acc, acc + frac, i == topIndex ? Color.uiWarn : palette[i % palette.count]))
            acc += frac
        }
        return out
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(buckets.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Circle().fill(i == topIndex ? Color.uiWarn : palette[i % palette.count]).frame(width: 8, height: 8)
                    Text(buckets[i].label)
                        .font(UIStyleFont.body(size: 11, weight: .semibold))
                        .foregroundColor(.uiInk)
                    Spacer()
                    Text("\(buckets[i].count)")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .foregroundColor(.uiMidGray)
                }
            }
        }
        .frame(minWidth: 70)
    }
}

// MARK: - Ритм недели

struct WeekdayRhythmChart: View {
    let days: [DayTrendStat]
    @State private var revealed = false

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                ChartCardHeader(title: "РИТМ НЕДЕЛИ")

                if days.allSatisfy({ $0.count == 0 }) {
                    ChartEmptyView().frame(height: 120)
                } else {
                    Chart(days) { d in
                        BarMark(
                            x: .value("День", d.day),
                            y: .value("Заметки", revealed ? d.count : 0)
                        )
                        .foregroundStyle(Color.uiInk)
                        .cornerRadius(4)
                        .annotation(position: .top, alignment: .center) {
                            if d.count > 0 {
                                Text("\(revealed ? d.count : 0)")
                                    .font(UIStyleFont.body(size: 10, weight: .bold))
                                    .foregroundColor(.uiMidGray)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisValueLabel() {
                                if let str = value.as(String.self) {
                                    Text(str).font(UIStyleFont.body(size: 10, weight: .semibold)).foregroundColor(.uiMidGray)
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .animation(.easeOut(duration: 0.5), value: revealed)
                    .frame(height: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }
}

// MARK: - Активность

struct ActivityChart: View {
    let points: [ActivityPoint]
    let range: StatsRange
    @State private var revealed = false

    private var total: Int { points.reduce(0) { $0 + $1.count } }
    private var peak: Int { points.map(\.count).max() ?? 0 }
    private var yMax: Int { max(1, peak + 1) }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                ChartCardHeader(title: "АКТИВНОСТЬ") {
                    HStack(spacing: 6) {
                        Text("\(total)")
                            .font(UIStyleFont.display(size: 12, weight: .bold))
                            .foregroundColor(.uiInk)
                            .contentTransition(.numericText())
                        Text(String(localized: "ЗАМЕТОК"))
                            .font(UIStyleFont.body(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.uiMidGray)
                    }
                }

                if points.allSatisfy({ $0.count == 0 }) {
                    ChartEmptyView().frame(height: 210)
                } else {
                    Chart(points) { p in
                        AreaMark(
                            x: .value("Дата", p.date),
                            y: .value("Заметки", revealed ? p.count : 0)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.uiInk.opacity(0.35), Color.uiInk.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Дата", p.date),
                            y: .value("Заметки", revealed ? p.count : 0)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.uiInk)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        if p.count == peak && peak > 0 {
                            PointMark(
                                x: .value("Дата", p.date),
                                y: .value("Заметки", revealed ? p.count : 0)
                            )
                            .foregroundStyle(Color.uiWarn)
                            .symbolSize(100)
                            .annotation(position: .top, alignment: .center) {
                                Text("\(peak)")
                                    .font(UIStyleFont.body(size: 10, weight: .bold))
                                    .foregroundColor(.uiWarn)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.6))
                                    )
                            }
                        }
                    }
                    // Запас 25% по высоте убирает наложение текста на хедер
                    .chartYScale(domain: 0...(Double(yMax) * 1.25))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: xStride)) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(Self.dayFormatter.string(from: date))
                                        .font(UIStyleFont.body(size: 9, weight: .semibold))
                                        .foregroundColor(.uiMidGray)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.uiHairline)
                            AxisValueLabel {
                                if let n = value.as(Int.self) {
                                    Text("\(n)")
                                        .font(UIStyleFont.body(size: 9, weight: .semibold))
                                        .foregroundColor(.uiMidGray)
                                }
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.65), value: revealed)
                    .frame(height: 210)
                    .padding(.top, 10)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }

    private var xStride: Int {
        switch range {
        case .week: return 1
        case .month: return 7
        case .all: return 14
        }
    }

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "d MMM"
        return df
    }()
}

// MARK: - Последние заметки (множество полос)

struct RecentNotesChart: View {
    let points: [TimelinePoint]
    @State private var revealed = false

    private var totalChars: Int { points.reduce(0) { $0 + $1.chars } }
    private var peakIndex: Int {
        points.enumerated().max(by: { $0.element.chars < $1.element.chars })?.offset ?? 0
    }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 12) {
                ChartCardHeader(title: "ПОСЛЕДНИЕ ЗАМЕТКИ") {
                    Text(String(localized: "СИМВОЛОВ"))
                        .font(UIStyleFont.body(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.uiMidGray)
                    Text("\(totalChars)")
                        .font(UIStyleFont.display(size: 20, weight: .bold))
                        .foregroundColor(.uiInk)
                        .contentTransition(.numericText())
                }

                if points.isEmpty || points.allSatisfy({ $0.chars == 0 }) {
                    ChartEmptyView().frame(height: 120)
                } else {
                    Chart(Array(points.enumerated()), id: \.element.id) { index, point in
                        BarMark(
                            x: .value("Номер", index),
                            y: .value("Символы", revealed ? point.chars : 0),
                            width: .fixed(5)
                        )
                        .foregroundStyle(index == peakIndex ? Color.uiWarn : Color.uiInk.opacity(0.55))
                        .cornerRadius(1.5)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .animation(.easeOut(duration: 0.5), value: revealed)
                    .frame(height: 120)
                }

                HStack(spacing: 4) {
                    Text(String(localized: "НАЧАЛО ПЕРИОДА"))
                        .font(UIStyleFont.body(size: 9, weight: .medium))
                        .foregroundColor(.uiMidGray)
                    Spacer()
                    Text(String(localized: "СЕЙЧАС"))
                        .font(UIStyleFont.body(size: 9, weight: .medium))
                        .foregroundColor(.uiMidGray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }
}

// MARK: - Прогресс к уровню

struct LevelProgressChart: View {
    let progress: LevelProgress
    @State private var revealed = false

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 14) {
                ChartCardHeader(title: "ПРОГРЕСС К УРОВНЮ")

                if progress.isMaxed {
                    HStack(spacing: 10) {
                        Text("\(progress.current)")
                            .font(UIStyleFont.display(size: 30, weight: .bold))
                            .foregroundColor(.uiInk)
                        Text(String(localized: "ВЫ ДОСТИГЛИ ВЕРШИНЫ"))
                            .font(UIStyleFont.body(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.uiWarn)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text("\(progress.current)")
                                .font(UIStyleFont.display(size: 30, weight: .bold))
                                .foregroundColor(.uiInk)
                            Text("/ \(progress.nextThreshold)")
                                .font(UIStyleFont.body(size: 13, weight: .regular))
                                .foregroundColor(.uiMidGray)
                            Spacer()
                            Text("\(String(localized: "ОСТАЛОСЬ")) \(max(0, progress.nextThreshold - progress.current)) \(String(localized: "ДО")) \(progress.nextLevel)")
                                .font(UIStyleFont.body(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.uiWarn)
                        }

                        GeometryReader { geo in
                            let w = geo.size.width
                            let r = revealed ? ratio : 0.0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.uiInk.opacity(0.10)).frame(height: 6)
                                Capsule()
                                    .fill(Color.uiInk)
                                    .frame(width: max(4, min(w - 2, w * r)), height: 6)
                                Rectangle()
                                    .fill(Color.uiWarn)
                                    .frame(width: 2, height: 9)
                                    .offset(x: min(w - 2, w * r) - 1)
                            }
                        }
                        .frame(height: 9)
                        .animation(.easeOut(duration: 0.7), value: revealed)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { revealed = true }
    }

    private var ratio: Double {
        guard progress.nextThreshold > 0 else { return progress.isMaxed ? 1 : 0 }
        return min(1.0, Double(progress.current) / Double(progress.nextThreshold))
    }
}
