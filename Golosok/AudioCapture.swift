import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import ServiceManagement

// MARK: - Системные звуки
struct SoundEffect {
    static func playStart() { guard AudioCapture.shared.soundEnabled else { return }; NSSound(named: "Pop")?.play() }
    static func playSuccess() { guard AudioCapture.shared.soundEnabled else { return }; NSSound(named: "Tink")?.play() }
    static func playCancel() { guard AudioCapture.shared.soundEnabled else { return }; NSSound(named: "Basso")?.play() }
}

struct UpdateInfo {
    let version: String
    let codename: String
    let url: URL
}

struct TranscriptionItem: Identifiable, Codable {
    var id = UUID()
    let date: String
    let text: String
    let duration: String
    var speedup: Double?
    
    var formattedSpeedup: String {
        if let s = speedup, s > 0 { return String(format: "x%.0f", s) }
        return "x28"
    }
}

class AudioCapture: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = AudioCapture()
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private var escMonitor: Any?
    
    @Published var isRecording = false
    @Published var isProcessingFile = false
    @Published var fileProcessingProgress: Double = 0.0
    @Published var audioSamples: [Float] = Array(repeating: 0.15, count: 9)
    @Published var transcribedText = ""
    
    @Published var updateInfo: UpdateInfo? = nil
    @Published var isDownloadingUpdate = false
    private var downloadTask: URLSessionDownloadTask?
    
    @Published var playingItemId: UUID? = nil
    private var audioPlayer: AVAudioPlayer?
    
    @Published var soundEnabled: Bool = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var autoPasteEnabled: Bool = UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled") }
    }
    @Published var launchAtLoginEnabled: Bool = UserDefaults.standard.bool(forKey: "launchAtLoginEnabled") {
        didSet {
            UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
            setLaunchAtLogin(enabled: launchAtLoginEnabled)
        }
    }
    
    @Published var history: [TranscriptionItem] = [] {
        didSet { saveHistory() }
    }
    
    private let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_record.wav")
    
    override init() {
        super.init()
        loadHistory()
        checkUpdates()
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {}
        }
    }
    
    func toggleRecording() {
        if isRecording { stopRecording() }
        else { startRecording() }
    }
    
    func cancelRecording() {
        removeEscMonitor()
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        SoundEffect.playCancel()
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioSamples = Array(repeating: 0.15, count: 9)
            self.transcribedText = "Запись отменена"
            OverlayPanelManager.shared.hideOverlay()
        }
    }
    
    func startRecording() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted { DispatchQueue.main.async { self.startRecording() } }
            }
            return
        case .denied, .restricted:
            DispatchQueue.main.async { self.transcribedText = "Нет доступа к микрофону." }
            return
        case .authorized: break
        @unknown default: break
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false
        ]
        
        do {
            if FileManager.default.fileExists(atPath: tempAudioURL.path) { try FileManager.default.removeItem(at: tempAudioURL) }
            audioRecorder = try AVAudioRecorder(url: tempAudioURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            guard audioRecorder?.record() == true else { return }
            
            startTime = Date()
            SoundEffect.playStart()
            
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.cancelRecording() }
            }
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.transcribedText = "Запись идет..."
                OverlayPanelManager.shared.showOverlay()
            }
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateMetering() }
        } catch {}
    }
    
    func stopRecording() {
        removeEscMonitor()
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        let durationSec = Date().timeIntervalSince(startTime ?? Date())
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.isProcessingFile = true
            self.fileProcessingProgress = 0.0
            self.audioSamples = Array(repeating: 0.15, count: 9)
            self.transcribedText = "Расшифровка..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.processLongFileInChunks(fileURL: self.tempAudioURL, isFileImport: false, audioDurationSec: durationSec)
        }
    }
    
    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
    
    private func updateMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let level = max(0.15, min(1.0, (power + 40.0) / 35.0))
        
        var newSamples: [Float] = []
        for i in 0..<9 {
            let randomFactor = Float.random(in: 0.7...1.3)
            let targetVal = max(0.15, min(1.0, level * randomFactor))
            let currentVal = i < audioSamples.count ? audioSamples[i] : 0.15
            newSamples.append(currentVal * 0.4 + targetVal * 0.6)
        }
        DispatchQueue.main.async { self.audioSamples = newSamples }
    }
    
    func importAndTranscribeFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie, .mp3, .mpeg4Audio, .wav]
        
        if panel.runModal() == .OK, let fileURL = panel.url {
            DispatchQueue.main.async {
                self.isProcessingFile = true
                self.fileProcessingProgress = 0.0
                self.transcribedText = "Подготовка файла..."
                OverlayPanelManager.shared.showOverlay()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.processLongFileInChunks(fileURL: fileURL, isFileImport: true, audioDurationSec: 0)
            }
        }
    }
    
    private func processLongFileInChunks(fileURL: URL, isFileImport: Bool, audioDurationSec: Double) {
        let processStartTime = Date()
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_file_full.wav")
        let sourceURL = isFileImport ? tempWavURL : fileURL
        
        if isFileImport {
            guard convertAudioTo16kHzWav(inputURL: fileURL, outputURL: tempWavURL) else {
                DispatchQueue.main.async {
                    self.isProcessingFile = false
                    self.transcribedText = "Ошибка чтения файла"
                    OverlayPanelManager.shared.hideOverlay()
                }
                return
            }
        }
        
        guard let inputFile = try? AVAudioFile(forReading: sourceURL) else { return }
        
        let totalFrames = inputFile.length
        let sampleRate = inputFile.processingFormat.sampleRate
        let realAudioSecs = isFileImport ? (Double(totalFrames) / sampleRate) : audioDurationSec
        
        let durationFormatted: String
        if realAudioSecs >= 60.0 {
            durationFormatted = String(format: "%.0f мин", realAudioSecs / 60.0)
        } else {
            durationFormatted = String(format: "%.1f сек", realAudioSecs)
        }
        
        let chunkSizeInSeconds: Double = 25.0
        let framesPerChunk = AVAudioFrameCount(chunkSizeInSeconds * sampleRate)
        let totalChunks = max(1, Int(ceil(Double(totalFrames) / Double(framesPerChunk))))
        
        var accumulatedText: [String] = []
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        for chunkIndex in 0..<totalChunks {
            autoreleasepool {
                let startFrame = Int64(chunkIndex) * Int64(framesPerChunk)
                let frameCountToRead = min(framesPerChunk, AVAudioFrameCount(totalFrames - startFrame))
                
                inputFile.framePosition = startFrame
                guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: frameCountToRead) else { return }
                try? inputFile.read(into: pcmBuffer, frameCount: frameCountToRead)
                
                let chunkWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_chunk_\(chunkIndex).wav")
                
                if writeBufferToWav(buffer: pcmBuffer, targetFormat: targetFormat, outputURL: chunkWavURL) {
                    let chunkText = runCLIOnWav(wavURL: chunkWavURL)
                    if !chunkText.isEmpty && chunkText != "Речь не распознана" {
                        accumulatedText.append(chunkText)
                    }
                    try? FileManager.default.removeItem(at: chunkWavURL)
                }
                
                DispatchQueue.main.async {
                    self.fileProcessingProgress = Double(chunkIndex + 1) / Double(totalChunks)
                }
            }
        }
        
        let rawText = accumulatedText.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let processingTimeSecs = Date().timeIntervalSince(processStartTime)
        let calculatedSpeedup = max(1.0, realAudioSecs / max(0.1, processingTimeSecs))
        
        DispatchQueue.main.async {
            self.isProcessingFile = false
            if rawText.isEmpty {
                self.transcribedText = isFileImport ? "В файле не распознана речь" : "Речь не распознана"
            } else {
                self.transcribedText = rawText
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy, HH:mm"
                let dateStr = formatter.string(from: Date())
                
                let newItem = TranscriptionItem(date: dateStr, text: rawText, duration: durationFormatted, speedup: calculatedSpeedup)
                
                self.saveAudioForNote(id: newItem.id, sourceURL: sourceURL)
                self.history.insert(newItem, at: 0)
                
                let prettyText = TextFormatter.formatIntoParagraphs(rawText)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyText, forType: .string)
                if !isFileImport { self.pasteToActiveApp() }
            }
            
            if isFileImport { SoundEffect.playSuccess() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                OverlayPanelManager.shared.hideOverlay()
            }
        }
    }

    private func saveAudioForNote(id: UUID, sourceURL: URL) {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let audioDir = appSupport.appendingPathComponent("Golosok/Audio", isDirectory: true)
        
        try? fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let destURL = audioDir.appendingPathComponent("\(id.uuidString).wav")
        
        if fm.fileExists(atPath: destURL.path) { try? fm.removeItem(at: destURL) }
        try? fm.copyItem(at: sourceURL, to: destURL)
    }
    
    func hasAudioFile(for item: TranscriptionItem) -> Bool {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let fileURL = appSupport.appendingPathComponent("Golosok/Audio/\(item.id.uuidString).wav")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    func toggleAudioPlayback(for item: TranscriptionItem) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let fileURL = appSupport.appendingPathComponent("Golosok/Audio/\(item.id.uuidString).wav")
        
        if playingItemId == item.id {
            audioPlayer?.stop()
            playingItemId = nil
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.play()
            playingItemId = item.id
        } catch {}
    }
    
    // ИСПРАВЛЕННЫЙ БЕЗОПАСНЫЙ КОНВЕРТЕР БЕЗ КРАША
    private func convertAudioTo16kHzWav(inputURL: URL, outputURL: URL) -> Bool {
        guard let inputFile = try? AVAudioFile(forReading: inputURL) else { return false }
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
            guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: targetFormat) else { return false }
            
            let bufferSize: AVAudioFrameCount = 8192
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: bufferSize) else { return false }
            
            let ratio = 16000.0 / inputFile.processingFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(bufferSize) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { return false }
            
            let totalFrames = inputFile.length
            var currentFrame: AVAudioFramePosition = 0
            var hasError = false
            
            while currentFrame < totalFrames && !hasError {
                autoreleasepool {
                    let framesToRead = min(bufferSize, AVAudioFrameCount(totalFrames - currentFrame))
                    if framesToRead == 0 {
                        currentFrame = totalFrames
                        return
                    }
                    
                    do {
                        try inputFile.read(into: inputBuffer, frameCount: framesToRead)
                    } catch {
                        hasError = true
                        return
                    }
                    
                    let framesRead = inputBuffer.frameLength
                    if framesRead == 0 {
                        currentFrame = totalFrames
                        return
                    }
                    
                    currentFrame += Int64(framesRead)
                    var error: NSError?
                    var allConsumed = false
                    
                    let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                        if allConsumed { outStatus.pointee = .noDataNow; return nil }
                        allConsumed = true
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                    
                    if status != .error && error == nil {
                        try? outputFile.write(from: outputBuffer)
                    } else {
                        hasError = true
                    }
                }
            }
            return !hasError
        } catch {
            return false
        }
    }
    
    private func writeBufferToWav(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat, outputURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            let file = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
            try file.write(from: buffer)
            return true
        } catch { return false }
    }
    
    private func runCLIOnWav(wavURL: URL) -> String {
        guard let cliPath = Bundle.main.path(forResource: "transcribe-cli", ofType: nil),
              let modelPath = Bundle.main.path(forResource: "gigaam", ofType: "gguf") else { return "" }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-m", modelPath, wavURL.path]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: data, encoding: .utf8) ?? ""
            let lines = rawOutput.components(separatedBy: .newlines)
            
            if let textLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("text:") }) {
                let extracted = String(textLine.trimmingCharacters(in: .whitespaces).dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if extracted != "(empty)" { return extracted }
            }
            return ""
        } catch { return "" }
    }
    
    private func pasteToActiveApp() {
        guard autoPasteEnabled else { SoundEffect.playSuccess(); return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        SoundEffect.playSuccess()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    func exportTranscription(_ item: TranscriptionItem, format: String) {
        let panel = NSSavePanel()
        panel.title = "Сохранить транскрипцию"
        panel.nameFieldStringValue = "Заметка_\(item.date.replacingOccurrences(of: ":", with: "-")).\(format)"
        
        if panel.runModal() == .OK, let saveURL = panel.url {
            var content = ""
            let prettyText = TextFormatter.formatIntoParagraphs(item.text)
            switch format.lowercased() {
            case "md": content = "# Транскрипция Голосок\n**Дата:** \(item.date)\n**Длительность:** \(item.duration)\n\n---\n\n\(prettyText)"
            case "txt": content = "Голосок — Транскрипция\nДата: \(item.date)\nДлительность: \(item.duration)\n\n\(prettyText)"
            case "csv": content = "\"Дата\",\"Длительность\",\"Текст\"\n\"\(item.date)\",\"\(item.duration)\",\"\(item.text.replacingOccurrences(of: "\"", with: "\"\""))\""
            case "json":
                let dict: [String: Any] = ["id": item.id.uuidString, "date": item.date, "duration": item.duration, "text": item.text]
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) { content = String(data: data, encoding: .utf8) ?? "" }
            default: content = prettyText
            }
            try? content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }
    
    func checkUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/Berliner187/Golosok/releases/latest") else { return }
        let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0"
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let releaseName = json["name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let firstAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                  let downloadUrlString = firstAsset["browser_download_url"] as? String,
                  let downloadUrl = URL(string: downloadUrlString) else { return }
            
            let cleanCurrent = currentVer.replacingOccurrences(of: "v", with: "")
            let cleanLatest = tagName.replacingOccurrences(of: "v", with: "")
            
            if cleanLatest.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                DispatchQueue.main.async {
                    let codename = releaseName.components(separatedBy: " ").last ?? "UPDATE"
                    self.updateInfo = UpdateInfo(version: tagName, codename: codename.uppercased(), url: downloadUrl)
                }
            } else {
                DispatchQueue.main.async { self.updateInfo = nil }
            }
        }.resume()
    }
    
    func cancelUpdateDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        DispatchQueue.main.async {
            self.isDownloadingUpdate = false
        }
    }
    
    func downloadAndInstallUpdate() {
        guard let updateUrl = updateInfo?.url else { return }
        DispatchQueue.main.async { self.isDownloadingUpdate = true }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Golosok_Update.dmg")
        if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
        
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        downloadTask = session.downloadTask(with: updateUrl) { tempURL, _, _ in
            DispatchQueue.main.async { self.isDownloadingUpdate = false }
            guard let tempURL = tempURL else { return }
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                process.arguments = ["attach", dest.path]
                try process.run()
            } catch {}
        }
        downloadTask?.resume()
    }
    
    func deleteItem(at index: Int) { history.remove(at: index) }
    func clearAllHistory() { history.removeAll() }
    private func saveHistory() { if let e = try? JSONEncoder().encode(history) { UserDefaults.standard.set(e, forKey: "transcription_history") } }
    private func loadHistory() { if let d = UserDefaults.standard.data(forKey: "transcription_history"), let dec = try? JSONDecoder().decode([TranscriptionItem].self, from: d) { self.history = dec } }
}
