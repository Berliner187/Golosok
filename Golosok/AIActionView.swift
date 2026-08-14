import SwiftUI
import AppKit

struct AIActionRequest: Identifiable {
    let id = UUID()
    let template: AIPromptTemplate
    let noteID: UUID
    let noteText: String
}

final class AICache {
    static let shared = AICache()

    private struct Key: Hashable {
        let noteID: UUID
        let templateID: String
    }
    private struct Entry {
        let sourceText: String
        let result: String
        let date: Date
    }
    private struct StoredEntry: Codable {
        let noteID: String
        let templateID: String
        let sourceText: String
        let result: String
        let date: Date
    }

    private var entries: [Key: Entry] = [:]
    private let limit = 60
    private let ioQueue = DispatchQueue(label: "Golosok.AICache.io")

    private init() {
        load()
    }

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Golosok", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai_cache.json")
    }

    func result(noteID: UUID, templateID: String, for text: String) -> String? {
        guard let entry = entries[Key(noteID: noteID, templateID: templateID)],
              entry.sourceText == text else { return nil }
        return entry.result
    }

    func store(noteID: UUID, templateID: String, text: String, result: String) {
        let key = Key(noteID: noteID, templateID: templateID)
        entries[key] = Entry(sourceText: text, result: result, date: Date())
        if entries.count > limit {
            if let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
                entries.removeValue(forKey: oldest)
            }
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        let snapshot = entries.map { key, entry in
            StoredEntry(noteID: key.noteID.uuidString, templateID: key.templateID, sourceText: entry.sourceText, result: entry.result, date: entry.date)
        }
        ioQueue.async { [weak self] in
            guard let self, let url = self.fileURL else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode([StoredEntry].self, from: data) else { return }
        for item in payload.prefix(limit) {
            guard let noteID = UUID(uuidString: item.noteID) else { continue }
            entries[Key(noteID: noteID, templateID: item.templateID)] = Entry(sourceText: item.sourceText, result: item.result, date: item.date)
        }
    }
}

struct AIResultSheet: View {
    let request: AIActionRequest
    let onOpenNewNote: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var resultText = ""
    @State private var errorText: String?
    @State private var copied = false
    @State private var fromCache = false

