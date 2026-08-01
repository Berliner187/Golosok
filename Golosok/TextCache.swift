import Foundation

class TextCache {
    static let shared = TextCache()
    
    // Потокобезопасный словарь в памяти
    private var memoryCache: [UUID: String] = [:]
    private let lock = NSLock()
    
    func getFormattedText(id: UUID, rawText: String) async -> String {
        // 1. Быстрая проверка кэша за 0.00001 мс
        lock.lock()
        if let cached = memoryCache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // 2. Если в кэше нет — форматируем 1 раз в фоновом потоке
        let formatted = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                return TextFormatter.formatIntoParagraphs(rawText)
            }
        }.value
        
        // 3. Сохраняем в кэш
        lock.lock()
        memoryCache[id] = formatted
        lock.unlock()
        
        return formatted
    }
    
    func clear() {
        lock.lock()
        memoryCache.removeAll()
        lock.unlock()
    }
}
