import SwiftUI
import Charts

struct DayTrendStat: Identifiable, Equatable {
    let id: String
    let day: String
    let count: Int
    let chars: Int

    init(day: String, count: Int, chars: Int) {
        self.id = day
        self.day = day
        self.count = count
        self.chars = chars
    }
}

enum TrendMetric {
    case notes
    case characters
}

struct DashboardCalculator: Equatable {
    let hoursSaved: String
    let aiPower: String
    let levelName: String
    let a4Pages: String
    let peakActivity: String
    let wpm: Int
    let totalMinutes: String
    let totalNotes: Int
    let avgLength: Int
    let weeklyTrend: [DayTrendStat]
    let timeOfDay: [TimeOfDayStat]
    let timeline: [TimelinePoint]
    let sizeHistogram: [SizeBucketStat]
    let weekdayAggregate: [DayTrendStat]
    let activity: [ActivityPoint]
    let savedTrend: [TimelinePoint]
    let recentNotes: [TimelinePoint]
    let levelProgress: LevelProgress
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy, HH:mm"
        return df
    }()
    
    static var empty: DashboardCalculator {
        let daysLabels = [String(localized: "ПН"), String(localized: "ВТ"), String(localized: "СР"), String(localized: "ЧТ"), String(localized: "ПТ"), String(localized: "СБ"), String(localized: "ВС")]
        return DashboardCalculator(
            hoursSaved: "0.00", aiPower: "35.0x", levelName: String(localized: "НОВИЧОК"), a4Pages: "0", peakActivity: String(localized: "НЕТ ДАННЫХ"),
            wpm: 0, totalMinutes: "0.0", totalNotes: 0, avgLength: 0,
            weeklyTrend: daysLabels.map { DayTrendStat(day: $0, count: 0, chars: 0) },
            timeOfDay: DashboardCalculator.emptyTimeOfDay,
            timeline: [],
            sizeHistogram: DashboardCalculator.emptySizeHistogram,
            weekdayAggregate: daysLabels.map { DayTrendStat(day: $0, count: 0, chars: 0) },
            activity: [],
            savedTrend: [],
            recentNotes: [],
            levelProgress: LevelProgress(current: 0, nextThreshold: 6, nextLevel: String(localized: "ПОЛЬЗОВАТЕЛЬ"), isMaxed: false)
        )
    }

    static var emptyTimeOfDay: [TimeOfDayStat] {
        [String(localized: "УТРО"), String(localized: "ДЕНЬ"), String(localized: "ВЕЧЕР"), String(localized: "НОЧЬ")]
            .map { TimeOfDayStat(label: $0, count: 0) }
    }

    static let sizeBucketLabels: [String] = ["<100", "100-300", "300-800", "800-2000", "2000+"]

    static var emptySizeHistogram: [SizeBucketStat] {
        sizeBucketLabels.map { SizeBucketStat(label: $0, count: 0) }
    }

    private static let levelThresholds: [(Int, String)] = [
        (6, "ПОЛЬЗОВАТЕЛЬ"), (21, "ЛЮБИТЕЛЬ"), (51, "ОПЫТНЫЙ"), (101, "СПЕЦИАЛИСТ"),
        (251, "ЭКСПЕРТ"), (501, "ПРОФИ"), (1001, "МАСТЕР"), (2501, "ВИРТУОЗ"), (5001, "ЛЕГЕНДА")
    ]
    
    static func calculate(from history: [TranscriptionItem], range: StatsRange = .all) -> DashboardCalculator {
        let daysLabels = [String(localized: "ПН"), String(localized: "ВТ"), String(localized: "СР"), String(localized: "ЧТ"), String(localized: "ПТ"), String(localized: "СБ"), String(localized: "ВС")]
        
        if history.isEmpty { return empty }
        
        // ---- один проход по истории: копим всё, что нужно агрегатам ----
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: Date())
        let cutoff: Date = range == .all ? .distantPast : Date().addingTimeInterval(-Double(range.dayCount) * 24 * 3600)
        let todayStart = Calendar.current.startOfDay(for: Date())

        var totalChars = 0
        var totalWords = 0
        var totalSecs: Double = 0.0
        var m = 0, d = 0, e = 0, n = 0
        var todRange = [0, 0, 0, 0]
        var dayCounts = [0, 0, 0, 0, 0, 0, 0]
        var dayChars = [0, 0, 0, 0, 0, 0, 0]
        var weekdayCounts = [0, 0, 0, 0, 0, 0, 0]
        var histCounts = [0, 0, 0, 0, 0]
        var activityCounts: [Date: Int] = [:]
        var savedByDay: [Date: Double] = [:]
        var speedups: [Double] = []
        var recorded: [(date: Date, chars: Int, secs: Double, speedup: Double)] = []
        recorded.reserveCapacity(history.count)

        for item in history {
            let cleaned = item.duration
                .replacingOccurrences(of: " сек", with: "").replacingOccurrences(of: " мин", with: "")
                .replacingOccurrences(of: " sec", with: "").replacingOccurrences(of: " min", with: "")
            let isMinutes = item.duration.contains("мин") || item.duration.contains("min")
            let secs = (Double(cleaned) ?? 2.5) * (isMinutes ? 60 : 1)
            totalSecs += secs
            totalChars += item.text.count
            totalWords += item.text.split(separator: " ").count
            if let s = item.speedup, s > 0 { speedups.append(s) }

            guard let date = dateFormatter.date(from: item.date) else { continue }
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 6..<12: m += 1
            case 12..<18: d += 1
            case 18..<24: e += 1
            default: n += 1
            }
            let weekday = (Calendar.current.component(.weekday, from: date) + 5) % 7
            if let currentWeekInterval, currentWeekInterval.contains(date) {
                dayCounts[weekday] += 1
                dayChars[weekday] += item.text.count
            }

            guard date >= cutoff else { continue }
            let bucket = hour < 6 ? 3 : (hour < 12 ? 0 : (hour < 18 ? 1 : 2))
            todRange[bucket] += 1
            weekdayCounts[weekday] += 1
            let c = item.text.count
            if c < 100 { histCounts[0] += 1 }
            else if c < 300 { histCounts[1] += 1 }
            else if c < 800 { histCounts[2] += 1 }
            else if c < 2000 { histCounts[3] += 1 }
            else { histCounts[4] += 1 }
            let day = Calendar.current.startOfDay(for: date)
            activityCounts[day, default: 0] += 1
            let daySaved = max(0.0, ((Double(c) / 200.0) - (secs / 60.0)) / 60.0)
            savedByDay[day, default: 0.0] += daySaved
            recorded.append((date: date, chars: c, secs: secs, speedup: item.speedup ?? 1))
        }
        
        let count = history.count
        let avgChars = totalChars / max(1, count)
        let a4Count = Double(totalChars) / 1800.0
        
        let level: String
        switch count {
        case 0...5:       level = String(localized: "НОВИЧОК")
        case 6...20:      level = String(localized: "ПОЛЬЗОВАТЕЛЬ")
        case 21...50:     level = String(localized: "ЛЮБИТЕЛЬ")
        case 51...100:    level = String(localized: "ОПЫТНЫЙ")
        case 101...250:   level = String(localized: "СПЕЦИАЛИСТ")
        case 251...500:   level = String(localized: "ЭКСПЕРТ")
        case 501...1000:  level = String(localized: "ПРОФИ")
        case 1001...2500: level = String(localized: "МАСТЕР")
        case 2501...5000: level = String(localized: "ВИРТУОЗ")
        default:          level = String(localized: "ЛЕГЕНДА")
        }
        
        let peak: String
        let maxActivity = max(m, d, e, n)
        if maxActivity == m { peak = String(localized: "УТРО") } else if maxActivity == d { peak = String(localized: "ДЕНЬ") } else if maxActivity == e { peak = String(localized: "ВЕЧЕР") } else { peak = String(localized: "НОЧЬ") }
        
        let totalMins = totalSecs / 60.0
        let savedHours = max(0.0, ((Double(totalChars) / 200.0) - totalMins) / 60.0)
        let calculatedWpm = totalMins > 0 ? Int(Double(totalWords) / totalMins) : 160
        let avgSpeedup = speedups.isEmpty ? 35.0 : (speedups.reduce(0, +) / Double(speedups.count))

        let trend = daysLabels.enumerated().map { DayTrendStat(day: $1, count: dayCounts[$0], chars: dayChars[$0]) }
        let timeOfDay = [String(localized: "УТРО"), String(localized: "ДЕНЬ"), String(localized: "ВЕЧЕР"), String(localized: "НОЧЬ")]
            .enumerated().map { TimeOfDayStat(label: $1, count: todRange[$0]) }
        let weekdayAggregate = daysLabels.enumerated().map { DayTrendStat(day: $1, count: weekdayCounts[$0], chars: 0) }
        let sizeHistogram = DashboardCalculator.sizeBucketLabels.enumerated().map { SizeBucketStat(label: $1, count: histCounts[$0]) }

        let sortedRecorded = recorded.sorted { $0.date < $1.date }
        let timeline = sortedRecorded
            .suffix(20)
            .map { TimelinePoint(date: $0.date, chars: $0.chars, minutes: $0.secs / 60.0, speedup: $0.speedup) }
        let recentNotes = Array(sortedRecorded
            .suffix(48)
            .map { TimelinePoint(date: $0.date, chars: $0.chars, minutes: $0.secs / 60.0, speedup: $0.speedup) })

        let activity = (0..<range.dayCount).map { i in
            let day = Calendar.current.date(byAdding: .day, value: -(range.dayCount - 1 - i), to: todayStart) ?? todayStart
            return ActivityPoint(date: day, count: activityCounts[day] ?? 0)
        }

        let savedTrend = (0..<range.dayCount).map { i in
            let day = Calendar.current.date(byAdding: .day, value: -(range.dayCount - 1 - i), to: todayStart) ?? todayStart
            return TimelinePoint(date: day, chars: 0, minutes: savedByDay[day] ?? 0, speedup: 0)
        }

        let levelProgress: LevelProgress
        if let next = levelThresholds.first(where: { $0.0 > count }) {
            levelProgress = LevelProgress(current: count, nextThreshold: next.0, nextLevel: NSLocalizedString(next.1, comment: ""), isMaxed: false)
        } else {
            levelProgress = LevelProgress(current: count, nextThreshold: count, nextLevel: NSLocalizedString("ЛЕГЕНДА", comment: ""), isMaxed: true)
        }

        return DashboardCalculator(
            hoursSaved: String(format: "%.2f", savedHours),
            aiPower: String(format: "%.1fx", avgSpeedup),
            levelName: level,
            a4Pages: String(format: "%.1f", a4Count),
            peakActivity: peak,
            wpm: max(130, min(210, calculatedWpm)),
            totalMinutes: String(format: "%.1f", totalMins),
            totalNotes: count,
            avgLength: avgChars,
            weeklyTrend: trend,
            timeOfDay: timeOfDay,
            timeline: Array(timeline),
            sizeHistogram: sizeHistogram,
            weekdayAggregate: weekdayAggregate,
            activity: activity,
            savedTrend: savedTrend,
            recentNotes: recentNotes,
            levelProgress: levelProgress
        )
    }
}

