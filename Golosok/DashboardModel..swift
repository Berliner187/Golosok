import Foundation
import Observation
import SwiftUI

// MARK: - Акцентный цвет

extension Color {
    /// Электрический синий — единственный акцент приложения в данных.
    /// Оранжевый (`uiWarn`) оставлен только для предупреждений и баннера обновления.
    static let uiSignal = Color.dynamic(light: "#0A5CFF", dark: "#3D8BFF")
}

// MARK: - Диапазон

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

// MARK: - Модель для экрана

struct HeatDay: Equatable {
    let date: Date
    let count: Int
    let isFuture: Bool
}

struct HeatWeek: Identifiable, Equatable {
    let id: Int
    let days: [HeatDay]          // 7 штук, Пн…Вс
}

struct DashboardInsight: Identifiable, Equatable {
    let id: String
    let icon: String
    let text: String
}

struct DashboardStats: Equatable {
    var range: StatsRange

    // Период (только надиктованные заметки)
    var notes = 0
    var words = 0
    var speechSeconds: Double = 0
    var savedMinutes: Double = 0
    var savedSeries: [Double] = []           // накопительно: линия «сэкономлено»

    // Изменение к предыдущему периоду (nil — нет с чем сравнивать)
    var deltaWords: Double? = nil
    var deltaNotes: Double? = nil
    var deltaSpeech: Double? = nil
    var deltaSaved: Double? = nil

    // Привычка (не зависит от диапазона)
    var streak = 0
    var bestStreak = 0
    var heat: [HeatWeek] = []
    var heatMax = 0
    var heatActiveDays = 0
    var heatElapsedDays = 0

    // Время суток (в пределах диапазона)
    var hourly: [Int] = Array(repeating: 0, count: 24)
    var peakHour: Int? = nil

    // Скорость распознавания
    var speedAvg: Double? = nil
    var speedSeries: [Double] = []

    var insights: [DashboardInsight] = []

    // Уровень (по числу всех заметок — как и раньше)
    var levelName = ""
    var levelCount = 0
    var levelNext: Int? = nil

    /// Пустые данные: показываются, пока фоновый расчёт ещё не готов или заметок нет.
    static let placeholders: [StatsRange: DashboardStats] = DashboardBuilder.build(notes: [], totalCount: 0, now: Date())
    static func placeholder(_ range: StatsRange) -> DashboardStats {
        placeholders[range] ?? DashboardStats(range: range)
    }
}

// MARK: - Разобранная заметка (кэшируется между пересчётами)

struct ParsedNote {
    let date: Date
    let day: Date                // начало дня
    let hour: Int
    let weekday: Int             // 0 = Пн
    let secs: Double
    let chars: Int
    let words: Int
    let speedup: Double          // 0 — неизвестно

    /// Сколько минут сэкономлено относительно набора текстом. Допущение: 200 знаков/мин (≈ 40 слов/мин).
    var savedMinutes: Double { max(0, Double(chars) / 200.0 - secs / 60.0) }
}

private struct CacheEntry {
    let fingerprint: Int
    let note: ParsedNote?        // nil — заметка не из диктовки (длительность «—»)
}

// MARK: - Расчёт

enum DashboardBuilder {
    private static let levelThresholds: [(Int, String)] = [
        (6, "ПОЛЬЗОВАТЕЛЬ"), (21, "ЛЮБИТЕЛЬ"), (51, "ОПЫТНЫЙ"), (101, "СПЕЦИАЛИСТ"),
        (251, "ЭКСПЕРТ"), (501, "ПРОФИ"), (1001, "МАСТЕР"), (2501, "ВИРТУОЗ"), (5001, "ЛЕГЕНДА")
    ]

