import SwiftUI

/// Дашборд. Экран только читает готовый результат из `DashboardStatsStore` (расчёт — в фоне, прогрев — на запуске),
/// поэтому открывается мгновенно. Сам `DashboardView` не подписан на `AudioCapture`: от записи и плеера он не перерисовывается.
struct DashboardView: View {
    @State private var range: StatsRange = .week

    var body: some View {
        let store = DashboardStatsStore.shared
        let stats = store.byRange[range] ?? DashboardStats.placeholder(range)

        ScrollView {
            VStack(spacing: 14) {
                header(stats)
                DashHeroCard(stats: stats)
                DashInsightsCard(insights: stats.insights)
                kpiRow(stats)
                DashHeatmapCard(stats: stats)
                HStack(alignment: .top, spacing: 12) {
                    DashHourlyCard(stats: stats).frame(maxWidth: .infinity)
                    DashSpeedCard(stats: stats).frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                Text("ГОЛОСОК ™2026")
                    .font(UIStyleFont.body(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(.uiMidGray.opacity(0.7))
                    .padding(.top, 6)
            }
            .padding(20)
        }
        .background(Color.uiCanvas)
        // Подстраховка: если окно открыли уже после полуночи, расчёт обновится (на каждую новую дату подпись меняется).
        .onAppear { store.refresh(history: AudioCapture.shared.history) }
    }

    // MARK: Шапка

    private func header(_ stats: DashboardStats) -> some View {
        HStack(spacing: 12) {
            Text("УРОВЕНЬ:")
                .font(UIStyleFont.body(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.uiMidGray)
            UIBadge(text: stats.levelName)
            if let next = stats.levelNext {
                Text("\(stats.levelCount) / \(next)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.uiMidGray)
            }
            Spacer()
            DashUpdateBanner()
            UISegmented(selection: $range, segments: StatsRange.allCases.map { UISegment(text: Text($0.title), value: $0) })
                .frame(width: 250)
        }
    }

    // MARK: Метрики

    private func kpiRow(_ s: DashboardStats) -> some View {
        HStack(spacing: 12) {
            DashKPICard(title: "СЛОВ НАДИКТОВАНО", delta: s.deltaWords) {
                DashNumberValue(value: s.words)
            }
            DashKPICard(title: "ВРЕМЯ РЕЧИ", delta: s.deltaSpeech) {
                DurationText(minutes: Int((s.speechSeconds / 60).rounded()), numberSize: 28, unitSize: 13,
                             color: .uiInk, unitColor: .uiMidGray, tracking: -0.8)
            }
            DashKPICard(title: "ЗАМЕТОК", delta: s.deltaNotes) {
                DashNumberValue(value: s.notes)
            }
            DashKPICard(title: "СЕРИЯ",
                        note: s.bestStreak > 0 ? String(format: String(localized: "рекорд %d"), s.bestStreak) : nil) {
                DashNumberValue(value: s.streak, unit: "дн.")
            }
        }
    }
}

// MARK: - Баннер обновления (логика прежняя, вынесен отдельно)

struct DashUpdateBanner: View {
    @ObservedObject var audioCapture = AudioCapture.shared

    var body: some View {
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
}