struct DashboardView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @State private var chartRange: StatsRange = .week
    @State private var stats: DashboardCalculator = DashboardCalculator.empty
    
    let cardBackground = Color.dynamic(light: "#0a0a0a", dark: "#ffffff")
    let primaryTextColor = Color.dynamic(light: "#ffffff", dark: "#0a0a0a")
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("УРОВЕНЬ:")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.uiMidGray)
                    UIBadge(text: stats.levelName)
                    
                    Spacer()
                    if let update = audioCapture.updateInfo {
                        HStack(spacing: 6) {
                            if audioCapture.isDownloadingUpdate {
                                ProgressView().scaleEffect(0.6)
                                Text(audioCapture.updateProgressText.isEmpty ? LocalizedStringKey("Скачивание...") : LocalizedStringKey(audioCapture.updateProgressText))
                                    .font(UIStyleFont.body(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                Button(action: { audioCapture.cancelUpdateDownload() }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.8))
                                }.buttonStyle(.plain)
                            } else {
                                Button(action: { audioCapture.downloadAndInstallUpdate() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text(String(format: String(localized: "Доступна %@"), update.codename))
                                    }
                                    .font(UIStyleFont.body(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.uiWarn).cornerRadius(12)
                    }
                }
                
                // ГЛАВНАЯ КАРТОЧКА
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AnimatedNumberText(
                            value: stats.hoursSaved.replacingOccurrences(of: ".", with: ","),
                            size: 44,
                            tint: primaryTextColor
                        )
                        
                        if stats.hoursSaved != "0" && stats.hoursSaved != "0.00" && stats.hoursSaved != "0,00" {
                            Text("ЧАСОВ СОХРАНЕНО")
                                .font(UIStyleFont.body(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundColor(primaryTextColor.opacity(0.7))
                        }
                    }

                    if !stats.savedTrend.isEmpty {
                        HeroSparkline(points: stats.savedTrend, tint: primaryTextColor)
                            .frame(height: 64)
                            .padding(.top, 4)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .cornerRadius(24)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.uiHairline, lineWidth: 1))
                
                DashboardChartsSection(stats: stats, chartRange: $chartRange)
                    .equatable()
            }
            .padding(20)
        }
        .background(Color.uiCanvas)
        .onAppear { apply() }
        .onChange(of: audioCapture.history.count) { _ in apply() }
        .onChange(of: chartRange) { _ in apply() }
    }
    
    private func apply() {
        let store = DashboardStatsStore.shared
        let s = store.value(for: audioCapture.history, range: chartRange)
        if s != stats { stats = s }
        store.refresh(history: audioCapture.history)
    }
}