    static func levelName(for count: Int) -> String {
        switch count {
        case 0...5:       return String(localized: "НОВИЧОК")
        case 6...20:      return String(localized: "ПОЛЬЗОВАТЕЛЬ")
        case 21...50:     return String(localized: "ЛЮБИТЕЛЬ")
        case 51...100:    return String(localized: "ОПЫТНЫЙ")
        case 101...250:   return String(localized: "СПЕЦИАЛИСТ")
        case 251...500:   return String(localized: "ЭКСПЕРТ")
        case 501...1000:  return String(localized: "ПРОФИ")
        case 1001...2500: return String(localized: "МАСТЕР")
        case 2501...5000: return String(localized: "ВИРТУОЗ")
        default:          return String(localized: "ЛЕГЕНДА")
        }
    }

    private struct Agg {
        var notes = 0, words = 0
        var secs = 0.0, saved = 0.0
        mutating func add(_ n: ParsedNote) {
            notes += 1
            words += n.words
            secs += n.secs
            saved += n.savedMinutes
        }
    }

    private struct Habit {
        var streak = 0, best = 0
        var weeks: [HeatWeek] = []
        var maxCount = 0, active = 0, elapsed = 0
    }

    static let heatWeeks = 26

    static func build(notes: [ParsedNote], totalCount: Int, now: Date) -> [StatsRange: DashboardStats] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        let sorted = notes.sorted { $0.date < $1.date }

        var perDay: [Date: Int] = [:]
        for n in sorted { perDay[n.day, default: 0] += 1 }
        let habit = makeHabit(perDay: perDay, today: today, cal: cal)

        let level = levelName(for: totalCount)
        let nextLevel = levelThresholds.first(where: { $0.0 > totalCount })?.0

        var out: [StatsRange: DashboardStats] = [:]
        for r in StatsRange.allCases {
            let days = r.dayCount
            let start: Date = r == .all
                ? (sorted.first?.day ?? today)
                : (cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
            let prevStart: Date? = r == .all ? nil : cal.date(byAdding: .day, value: -days, to: start)

            let totalDays = max(1, Int((today.timeIntervalSince(start) / 86_400).rounded()) + 1)
            let bucketCount = r == .all ? min(60, max(2, totalDays)) : days

            var cur = Agg(), prev = Agg()
            var hourly = [Int](repeating: 0, count: 24)
            var weekdayCounts = [Int](repeating: 0, count: 7)
            var speeds: [Double] = []
            var savedBuckets = [Double](repeating: 0, count: bucketCount)

            for n in sorted {
                if n.day >= start {
                    cur.add(n)
                    hourly[n.hour] += 1
                    weekdayCounts[n.weekday] += 1
                    if n.speedup > 0 { speeds.append(n.speedup) }
                    let off = max(0, Int((n.day.timeIntervalSince(start) / 86_400).rounded()))
                    let idx = min(bucketCount - 1, Int(Double(off) / Double(totalDays) * Double(bucketCount)))
                    savedBuckets[idx] += n.savedMinutes
                } else if let ps = prevStart, n.day >= ps {
                    prev.add(n)
                }
            }

            func delta(_ c: Double, _ p: Double) -> Double? {
                guard prevStart != nil, p > 0 else { return nil }
                return (c - p) / p
            }

            var s = DashboardStats(range: r)
            s.notes = cur.notes
            s.words = cur.words
            s.speechSeconds = cur.secs
            s.savedMinutes = cur.saved
            var acc = 0.0
            s.savedSeries = savedBuckets.map { (v: Double) -> Double in
                acc += v
                return acc
            }
            s.deltaWords = delta(Double(cur.words), Double(prev.words))
            s.deltaNotes = delta(Double(cur.notes), Double(prev.notes))
            s.deltaSpeech = delta(cur.secs, prev.secs)
            s.deltaSaved = delta(cur.saved, prev.saved)

            s.streak = habit.streak
            s.bestStreak = habit.best
            s.heat = habit.weeks
            s.heatMax = habit.maxCount
            s.heatActiveDays = habit.active
            s.heatElapsedDays = habit.elapsed

            s.hourly = hourly
            if hourly.reduce(0, +) >= 3 {
                s.peakHour = hourly.indices.max(by: { hourly[$0] < hourly[$1] })
            }

            if !speeds.isEmpty {
                s.speedAvg = speeds.reduce(0, +) / Double(speeds.count)
                s.speedSeries = Array(speeds.suffix(30))
            }

            s.levelName = level
            s.levelCount = totalCount
            s.levelNext = nextLevel

            s.insights = makeInsights(stats: s, prevWords: prev.words, weekdayCounts: weekdayCounts, cal: cal)
            out[r] = s
        }
        return out
    }

