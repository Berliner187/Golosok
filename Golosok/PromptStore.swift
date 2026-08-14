import Foundation
import Combine

final class PromptStore: ObservableObject {
    static let shared = PromptStore()

    @Published private(set) var templates: [AIPromptTemplate] = []

    private let ioQueue = DispatchQueue(label: "Golosok.PromptStore.io")
    private static let migrationsKey = "promptstore.migrated.v1"

    private init() { load() }

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Golosok", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("prompts.json")
    }

    // MARK: - Public API

    @discardableResult
    func create(title: String, icon: String, system: String) -> String {
        let id = UUID().uuidString
        let prompt = AIPromptTemplate(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.isEmpty ? "sparkles" : icon,
            system: system.trimmingCharacters(in: .whitespacesAndNewlines),
            isProtected: false,
            isCustom: true,
            createdAt: Date()
        )
        templates.append(prompt)
        persist()
        return id
    }

    func update(_ updated: AIPromptTemplate) {
        guard let idx = templates.firstIndex(where: { $0.id == updated.id }) else { return }
        var p = updated
        p.isProtected = templates[idx].isProtected            // флаг защищённости неизменен
        p.createdAt = templates[idx].createdAt               // сохраняем дату
        p.isCustom = true                                     // после правки показываем как пользовательский
        p.title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
        p.system = p.system.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.icon.trimmingCharacters(in: .whitespaces).isEmpty { p.icon = templates[idx].icon }
        templates[idx] = p
        AICache.shared.invalidate(templateID: p.id)
        persist()
    }

    func delete(id: String) {
        guard let idx = templates.firstIndex(where: { $0.id == id }), !templates[idx].isProtected else { return }
        AICache.shared.invalidate(templateID: id)
        templates.remove(at: idx)
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        templates.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Сброс встроенного промпта к заводским значениям.
    func reset(id: String) {
        guard AIPromptDefaults.builtinIDs.contains(id),
              let def = AIPromptDefaults.template(id: id),
              let idx = templates.firstIndex(where: { $0.id == id }) else { return }
        var d = def
        d.createdAt = templates[idx].createdAt
        templates[idx] = d
        AICache.shared.invalidate(templateID: id)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = templates
        ioQueue.async { [weak self] in
            guard let self, let url = self.fileURL else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AIPromptTemplate].self, from: data) else {
            templates = AIPromptDefaults.defaults
            persist()
            return
        }
        templates = decoded

        // Миграция: гарантировать наличие защищённого встроенного промпта,
        // если файл хранилища повредился/был обрезан (защита от вырождения).
        if !templates.contains(where: { $0.isProtected }) {
            templates.insert(AIPromptDefaults.defaults.first(where: { $0.isProtected })!, at: 0)
            persist()
        }
    }
}