final class DashboardStatsStore: ObservableObject {
    static let shared = DashboardStatsStore()
    @Published private(set) var byRange: [StatsRange: DashboardCalculator] = [:]
    private var computedSignature = 0
    private let queue = DispatchQueue(label: "golosok.dashboard.calc", qos: .utility)

    func value(for history: [TranscriptionItem], range: StatsRange) -> DashboardCalculator {
        if let s = byRange[range] { return s }
        return DashboardCalculator.calculate(from: history, range: range)
    }

    func refresh(history: [TranscriptionItem]) {
        var hasher = Hasher()
        hasher.combine(history.count)
        if let first = history.first { hasher.combine(first.id); hasher.combine(first.date) }
        hasher.combine(history.last?.id)
        let sig = hasher.finalize()
        guard sig != computedSignature else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var next: [StatsRange: DashboardCalculator] = [:]
            for r in StatsRange.allCases {
                next[r] = DashboardCalculator.calculate(from: history, range: r)
            }
            DispatchQueue.main.async {
                guard self.computedSignature != sig else { return }
                self.computedSignature = sig
                self.byRange = next
            }
        }
    }
}

struct DashboardChartsSection: View, Equatable {
    let stats: DashboardCalculator
    @Binding var chartRange: StatsRange
    @State private var trendMetric: TrendMetric = .notes
    @State private var revealed = false
    
