import SwiftUI
import Charts

struct DayTrendStat: Identifiable {
    let id = UUID()
    let day: String
    let count: Int
    let chars: Int
}

enum TrendMetric {
    case notes
    case characters
}

struct DashboardCalculator {
    let hoursSaved: String
    let aiPower: String
    let levelName: String
    let a4Pages: String
    let peakActivity: String
    let streakDays: Int
    let wpm: Int
    let totalMinutes: String
    let totalNotes: Int
    let avgLength: Int
    let weeklyTrend: [DayTrendStat]
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy, HH:mm"
        return df
    }()
    
    static var empty: DashboardCalculator {
        let daysLabels = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
        return DashboardCalculator(
            hoursSaved: "0.00", aiPower: "35.0x", levelName: "НОВИЧОК", a4Pages: "0", peakActivity: "НЕТ ДАННЫХ",
            streakDays: 0, wpm: 0, totalMinutes: "0.0", totalNotes: 0, avgLength: 0,
            weeklyTrend: daysLabels.map { DayTrendStat(day: $0, count: 0, chars: 0) }
        )
    }
    
    static func calculate(from history: [TranscriptionItem]) -> DashboardCalculator {
        let count = history.count
        let daysLabels = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
        
        if count == 0 { return empty }
        
        let totalChars = history.reduce(0) { $0 + $1.text.count }
        let avgChars = totalChars / max(1, count)
        let a4Count = Double(totalChars) / 1800.0
        
        let level: String
        switch count {
        case 0...5:       level = "НОВИЧОК"
        case 6...20:      level = "ПОЛЬЗОВАТЕЛЬ"
        case 21...50:     level = "ЛЮБИТЕЛЬ"
        case 51...100:    level = "ОПЫТНЫЙ"
        case 101...250:   level = "СПЕЦИАЛИСТ"
        case 251...500:   level = "ЭКСПЕРТ"
        case 501...1000:  level = "ПРОФИ"
        case 1001...2500: level = "МАСТЕР"
        case 2501...5000: level = "ВИРТУОЗ"
        default:          level = "ЛЕГЕНДА"
        }
        
        var totalSecs: Double = 0.0
        var m = 0, d = 0, e = 0, n = 0
        
        for item in history {
            let cleaned = item.duration.replacingOccurrences(of: " сек", with: "").replacingOccurrences(of: " мин", with: "")
            totalSecs += Double(cleaned) ?? 2.5
            
            if let date = dateFormatter.date(from: item.date) {
                let hour = Calendar.current.component(.hour, from: date)
                switch hour {
                case 6..<12: m += 1
                case 12..<18: d += 1
                case 18..<24: e += 1
                default: n += 1
                }
            }
        }
        
        let peak: String
        let maxActivity = max(m, d, e, n)
        if maxActivity == m { peak = "УТРО" } else if maxActivity == d { peak = "ДЕНЬ" } else if maxActivity == e { peak = "ВЕЧЕР" } else { peak = "НОЧЬ" }
        
        let totalMins = totalSecs / 60.0
        let savedHours = max(0.0, ((Double(totalChars) / 200.0) - totalMins) / 60.0)
        
        let totalWords = history.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let calculatedWpm = totalMins > 0 ? Int(Double(totalWords) / totalMins) : 160
        
        var dayCounts = Array(repeating: 0, count: 7)
        var dayChars = Array(repeating: 0, count: 7)
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        
        if let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) {
            for item in history {
                if let date = dateFormatter.date(from: item.date), currentWeekInterval.contains(date) {
                    let idx = (calendar.component(.weekday, from: date) + 5) % 7
                    dayCounts[idx] += 1
                    dayChars[idx] += item.text.count
                }
            }
        }
        let trend = daysLabels.enumerated().map { DayTrendStat(day: $1, count: dayCounts[$0], chars: dayChars[$0]) }
        
        let speedups = history.compactMap { $0.speedup }.filter { $0 > 0 }
        let avgSpeedup = speedups.isEmpty ? 35.0 : (speedups.reduce(0, +) / Double(speedups.count))
        
        return DashboardCalculator(
            hoursSaved: String(format: "%.2f", savedHours),
            aiPower: String(format: "%.1fx", avgSpeedup),
            levelName: level,
            a4Pages: String(format: "%.1f", a4Count),
            peakActivity: peak,
            streakDays: max(1, count > 0 ? 1 : 0),
            wpm: max(130, min(210, calculatedWpm)),
            totalMinutes: String(format: "%.1f", totalMins),
            totalNotes: count,
            avgLength: avgChars,
            weeklyTrend: trend
        )
    }
}

struct DashboardView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @State private var trendMetric: TrendMetric = .notes
    @State private var stats: DashboardCalculator = DashboardCalculator.empty
    
    let cardBackground = Color.dynamic(light: "#0a0a0a", dark: "#ffffff")
    let primaryTextColor = Color.dynamic(light: "#ffffff", dark: "#0a0a0a")
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ШАПКА
                HStack {
                    Text("УРОВЕНЬ:")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.uiMidGray)
                    UIBadge(text: stats.levelName)
                    
                    Spacer()
                    if let update = audioCapture.updateInfo {
                        Button(action: {
                            audioCapture.downloadAndInstallUpdate()
                        }) {
                            HStack(spacing: 4) {
                                if audioCapture.isDownloadingUpdate {
                                    ProgressView().scaleEffect(0.6)
                                    Text("Скачивание...")
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Доступна \(update.codename)")
                                }
                            }
                            .font(UIStyleFont.body(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.uiEmber).cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(audioCapture.isDownloadingUpdate)
                    }
                }
                
                // ГЛАВНАЯ КАРТОЧКА
                VStack(alignment: .leading, spacing: 6) {
                    Text(stats.hoursSaved)
                        .font(UIStyleFont.display(size: 44, weight: .bold))
                        .foregroundColor(primaryTextColor)
                        .tracking(-1.5)
                    
                    Text("СОХРАНЕНО ЧАСОВ")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(primaryTextColor)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .cornerRadius(24)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.uiHairline, lineWidth: 1))
                
                // СЕТКА МЕТРИК
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(value: stats.aiPower, label: "МОЩНОСТЬ ИИ")
                    StatCard(value: "\(stats.totalNotes)", label: "ВСЕГО ЗАМЕТОК")
                    StatCard(value: stats.totalMinutes, label: "НАГОВОРИЛИ (МИН)")
                    StatCard(value: stats.a4Pages, label: "СТРАНИЦ А4")
                    StatCard(value: "\(stats.wpm)", label: "WPM (ТЕМП)")
                    StatCard(value: stats.peakActivity, label: "ПИК АКТИВНОСТИ")
                }
                
                // ГРАФИК
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
                            let yVal = (trendMetric == .notes) ? item.count : item.chars
                            
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
                        .animation(.easeInOut(duration: 0.3), value: trendMetric)
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
                
                // ФУТЕР
                HStack {
                    Text("ГОЛОСОК ™2026")
                        .font(UIStyleFont.body(size: 10, weight: .bold))
                        .foregroundColor(primaryTextColor)
                    Spacer()
                    Text("Design by Kozak")
                        .font(UIStyleFont.body(size: 10, weight: .regular))
                        .foregroundColor(primaryTextColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(cardBackground)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.uiHairline, lineWidth: 1))
            }
            .padding(20)
        }
        .background(Color.uiCanvas)
        .onAppear {
            stats = DashboardCalculator.calculate(from: audioCapture.history)
        }
        .onChange(of: audioCapture.history.count) { _ in
            stats = DashboardCalculator.calculate(from: audioCapture.history)
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
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