    // MARK: Привычка: серии и тепловая карта

    private static func makeHabit(perDay: [Date: Int], today: Date, cal: Calendar) -> Habit {
        var h = Habit()

        let days = perDay.keys.sorted()
        var run = 0
        var prev: Date? = nil
        for d in days {
            if let p = prev, cal.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            h.best = max(h.best, run)
            prev = d
        }
        // Серия жива, пока не закончился сегодняшний день: если сегодня ещё не диктовали — считаем со вчера.
        var cursor = perDay[today] != nil ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        while perDay[cursor] != nil {
            h.streak += 1
            guard let p = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = p
        }

        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let gridStart = cal.date(byAdding: .day, value: -(heatWeeks - 1) * 7, to: weekStart) ?? weekStart
        for w in 0..<heatWeeks {
            var ds: [HeatDay] = []
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart) ?? gridStart
                let c = perDay[date] ?? 0
                let future = date > today
                ds.append(HeatDay(date: date, count: c, isFuture: future))
                if !future {
                    h.elapsed += 1
                    h.maxCount = max(h.maxCount, c)
                    if c > 0 { h.active += 1 }
                }
            }
            h.weeks.append(HeatWeek(id: w, days: ds))
        }
        return h
    }

    // MARK: Выводы

    private static func makeInsights(stats s: DashboardStats, prevWords: Int, weekdayCounts: [Int], cal: Calendar) -> [DashboardInsight] {
        var list: [DashboardInsight] = []

        if let dw = s.deltaWords, prevWords >= 20, abs(dw) >= 0.1 {
            let pct = Int((abs(dw) * 100).rounded())
            let text = dw > 0
                ? String(format: String(localized: "На %d%% больше слов, чем в предыдущем периоде"), pct)
                : String(format: String(localized: "На %d%% меньше слов, чем в предыдущем периоде"), pct)
            list.append(DashboardInsight(id: "trend", icon: dw > 0 ? "arrow.up.right" : "arrow.down.right", text: text))
        }

        if s.streak >= 2 {
            list.append(DashboardInsight(id: "streak", icon: "flame",
                                         text: String(format: String(localized: "Серия: %d дн. подряд"), s.streak)))
        }

        if s.notes >= 5, let ph = s.peakHour {
            let span = String(format: "%02d:00–%02d:00", ph, (ph + 1) % 24)
            list.append(DashboardInsight(id: "hour", icon: "clock",
                                         text: String(format: String(localized: "Чаще всего вы диктуете с %@"), span)))
        }

        if s.notes >= 7, let top = weekdayCounts.indices.max(by: { weekdayCounts[$0] < weekdayCounts[$1] }),
           Double(weekdayCounts[top]) / Double(max(1, s.notes)) >= 0.2 {
            let name = cal.weekdaySymbols[(top + 1) % 7]
            list.append(DashboardInsight(id: "weekday", icon: "calendar",
                                         text: String(format: String(localized: "Самый активный день — %@"), name)))
        }

        if let avg = s.speedAvg, avg >= 5 {
            list.append(DashboardInsight(id: "speed", icon: "bolt",
                                         text: String(format: String(localized: "Распознавание в среднем в %d× быстрее речи"), Int(avg.rounded()))))
        }
        return Array(list.prefix(3))
    }
}

// MARK: - Хранилище: расчёт в фоне, результат кэшируется

