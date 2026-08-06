import Foundation

struct RecognitionModel: Identifiable {
    let id: String
    let name: String
    let systemName: String
    let languageCode: String
    let fileName: String
    let isBundled: Bool
    let sizeMB: Int
    let downloadURL: URL?
}

extension RecognitionModel {
    static let russianGigaAM = RecognitionModel(
        id: "ru_giga",
        name: "RecognitionModel.Russian",
        systemName: "GigaAM",
        languageCode: "ru",
        fileName: "gigaam",
        isBundled: true,
        sizeMB: 273,
        downloadURL: nil
    )
    static let englishTurbo = RecognitionModel(
        id: "en_turbo",
        name: "RecognitionModel.EnglishTurbo",
        systemName: "Whisper Large-v3 Turbo",
        languageCode: "en",
        fileName: "ggml-large-v3-turbo-q8_0.bin",
        isBundled: false,
        sizeMB: 820,
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin")
    )
    static let englishMedium = RecognitionModel(
        id: "en_medium",
        name: "RecognitionModel.EnglishMedium",
        systemName: "Whisper Medium (Q5)",
        languageCode: "en",
        fileName: "ggml-medium-q5_0.bin",
        isBundled: false,
        sizeMB: 510,
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin")
    )
}

final class ModelStore: NSObject, ObservableObject {
    static let shared = ModelStore()

    static let catalog: [RecognitionModel] = [.russianGigaAM, .englishTurbo, .englishMedium]

    @Published var downloadingID: String?
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus = ""
    @Published var downloadFailed = false

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    var activeModelID: String {
        get { UserDefaults.standard.string(forKey: "recognized.activeModel") ?? RecognitionModel.russianGigaAM.id }
        set {
            UserDefaults.standard.set(newValue, forKey: "recognized.activeModel")
            objectWillChange.send()
        }
    }

    func model(named id: String) -> RecognitionModel? {
        Self.catalog.first { $0.id == id } ?? Self.catalog.first { $0.name == id }
    }

    private var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Golosok/Models", isDirectory: true)
    }

    func localModelPath(for id: String) -> String? {
        guard let model = model(named: id) else { return nil }
        if model.isBundled {
            return Bundle.main.path(forResource: model.fileName, ofType: model.id == "ru_giga" ? "gguf" : nil)
        }
        let path = modelsDir.appendingPathComponent(model.fileName).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    func isDownloaded(_ id: String) -> Bool {
        guard let model = model(named: id), !model.isBundled else { return true }
        return FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent(model.fileName).path)
    }

    func download(_ id: String) {
        guard let model = model(named: id), let url = model.downloadURL, !isDownloaded(id) else { return }
        downloadFailed = false
        downloadStatus = "DownloadStatus.Connecting"
        downloadingID = id
        downloadProgress = 0
        task = session?.downloadTask(with: url)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        downloadingID = nil
        downloadStatus = ""
    }

    func remove(_ id: String) {
        guard let model = model(named: id), !model.isBundled else { return }
        let path = modelsDir.appendingPathComponent(model.fileName).path
        if FileManager.default.fileExists(atPath: path) { try? FileManager.default.removeItem(atPath: path) }
        if activeModelID == id { activeModelID = RecognitionModel.russianGigaAM.id }
        objectWillChange.send()
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        DispatchQueue.main.async {
            self.downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let mbW = Double(totalBytesWritten) / (1024.0 * 1024.0)
            let mbT = Double(totalBytesExpectedToWrite) / (1024.0 * 1024.0)
            let pct = Int(self.downloadProgress * 100.0)
            self.downloadStatus = String(format: "%.0f / %.0f МБ (%d%%)", mbW, mbT, pct)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadingID
        guard let id, let model = self.model(named: id), !model.isBundled else {
            DispatchQueue.main.async { self.downloadingID = nil; self.downloadStatus = "" }
            return
        }
        do {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            let dest = modelsDir.appendingPathComponent(model.fileName)
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.downloadingID = nil
                self.downloadStatus = "DownloadStatus.Ready"
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadingID = nil
                self.downloadStatus = "DownloadStatus.Failed"
                self.downloadFailed = true
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.downloadingID = nil
            self.downloadStatus = "DownloadStatus.Failed"
            self.downloadFailed = true
        }
    }
}