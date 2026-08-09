import Foundation

final class Telemetry: NSObject {

    static let shared = Telemetry()

    private static let endpoint = URL(string: "https://golosok.space/api/v1/telemetry/")!
    private let queue = DispatchQueue(label: "Golosok.Telemetry")
    private let session: URLSession
    private var pending: [[String: Any]] = []
    private var flushWorkItem: DispatchWorkItem?
    private let maxRetries = 3

    private override init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        session = URLSession(configuration: cfg)
        super.init()
    }

    var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool) ?? true
    }

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "anonymous_device_id") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "anonymous_device_id")
        return id
    }

    func event(_ type: String, _ fields: [String: Any] = [:]) {
        guard isEnabled else { return }
        var payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "device_id": deviceID,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "event_type": type
        ]
        payload.merge(fields) { _, new in new }
        queue.async { [weak self] in
            guard let self else { return }
            self.pending.append(payload)
            if self.pending.count >= 5 { self.scheduleFlush(delay: 0.2) } else { self.scheduleFlush(delay: 1.0) }
        }
    }

    private func scheduleFlush(delay: TimeInterval) {
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.performFlush() }
        flushWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func performFlush() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)

        var request = URLRequest(url: Telemetry.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: batch) else { return }
        request.httpBody = data

        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            if !ok {
                self.requeue(batch)
            }
        }.resume()
    }

    private func requeue(_ batch: [[String: Any]]) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.pending.count + batch.count < 200 {
                self.pending.insert(contentsOf: batch, at: 0)
                self.scheduleFlush(delay: 5.0)
            }
        }
    }
}