/// Внешний API прежний: `DashboardStatsStore.shared.refresh(history:)` вызывается из `AudioCapture` и `AppDelegate`
/// (прогрев на запуске во время сплэша). Экран только читает готовый результат.
@Observable
final class DashboardStatsStore {
    static let shared = DashboardStatsStore()

    /// Готовые данные по диапазонам. Обновляется только на main.
    private(set) var byRange: [StatsRange: DashboardStats] = [:]

    @ObservationIgnored private var computedSignature = 0
    @ObservationIgnored private var pendingSignature = 0
    /// Кэш разбора заметок. Трогается только на `queue` (серийная), поэтому без блокировок.
    @ObservationIgnored private var cache: [UUID: CacheEntry] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "golosok.dashboard.calc", qos: .utility)
    @ObservationIgnored private let dateParser: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy, HH:mm"
        return df
    }()

    private init() {}

    func refresh(history: [TranscriptionItem]) {
        let sig = Self.signature(of: history)
        guard sig != computedSignature, sig != pendingSignature else { return }
        pendingSignature = sig
        let snapshot = history
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.compute(snapshot)
            DispatchQueue.main.async {
                // Если за это время запущен более новый расчёт — этот результат устарел.
                guard self.pendingSignature == sig else { return }
                self.computedSignature = sig
                self.byRange = result
            }
        }
    }

    /// Меняется, когда меняется состав или текст заметок либо наступает новый день.
    /// Прочитано/непрочитано в подпись не входит — клик по заметке не вызывает пересчёт.
    private static func signature(of history: [TranscriptionItem]) -> Int {
        var h = Hasher()
        h.combine(history.count)
        h.combine(Calendar.current.startOfDay(for: Date()))
        for item in history {
            h.combine(item.id)
            h.combine(item.text.utf8.count)
        }
        return h.finalize()
    }

    private func compute(_ history: [TranscriptionItem]) -> [StatsRange: DashboardStats] {
        let cal = Calendar.current
        var next: [UUID: CacheEntry] = [:]
        next.reserveCapacity(history.count)
        var parsed: [ParsedNote] = []
        parsed.reserveCapacity(history.count)

        for item in history {
            let fp = item.text.utf8.count
            let entry: CacheEntry
            if let cached = cache[item.id], cached.fingerprint == fp {
                entry = cached
            } else {
                entry = CacheEntry(fingerprint: fp, note: parse(item, cal: cal))
            }
            next[item.id] = entry
            if let n = entry.note { parsed.append(n) }
        }
        cache = next
        return DashboardBuilder.build(notes: parsed, totalCount: history.count, now: Date())
    }

    private func parse(_ item: TranscriptionItem, cal: Calendar) -> ParsedNote? {
        // Длительность «—» у заметок не из диктовки (вставленный текст): в статистику речи они не входят.
        guard let secs = Self.parseSeconds(item.duration), secs > 0,
              let date = dateParser.date(from: item.date) else { return nil }
        let comps = cal.dateComponents([.hour, .weekday], from: date)
        let speed = item.speedup ?? 0
        return ParsedNote(
            date: date,
            day: cal.startOfDay(for: date),
            hour: comps.hour ?? 0,
            weekday: ((comps.weekday ?? 2) + 5) % 7,
            secs: secs,
            chars: item.text.count,
            words: item.text.split(whereSeparator: { $0.isWhitespace }).count,
            speedup: speed > 0 ? speed : 0
        )
    }

    /// «43 сек», «2 мин», «43 sec», «2 min» → секунды. Берётся первое число в строке.
    static func parseSeconds(_ s: String) -> Double? {
        var num = ""
        var started = false
        for ch in s {
            if ch.isNumber {
                num.append(ch)
                started = true
            } else if started && (ch == "." || ch == ",") {
                num.append(".")
            } else if started {
                break
            }
        }
        guard let v = Double(num) else { return nil }
        let lower = s.lowercased()
        let isMinutes = lower.contains("мин") || lower.contains("min")
        return v * (isMinutes ? 60 : 1)
    }
}