    static func == (lhs: DashboardChartsSection, rhs: DashboardChartsSection) -> Bool {
        lhs.stats == rhs.stats && lhs.chartRange == rhs.chartRange
    }
    
    var body: some View {
        LazyVStack(spacing: 16) {
            // ПЕРЕКЛЮЧАТЕЛЬ ДИАПАЗОНА
            HStack(spacing: 12) {
                Text("ДИАПАЗОН")
                    .font(UIStyleFont.body(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.uiMidGray)
                Spacer()
                Picker("", selection: $chartRange) {
                    ForEach(StatsRange.allCases) { r in
                        Text(r.title).tag(r)
                    }
                }
                .labelsHidden()
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 240)
            }
            
            // ГРАФИК (НЕДЕЛЬНЫЙ ТРЕНД)
            UICard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("НЕДЕЛЬНЫЙ ТРЕНД")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(.uiMidGray)
                        
                        Spacer()
                        
                        Picker("", selection: $trendMetric) {
                            Text("Заметки").tag(TrendMetric.notes)
                            Text("Символы").tag(TrendMetric.characters)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 160)
                    }
                    
                    Chart(stats.weeklyTrend) { item in
                        let yVal = revealed ? ((trendMetric == .notes) ? item.count : item.chars) : 0
                        
                        BarMark(
                            x: .value("День", item.day),
                            y: .value("Показатель", yVal)
                        )
                        .foregroundStyle(Color.uiInk)
                        .cornerRadius(4)
                        .annotation(position: .top, alignment: .center) {
                            if yVal > 0 {
                                Text("\(yVal)")
                                    .font(UIStyleFont.body(size: 10, weight: .bold))
                                    .foregroundColor(.uiMidGray)
                            }
                        }
                    }
                    .frame(height: 120)
                    .id(trendMetric)
                    .animation(.easeOut(duration: 0.5), value: revealed)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisValueLabel() {
                                if let str = value.as(String.self) {
                                    Text(str).font(UIStyleFont.body(size: 11, weight: .semibold)).foregroundColor(.uiMidGray)
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                }
            }
            
            // АКТИВНОСТЬ (линейный график)
            ActivityChart(points: stats.activity, range: chartRange)
            
            // ГРАФИКИ (2 КОЛОНКИ)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                TimeOfDayChart(stats: stats.timeOfDay, peak: stats.peakActivity)
                TempoChart(points: stats.timeline)
                WeekdayRhythmChart(days: stats.weekdayAggregate)
                SizeDonutChart(buckets: stats.sizeHistogram)
            }
            
