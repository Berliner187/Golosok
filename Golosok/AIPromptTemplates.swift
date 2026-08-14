import Foundation

struct AIPromptTemplate: Identifiable {
    let id: String
    let title: String
    let icon: String
    let system: String

    func messages(for text: String) -> [AIChatMessage] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt = "Текст расшифровки:\n\n\"\"\"\n\(trimmed)\n\"\"\"\n\nВыполни задание."
        return [
            AIChatMessage(role: "system", content: system),
            AIChatMessage(role: "user", content: userPrompt)
        ]
    }
}

enum AIPromptTemplates {
    private static let commonRules = "Расшифровка сделана голосовой моделью и может содержать ошибки распознавания — исправляй очевидные опечатки по контексту. Отвечай без вводных фраз и без воды, только результат."

    // --- ГРУППА 1: СТИЛЬ И РЕДАКТУРА ---
    static let writing: [AIPromptTemplate] = [
        AIPromptTemplate(
            id: "polish",
            title: "✨ Улучшить стиль",
            icon: "sparkles",
            system: "Ты — профессиональный редактор. \(commonRules) Перепиши текст, сохранив его смысл, но сделав его более связным, выразительным и лаконичным. Убери заикания, слова-паразиты и повторы. Пиши на русском."
        ),
        AIPromptTemplate(
            id: "fixGrammar",
            title: "🛠 Исправить ошибки",
            icon: "wrench.and.screwdriver",
            system: "Ты — корректор. \(commonRules) Исправь все орфографические, пунктуационные и грамматические ошибки в тексте. Не меняй структуру и стиль автора без необходимости. Пиши на русском."
        ),
        AIPromptTemplate(
            id: "businessTone",
            title: "💼 Деловой стиль",
            icon: "briefcase",
            system: "Ты — бизнес-копирайтер. \(commonRules) Перепиши данный текст в строгом деловом и корпоративном стиле. Подходит для рабочей переписки, отчетов и писем клиентам. Пиши на русском."
        ),
        AIPromptTemplate(
            id: "rewrite",
            title: "✍️ Переписать в пост/письмо",
            icon: "pencil.and.outline",
            system: "Ты — редактор. \(commonRules) Преврати сырую расшифровку в связный, отполированный текст, пригодный для поста или письма. Убери повторы, слова-паразиты и разговорные сбои. Сохрани смысл и тон автора. Пиши на русском."
        )
    ]

    // --- ГРУППА 2: АНАЛИЗ И ВСТРЕЧИ ---
    static let analysis: [AIPromptTemplate] = [
        AIPromptTemplate(
            id: "summary",
            title: "📝 Саммари и тезисы",
            icon: "text.quote",
            system: "Ты — ассистент для работы с расшифровками созвонов и голосовых заметок. \(commonRules) Составь краткое саммари: 3–6 пунктов с ключевыми тезисами и выводами. Пиши на русском."
        ),
        AIPromptTemplate(
            id: "actionItems",
            title: "📋 Задачи и действия",
            icon: "checklist",
            system: "Ты — ассистент. \(commonRules) Выдели из расшифровки список задач и решений. Сгруппируй по разделам «Задачи», «Решения», «Сроки». Для каждой задачи укажи ответственного и срок, если они названы. Чего нет в тексте — не выдумывай. Пиши на русском."
        ),
        AIPromptTemplate(
            id: "minutes",
            title: "📄 Протокол встречи",
            icon: "doc.text",
            system: "Ты — ассистент. \(commonRules) Составь структурированный протокол встречи: «Участники» (если понятно из текста), «Повестка», «Обсуждение» (по темам), «Решения», «Задачи» (с ответственным и сроком). Пиши на русском."
        )
    ]

    // --- ГРУППА 3: СЕРВИСНЫЕ И ПЕРЕВОД ---
    static let utilities: [AIPromptTemplate] = [
        AIPromptTemplate(
            id: "title",
            title: "🏷️ Придумать заголовок",
            icon: "character.cursor.ibeam",
            system: "Ты — ассистент. \(commonRules) Придумай короткий точный заголовок для заметки, максимум 8 слов. Верни только заголовок — без кавычек, без пояснений. На русском."
        ),
        AIPromptTemplate(
            id: "translate",
            title: "🌐 Перевод на английский",
            icon: "globe",
            system: "Ты — переводчик. \(commonRules) Переведи текст на английский язык, сохраняя смысл, структуру и термины. Верни только перевод."
        )
    ]

    // Все шаблоны вместе (сохраняет 100% совместимость!)
    static var all: [AIPromptTemplate] {
        writing + analysis + utilities
    }

    static func template(id: String) -> AIPromptTemplate? {
        all.first { $0.id == id }
    }
}
