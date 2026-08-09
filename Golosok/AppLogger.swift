import Foundation
import SwiftUI

enum LogLevel: Int, Comparable, CaseIterable {
    case info = 0
    case warn = 1
    case error = 2

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let source: String
    let message: String
    let details: String?
}

final class AppLogger: ObservableObject {

    static let shared = AppLogger()

    @Published private(set) var entries: [LogEntry] = []

    private let maxInMemory = 500
    private let maxFileBytes = 2 * 1024 * 1024
    private let ioQueue = DispatchQueue(label: "Golosok.AppLogger.io")
    private let fileURL: URL?
    private var fileHandle: FileHandle?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        var url: URL?
        if let base {
            let dir = base.appendingPathComponent("Golosok/Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("app.log")
        }
        self.fileURL = url
        loadTailFromFile()
    }

    var logFileURL: URL? { fileURL }

    // MARK: - API

    func info(_ source: String, _ message: String, details: String? = nil) {
        log(.info, source: source, message: message, details: details)
    }

    func warn(_ source: String, _ message: String, details: String? = nil) {
        log(.warn, source: source, message: message, details: details)
    }

    func error(_ source: String, _ message: String, details: String? = nil) {
        log(.error, source: source, message: message, details: details)
    }

    func log(_ level: LogLevel, source: String, message: String, details: String? = nil) {
        let entry = LogEntry(timestamp: Date(), level: level, source: source, message: message, details: details)
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxInMemory {
                self.entries = Array(self.entries.prefix(self.maxInMemory))
            }
        }
        writeToDisk(entry)
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
        ioQueue.async { [weak self] in self?.resetFile() }
    }

    // MARK: Disk

    private func loadTailFromFile() {
        guard let fileURL else { return }
        ioQueue.async { [weak self] in
            guard let self, let data = try? Data(contentsOf: fileURL) else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n").suffix(200)
            let parsed: [LogEntry] = lines.compactMap { line -> LogEntry? in
                guard let obj = try? JSONSerialization.jsonObject(with: Data(String(line).utf8)) as? [String: Any],
                      let msg = obj["message"] as? String,
                      let src = obj["source"] as? String else { return nil }
                let lvl = (obj["level"] as? String).flatMap { s in
                    LogLevel.allCases.compactMap { $0.label.lowercased() == s.lowercased() ? $0 : nil }.first
                } ?? .info
                return LogEntry(timestamp: Date(), level: lvl, source: src, message: msg, details: obj["detail"] as? String)
            }
            DispatchQueue.main.async {
                self.entries = Array(parsed.reversed().prefix(self.maxInMemory))
            }
        }
    }

    private func writeToDisk(_ entry: LogEntry) {
        var obj: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: entry.timestamp),
            "level": entry.level.label,
            "source": entry.source,
            "message": entry.message
        ]
        if let d = entry.details { obj["detail"] = d }
        guard let line = (try? JSONSerialization.data(withJSONObject: obj)) else { return }
        ioQueue.async { [weak self] in self?.appendLine(line) }
    }

    private func appendLine(_ line: Data) {
        guard let fileURL else { return }
        do {
            var handle = fileHandle
            if handle == nil {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
                }
                let h = try FileHandle(forWritingTo: fileURL)
                h.seekToEndOfFile()
                handle = h
                fileHandle = h
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if size > maxFileBytes { resetAndReopen() }
            handle?.seekToEndOfFile()
            handle?.write(line)
            handle?.write(Data([0x0A]))
        } catch {
            try? (line + Data([0x0A])).write(to: fileURL, options: .atomic)
        }
    }

    private func resetAndReopen() {
        fileHandle?.closeFile()
        fileHandle = nil
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }

    private func resetFile() {
        fileHandle?.closeFile()
        fileHandle = nil
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct LogFilter: OptionSet {
    let rawValue: Int
    static let info = LogFilter(rawValue: 1 << 0)
    static let warn = LogFilter(rawValue: 1 << 1)
    static let error = LogFilter(rawValue: 1 << 2)
}