            // ПОСЛЕДНИЕ ЗАМЕТКИ (полосы на всю ширину)
            RecentNotesChart(points: stats.recentNotes)
            
            // ПРОГРЕСС К УРОВНЮ (на всю ширину)
            LevelProgressChart(progress: stats.levelProgress)
            
            // МЕТРИКИ
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(value: stats.aiPower, label: "МОЩНОСТЬ ИИ")
                StatCard(value: "\(stats.totalNotes)", label: "ВСЕГО ЗАМЕТОК")
                StatCard(value: stats.totalMinutes, label: "НАГОВОРИЛИ (МИН)")
                StatCard(value: stats.a4Pages, label: "СТРАНИЦ А4")
                StatCard(value: "\(stats.wpm)", label: "WPM (ТЕМП)")
                StatCard(value: stats.peakActivity, label: "ПИК АКТИВНОСТИ")
            }
            
            // ФУТЕР
            HStack {
                Text("ГОЛОСОК ™2026")
                    .font(UIStyleFont.body(size: 10, weight: .bold))
                    .foregroundColor(Color.dynamic(light: "#ffffff", dark: "#0a0a0a"))
                Spacer()
                Text("Design by Kozak")
                    .font(UIStyleFont.body(size: 10, weight: .regular))
                    .foregroundColor(Color.dynamic(light: "#ffffff", dark: "#0a0a0a"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.dynamic(light: "#0a0a0a", dark: "#ffffff"))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.uiHairline, lineWidth: 1))
        }
        .onAppear { revealed = true }
    }
}

struct StatCard: View {
    let value: String
    let label: LocalizedStringKey
    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 6) {
                Text(value)
                    .font(UIStyleFont.display(size: 26, weight: .bold))
                    .foregroundColor(.uiInk)
                    .tracking(-0.5)
                Text(label)
                    .font(UIStyleFont.body(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.uiMidGray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AnimatedNumberText: View {
    let value: String
    let size: CGFloat
    let tint: Color
    @State private var displayed: Double = 0

    private var target: Double { max(0, Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0) }

    var body: some View {
        Text(String(format: "%.2f", displayed))
            .font(UIStyleFont.display(size: size, weight: .bold))
            .foregroundColor(tint)
            .tracking(-1.5)
            .monospacedDigit()
            .task(id: target) {
                let from = displayed
                let to = target
                guard abs(from - to) > 0.001 else {
                    displayed = to
                    return
                }
                let seconds = 0.8
                let steps = 60
                for i in 1...steps {
                    let t = Double(i) / Double(steps)
                    let eased = 1 - pow(1 - t, 3)
                    displayed = from + (to - from) * eased
                    if t < 1 { try? await Task.sleep(nanoseconds: UInt64(seconds / Double(steps) * 1e9)) }
                }
                displayed = to
            }
    }
}

struct HeroSparkline: View {
    let points: [TimelinePoint]
    let tint: Color
    @State private var revealed = false

    var body: some View {
        Chart(points) { p in
            AreaMark(
                x: .value("Дата", p.date),
                y: .value("Часы", revealed ? p.minutes : 0)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.0)], startPoint: .top, endPoint: .bottom))

            LineMark(
                x: .value("Дата", p.date),
                y: .value("Часы", revealed ? p.minutes : 0)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .animation(.easeOut(duration: 0.7), value: revealed)
        .onAppear { revealed = true }
    }
}
