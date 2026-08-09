import SwiftUI

struct LogsView: View {
    @ObservedObject var logger = AppLogger.shared
    @State private var showInfo = true
    @State private var showWarn = true
    @State private var showError = true
    @Environment(\.dismiss) private var dismiss

    private var filtered: [LogEntry] {
        logger.entries.filter {
            switch $0.level {
            case .info: return showInfo
            case .warn: return showWarn
            case .error: return showError
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider().background(Color.uiHairline)

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("Пока нет записей")
                        .font(UIStyleFont.body(size: 13, weight: .medium))
                        .foregroundColor(.uiMidGray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { entry in
                            LogRow(entry: entry)
                            if entry.id != filtered.last?.id {
                                Divider().background(Color.uiHairline.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            footer
                .padding(16)
        }
        .background(Color.uiPaper)
        .frame(minWidth: 560, minHeight: 440)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Логи приложения")
                .font(UIStyleFont.display(size: 16, weight: .semibold))
                .foregroundColor(.uiInk)
            Spacer()

            HStack(spacing: 6) {
                levelButton(tint: .uiInkSoft, symbol: "i.circle",
                            isOn: showInfo, help: "Информация") { showInfo.toggle() }
                levelButton(tint: .uiWarn, symbol: "exclamationmark.triangle",
                            isOn: showWarn, help: "Предупреждения") { showWarn.toggle() }
                levelButton(tint: .uiEmber, symbol: "xmark.octagon",
                            isOn: showError, help: "Ошибки") { showError.toggle() }
            }
        }
    }

    private func levelButton(tint: Color, symbol: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isOn ? tint : .uiMidGray.opacity(0.6))
                .frame(width: 28, height: 26)
                .background(isOn ? tint.opacity(0.14) : Color.uiCanvas)
                .cornerRadius(13)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(isOn ? tint.opacity(0.4) : Color.uiHairline, lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
        .help(help)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            UIOutlineButton(title: "Копировать") { copyLogs() }
            UIOutlineButton(title: "Очистить") { logger.clear() }
            UIOutlineButton(title: "Открыть файл") { openFile() }
            Spacer()
            UIPrimaryButton(title: "Закрыть") { dismiss() }
        }
    }

    private func copyLogs() {
        let text = filtered.map { entry in
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            let extra = entry.details.map { " | \($0)" } ?? ""
            return "[\(f.string(from: entry.timestamp))] \(entry.level.label) \(entry.source): \(entry.message)\(extra)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openFile() {
        guard let url = AppLogger.shared.logFileURL else { return }
        NSWorkspace.shared.open(url)
    }
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(entry.level.label)
                    .font(UIStyleFont.body(size: 9, weight: .bold))
                    .foregroundColor(color)
                Text(timeString)
                    .font(UIStyleFont.body(size: 10, weight: .regular))
                    .foregroundColor(.uiMidGray)
                Text(entry.source)
                    .font(UIStyleFont.body(size: 10, weight: .semibold))
                    .foregroundColor(.uiInkSoft)
            }
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.uiInk)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let details = entry.details {
                Text(details)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.uiMidGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var color: Color {
        switch entry.level {
        case .info: return .uiInkSoft
        case .warn: return .uiWarn
        case .error: return .uiEmber
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: entry.timestamp)
    }
}