    enum Phase { case loading, done, error }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: request.template.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.uiInk)
                Text(LocalizedStringKey(request.template.title))
                    .font(UIStyleFont.display(size: 15, weight: .bold))
                    .foregroundColor(.uiInk)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.uiMidGray)
                        .frame(width: 28, height: 28)
                        .background(Color.uiSidebar)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.uiHairline, lineWidth: 1))
                }
                .buttonStyle(TactileButtonStyle())
            }

            Divider().background(Color.uiHairline)

            if phase == .done && fromCache {
                cacheBar
            }

            content

            if phase == .done {
                Divider().background(Color.uiHairline)
                footer
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 400)
        .background(Color.uiPaper)
        .onAppear(perform: run)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 16) {
                AIThinkingOrb(icon: request.template.icon)
                Text("Генерация…")
                    .font(UIStyleFont.body(size: 12, weight: .regular))
                    .foregroundColor(.uiMidGray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error:
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundColor(.uiEmber)
                Text(errorText ?? String(localized: "Ошибка"))
                    .font(UIStyleFont.body(size: 13, weight: .medium))
                    .foregroundColor(.uiInk)
                    .multilineTextAlignment(.center)
                UIOutlineButton(title: "Повторить") { run() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .done:
            ScrollView {
                markdownText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color.uiSidebar)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.uiHairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var markdownText: some View {
        Text(renderedMarkdown())
            .font(UIStyleFont.body(size: 14, weight: .regular))
            .foregroundColor(.uiInk)
            .textSelection(.enabled)
    }

    private func renderedMarkdown() -> AttributedString {
        let lines = resultText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var out = AttributedString()
        var bullets: [String] = []

        func flushBullets() {
            guard !bullets.isEmpty else { return }
            for item in bullets {
                out.append(inlineStyled(item))
                out.append(AttributedString("\n"))
            }
            bullets.removeAll()
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushBullets()
                out.append(AttributedString("\n"))
                continue
            }
            if let heading = Self.headingText(line) {
                flushBullets()
                out.append(inlineStyled("**\(heading)**"))
                out.append(AttributedString("\n"))
                continue
            }
            if let item = Self.listItemText(line) {
                bullets.append(item)
                continue
            }
            flushBullets()
            out.append(inlineStyled(line))
            out.append(AttributedString("\n"))
        }
        flushBullets()
        return out
    }

    private func inlineStyled(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }

    private static func headingText(_ line: String) -> String? {
        var s = line
        var level = 0
        while s.hasPrefix("#") { level += 1; s.removeFirst() }
        guard level >= 1, level <= 6, s.hasPrefix(" ") else { return nil }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func listItemText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] {
            if line.hasPrefix(marker) {
                return "• " + String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i].isNumber { i += 1 }
        guard i > 0, i < chars.count, (chars[i] == "." || chars[i] == ")") else { return nil }
        let marker = String(chars.prefix(i + 1))
        let rest = String(chars.dropFirst(i + 1)).trimmingCharacters(in: .whitespaces)
        return "\(marker) \(rest)"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            UIPrimaryButton(title: "Вставить ниже") {
                AudioCapture.shared.appendTextToNote(id: request.noteID, text: resultText)
                SoundEffect.playSuccess()
                dismiss()
            }
            UIOutlineButton(title: "Заменить") {
                AudioCapture.shared.replaceNoteText(id: request.noteID, text: resultText)
                SoundEffect.playSuccess()
                dismiss()
            }
            UIOutlineButton(title: "Новая заметка") {
                let newID = AudioCapture.shared.addNote(text: resultText)
                SoundEffect.playSuccess()
                dismiss()
                onOpenNewNote(newID)
            }
            Spacer()
            Button(action: copy) {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                    Text(copied ? "Готово!" : "Копировать")
                        .font(UIStyleFont.body(size: 13, weight: .medium))
                }
                .foregroundColor(copied ? Color(hex: "#10B981") : .uiInk)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(Color.uiPaper)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(copied ? Color(hex: "#10B981").opacity(0.5) : Color.uiHairline, lineWidth: 1))
            }
            .buttonStyle(TactileButtonStyle())
        }
    }

    private func run() {
        if let cached = AICache.shared.result(noteID: request.noteID, templateID: request.template.id, for: request.noteText) {
            resultText = cached
            fromCache = true
            phase = .done
            return
        }
        generate()
    }

    private func regenerate() {
        generate()
    }

    private func generate() {
        fromCache = false
        phase = .loading
        errorText = nil

        guard AIProviderStore.shared.isConfigured else {
            phase = .error
            errorText = String(localized: "ИИ-провайдер не настроен. Добавьте ключ в Настройках → ИИ-провайдер.")
            return
        }

        let messages = request.template.messages(for: request.noteText)
        AIService.shared.chat(messages: messages, using: AIProviderStore.shared.config) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    resultText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    phase = .done
                    AICache.shared.store(noteID: request.noteID, templateID: request.template.id, text: request.noteText, result: resultText)
                case .failure(let error):
                    errorText = error.localizedDescription
                    phase = .error
                }
            }
        }
    }

    private var cacheBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            Text("Взято из кэша")
                .font(UIStyleFont.body(size: 12, weight: .regular))
                .foregroundColor(.uiMidGray)
            Spacer()
            Button("Перегенерировать") {
                regenerate()
            }
            .font(UIStyleFont.body(size: 12, weight: .medium))
            .foregroundColor(.uiInk)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.uiSidebar)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.uiHairline, lineWidth: 1))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        SoundEffect.playCopy()
        withAnimation(.spring()) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(.spring()) { copied = false } }
    }
}

struct AIThinkingOrb: View {
    let icon: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Color.uiInk.opacity(0.05)).frame(width: 64, height: 64)
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.uiInk)
            Circle()
                .stroke(Color.uiInk.opacity(0.25), lineWidth: 1.5)
                .frame(width: 64, height: 64)
                .scaleEffect(pulse ? 1.4 : 0.9)
                .opacity(pulse ? 0 : 1)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
