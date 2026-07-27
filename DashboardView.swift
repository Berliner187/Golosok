import SwiftUI
import Charts

struct DayTrendStat: Identifiable {
    let id = UUID()
    let day: String
    let count: Int
}

struct DashboardCalculator {
    let hoursSaved: String
    let aiPower: String
    let streakDays: Int
    let wpm: Int
    let totalMinutes: String
    let totalNotes: Int
    let avgLength: Int
    let weeklyTrend: [DayTrendStat]
    
    static func calculate(from history: [TranscriptionItem]) -> DashboardCalculator {
        let count = history.count
        let daysLabels = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
        
        if count == 0 {
            let emptyTrend = daysLabels.map { DayTrendStat(day: $0, count: 0) }
            return DashboardCalculator(
                hoursSaved: "0.00",
                aiPower: "35.0x",
                streakDays: 0,
                wpm: 0,
                totalMinutes: "0.0",
                totalNotes: 0,
                avgLength: 0,
                weeklyTrend: emptyTrend
            )
        }
        
        let totalChars = history.reduce(0) { $0 + $1.text.count }
        let avgChars = totalChars / max(1, count)
        
        var totalSecs: Double = 0.0
        for item in history {
            let cleaned = item.duration.replacingOccurrences(of: " сек", with: "").replacingOccurrences(of: ",", with: ".")
            totalSecs += Double(cleaned) ?? 2.5
        }
        let totalMins = totalSecs / 60.0
        
        let typingMinutes = Double(totalChars) / 200.0
        let savedHours = max(0.0, (typingMinutes - totalMins) / 60.0)
        
        let totalWords = history.reduce(0) { $0 + $1.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count }
        let calculatedWpm = totalMins > 0 ? Int(Double(totalWords) / totalMins) : 160
        
        // ФИЛЬТРАЦИЯ СТРОГО ПО ТЕКУЩЕЙ НЕДЕЛЕ
        var dayCounts = Array(repeating: 0, count: 7)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Устанавливаем Понедельник как 1-й день недели
        
        let now = Date()
        
        // Берем временной интервал ТЕКУЩЕЙ недели (с ПН 00:00 до ВС 23:59)
        if let currentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
            for item in history {
                if let date = formatter.date(from: item.date) {
                    // Учитываем запись ТОЛЬКО если она была сделана на ЭТОЙ неделе!
                    if currentWeekInterval.contains(date) {
                        let weekday = calendar.component(.weekday, from: date)
                        let idx = (weekday + 5) % 7 // Переводим 2(Пн)...7(Сб), 1(Вс) в индексы 0...6
                        dayCounts[idx] += 1
                    }
                }
            }
        }
        
        let trend = daysLabels.enumerated().map { (index, label) in
            DayTrendStat(day: label, count: dayCounts[index])
        }
        
        return DashboardCalculator(
            hoursSaved: String(format: "%.2f", savedHours),
            aiPower: "35.0x",
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
    
    var stats: DashboardCalculator {
        DashboardCalculator.calculate(from: audioCapture.history)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ШАПКА
                HStack {
                    Text("Используется")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.uiMidGray)
                    
                    UIBadge(text: "GigaAM v3")
                    Spacer()
                }
                
                // СЭКОНОМЛЕННЫЕ ЧАСЫ
                VStack(alignment: .leading, spacing: 6) {
                    Text(stats.hoursSaved)
                        .font(UIStyleFont.display(size: 44, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(-1.5)
                    
                    Text("СОХРАНЕНО ЧАСОВ")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.uiInk)
                .cornerRadius(24)
                
                // СЕТКА МЕТРИК
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(value: stats.aiPower, label: "МОЩНОСТЬ ИИ")
                    StatCard(value: "\(stats.streakDays)", label: "ДНЕЙ ПОДРЯД")
                    StatCard(value: "\(stats.wpm)", label: "WPM (ТЕМП)")
                    
                    StatCard(value: stats.totalMinutes, label: "НАГОВОРИЛИ (МИН)")
                    StatCard(value: "\(stats.totalNotes)", label: "ВСЕГО ЗАМЕТОК")
                    StatCard(value: "\(stats.avgLength)", label: "СРЕДНЯЯ ДЛИНА (ЗН)")
                }
                
                // ГРАФИК
                UICard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("НЕДЕЛЬНЫЙ ТРЕНД")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(.uiMidGray)
                        
                        Chart(stats.weeklyTrend) { item in
                            BarMark(
                                x: .value("День", item.day),
                                y: .value("Записи", item.count)
                            )
                            .foregroundStyle(Color.uiInk)
                            .cornerRadius(4)
                            // Выводим значения над столбцами
                            .annotation(position: .top, alignment: .center) {
                                if item.count > 0 {
                                    Text("\(item.count)")
                                        .font(UIStyleFont.body(size: 10, weight: .bold))
                                        .foregroundColor(.uiMidGray)
                                }
                            }
                        }
                        .frame(height: 120)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { value in
                                AxisValueLabel() {
                                    if let str = value.as(String.self) {
                                        Text(str)
                                            .font(UIStyleFont.body(size: 11, weight: .semibold))
                                            .foregroundColor(.uiMidGray)
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
                        .foregroundColor(.white)
                    Spacer()
                    Text("Design by Kozak")
                        .font(UIStyleFont.body(size: 10, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.uiInk)
                .cornerRadius(16)
            }
            .padding(20)
        }
        .background(Color.uiCanvas)
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
