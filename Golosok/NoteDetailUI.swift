import SwiftUI
import AppKit

// MARK: - Типографика текста заметки

/// Единые параметры чтения: комфортная длина строки, воздух между строками и абзацами.
enum NoteTypography {
    static let fontSize: CGFloat = 16
    static let maxReadingWidth: CGFloat = 760

    static var font: NSFont { .systemFont(ofSize: fontSize, weight: .regular) }

    static var paragraphStyle: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 6
        p.paragraphSpacing = 10
        return p
    }
}

// MARK: - Кнопки-иконки действий

/// Круглая иконка 34 pt для второстепенных действий (Редактировать, Экспорт, Удалить).
/// Подпись — во всплывающей подсказке. Нужна и как «лицо» для UIDropdownMenu.
struct NoteIconLabel: View {
    let icon: String
    var tint: Color = .uiInk
    var hoverTint: Color? = nil
    @State private var hover = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(hover ? (hoverTint ?? tint) : tint)
            .frame(width: 34, height: 34)
            .background(Circle().fill(hover ? (hoverTint ?? Color.uiInk).opacity(0.08) : Color.clear))
            .overlay(Circle().stroke(hover ? (hoverTint ?? Color.uiHairline).opacity(hoverTint == nil ? 1 : 0.35) : Color.uiHairline,
                                     lineWidth: 1))
            .contentShape(Circle())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct NoteIconButton: View {
    let icon: String
    let help: LocalizedStringKey
    var tint: Color = .uiInk
    var hoverTint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NoteIconLabel(icon: icon, tint: tint, hoverTint: hoverTint)
        }
        .buttonStyle(TactileButtonStyle())
        .help(help)
    }
}

// MARK: - Метаданные

/// Вместо четырёх цветных плашек — одна тихая строка. Скорость и время чтения остались в подсказке.
struct NoteMetaLine: View {
    let parts: [String]
    let tooltip: String

    var body: some View {
        Text(parts.joined(separator: "  ·  "))
            .font(UIStyleFont.body(size: 12, weight: .regular))
            .foregroundColor(.uiMidGray)
            .monospacedDigit()
            .help(tooltip)
    }
}

struct NoteSearchHint: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                Text(LocalizedStringKey("Поиск")).font(UIStyleFont.body(size: 12, weight: .regular))
                Text("⌘F")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.uiHairline, lineWidth: 1))
            }
            .foregroundColor(hover ? .uiInk : .uiMidGray)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(String(localized: "Поиск по стенограмме (⌘F)"))
    }
}

struct NoteListenButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 9, weight: .bold))
                Text(isPlaying ? LocalizedStringKey("Пауза") : LocalizedStringKey("Слушать голос"))
                    .font(UIStyleFont.body(size: 12, weight: .medium))
            }
            .foregroundColor(.uiInk)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.uiSidebar))
            .overlay(Capsule().stroke(Color.uiHairline, lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
    }
}

// MARK: - Плеер

/// Монохромный плеер: ink-кнопка вместо синей, тонкий трек, время моноширинным — всё в одной капсуле.
struct NotePlayerBar: View {
    let isPlaying: Bool
    @Binding var playhead: Double
    let duration: Double
    let playheadText: String
    let durationText: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.dynamic(light: "#ffffff", dark: "#000000"))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.uiInk))
            }
            .buttonStyle(TactileButtonStyle())

            Text(playheadText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.uiMidGray)

            UISeekSlider(value: $playhead, range: 0...max(duration, 0.01))

            Text(durationText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.uiMidGray)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.uiSidebar))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.uiHairline, lineWidth: 1))
    }
}
