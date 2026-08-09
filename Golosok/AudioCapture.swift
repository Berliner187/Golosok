import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import ServiceManagement

// MARK: - Кастомная акустическая айдентика
struct SoundEffect {
    static func playStart() { LuxurySoundSynth.shared.playStart() }
    static func playSuccess() { LuxurySoundSynth.shared.playSuccess() }
    static func playCancel() { LuxurySoundSynth.shared.playCancel() }
    static func playCopy() { LuxurySoundSynth.shared.playCopy() }
    static func playDelete() { LuxurySoundSynth.shared.playDelete() }
    static func playWarning() { LuxurySoundSynth.shared.playWarning() }
}

struct UpdateInfo: Codable {
    let version: String
    let codename: String
    let url: URL
}

struct TranscriptionItem: Identifiable, Codable, Hashable {
    var id = UUID()
    let date: String
    let text: String
    let duration: String
    var speedup: Double?
    var isUnread: Bool? = false
    
    var formattedSpeedup: String {
        if let s = speedup, s > 0 { return String(format: "x%.0f", s) }
        return "x1"
    }
}

class AudioCapture: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = AudioCapture()
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    private var escMonitor: Any?
    private var pasteTarget: NSRunningApplication?
    
    @Published var isRecording = false
    @Published var isProcessingFile = false
    @Published var fileProcessingProgress: Double = 0.0
    @Published var transcribedText = ""
    @Published var warningMessage: String? = nil
    @Published var audioSamples: [Float] = Array(repeating: 0.15, count: 18)
    @Published var formattedRecordingTime: String = "00:00"
    
    // АПДЕЙТЫ
    @Published var updateInfo: UpdateInfo? = nil
    @Published var isDownloadingUpdate = false
    @Published var updateProgressText: String = ""
    private var downloadTask: URLSessionDownloadTask?
    
    @Published var playingItemId: UUID? = nil
    private var audioPlayer: AVAudioPlayer?
    
    @Published var isSuccessDone = false
    
    @Published var soundEnabled: Bool = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var autoPasteEnabled: Bool = UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPasteEnabled") }
    }
    @Published var analyticsEnabled: Bool = UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(analyticsEnabled, forKey: "analyticsEnabled") }
    }
    @Published var launchAtLoginEnabled: Bool = UserDefaults.standard.bool(forKey: "launchAtLoginEnabled") {
        didSet {
            UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
            setLaunchAtLogin(enabled: launchAtLoginEnabled)
        }
    }
    
    @Published var autoOpenNoteEnabled: Bool = UserDefaults.standard.object(forKey: "autoOpenNoteEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoOpenNoteEnabled, forKey: "autoOpenNoteEnabled") }
    }
    
    @Published var history: [TranscriptionItem] = [] {
        didSet {
            guard !isLoadingHistory else { return }
            saveHistory()
            DashboardStatsStore.shared.refresh(history: history)
        }
    }
    
    private var isLoadingHistory = false
    
    private let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_record.wav")
    
    override init() {
        super.init()
        
        if UserDefaults.standard.object(forKey: "analyticsEnabled") == nil {
            self.analyticsEnabled = true
        }
        
        loadHistory()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            self?.checkUpdates()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard self != nil else { return }
            let launchCount = UserDefaults.standard.integer(forKey: "launch_count") + 1
            UserDefaults.standard.set(launchCount, forKey: "launch_count")
            Telemetry.shared.event("app_launch", [
                "launch_count": launchCount,
                "mic_granted": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                "accessibility_granted": PermissionManager.shared.isAccessibilityGranted,
                "model_id": ModelStore.shared.activeModelID
            ])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self else { return }
            DashboardStatsStore.shared.refresh(history: self.history)
        }
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
        if isProcessingFile {
            SoundEffect.playCancel()
            return
        }
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
            self.warningMessage = nil
            self.isRecording = false
            self.audioSamples = Array(repeating: 0.15, count: 9)
            self.transcribedText = String(localized: "Запись отменена")
            OverlayPanelManager.shared.hideOverlay()
        }
    }
    
    func startRecording() {
        guard !isProcessingFile else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted { DispatchQueue.main.async { self.startRecording() } }
            }
            return
        case .denied, .restricted:
            DispatchQueue.main.async { self.transcribedText = String(localized: "Нет доступа к микрофону.") }
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
            AppLogger.shared.info("Recording", "Запись началась", details: "режим: \(HotKeySettings.shared.mode == .pushToTalk ? "рация" : "переключатель")")
            
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.cancelRecording() }
            }
            
            DispatchQueue.main.async {
                self.warningMessage = nil
                self.isRecording = true
                self.transcribedText = String(localized: "Запись идет...")
                OverlayPanelManager.shared.showOverlay()
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateMetering() }
        } catch {}
    }
    
    func stopRecording() {
        removeEscMonitor()
        pasteTarget = NSWorkspace.shared.frontmostApplication
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        let durationSec = Date().timeIntervalSince(startTime ?? Date())
        
        AppLogger.shared.info("Recording", "Запись остановлена", details: String(format: "длительность %.1f с, цель вставки: %@", durationSec, NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"))
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.isProcessingFile = false
            self.fileProcessingProgress = 0.0
            self.audioSamples = Array(repeating: 0.15, count: 9)
            self.transcribedText = String(localized: "Расшифровка...")
        }
        
        DispatchQueue.global(qos: .utility).async {
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
        
        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        let mins = elapsed / 60
        let secs = elapsed % 60
        let timeStr = String(format: "%02d:%02d", mins, secs)
        
        let power = recorder.averagePower(forChannel: 0)
        let level = max(0.15, min(1.0, (power + 40.0) / 35.0))
        
        var newSamples: [Float] = []
        for i in 0..<18 {
            let randomFactor = Float.random(in: 0.7...1.3)
            let targetVal = max(0.15, min(1.0, level * randomFactor))
            let currentVal = i < audioSamples.count ? audioSamples[i] : 0.15
            newSamples.append(currentVal * 0.35 + targetVal * 0.65)
        }
        
        DispatchQueue.main.async {
            self.formattedRecordingTime = timeStr
            self.audioSamples = newSamples
        }
    }

    func importAndTranscribeFile() {
        if isRecording || isProcessingFile {
            SoundEffect.playCancel()
            return
        }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let webmType = UTType(filenameExtension: "webm") ?? .movie
        let mkvType = UTType(filenameExtension: "mkv") ?? .movie
        let oggType = UTType(filenameExtension: "ogg") ?? .audio
        panel.allowedContentTypes = [.audio, .movie, .mp3, .mpeg4Audio, .wav, webmType, mkvType, oggType]
        
        if panel.runModal() == .OK, let fileURL = panel.url {
            DispatchQueue.main.async {
                self.warningMessage = nil
                self.isProcessingFile = true
                self.fileProcessingProgress = 0.0
                self.transcribedText = String(localized: "Извлечение аудио...")
                OverlayPanelManager.shared.showOverlay()
            }
            DispatchQueue.global(qos: .utility).async {
                self.processLongFileInChunks(fileURL: fileURL, isFileImport: true, audioDurationSec: 0)
            }
        }
    }
    
    private func processLongFileInChunks(fileURL: URL, isFileImport: Bool, audioDurationSec: Double) {
        let processStartTime = Date()
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_file_full.wav")
        let sourceURL = isFileImport ? tempWavURL : fileURL
        
        if isFileImport {
            var conversionSuccess = false
            conversionSuccess = convertMediaTo16kHzWav(inputURL: fileURL, outputURL: tempWavURL)
            if !conversionSuccess { conversionSuccess = convertWithFFmpeg(inputURL: fileURL, outputURL: tempWavURL) }
            if !conversionSuccess { conversionSuccess = convertAudioTo16kHzWav(inputURL: fileURL, outputURL: tempWavURL) }
            
            if !conversionSuccess {
                DispatchQueue.main.async {
                    self.isProcessingFile = false
                    OverlayPanelManager.shared.showWarning(message: String(localized: "Не удалось извлечь аудио"))
                }
                return
            }
        }
        
        guard let inputFile = try? AVAudioFile(forReading: sourceURL) else {
            DispatchQueue.main.async {
                self.isProcessingFile = false
                OverlayPanelManager.shared.showWarning(message: String(localized: "Ошибка чтения файла"))
            }
            return
        }
        
        let totalFrames = inputFile.length
        let sampleRate = inputFile.processingFormat.sampleRate
        let realAudioSecs = isFileImport ? (Double(totalFrames) / sampleRate) : audioDurationSec
        
        let durationFormatted: String
        if realAudioSecs >= 60.0 { durationFormatted = String(format: String(localized: "%.0f мин"), realAudioSecs / 60.0) }
        else { durationFormatted = String(format: String(localized: "%.1f сек"), realAudioSecs) }
        
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
                    if !chunkText.isEmpty && chunkText != String(localized: "Речь не распознана") { accumulatedText.append(chunkText) }
                    try? FileManager.default.removeItem(at: chunkWavURL)
                }
                
                if isFileImport {
                    DispatchQueue.main.async { self.fileProcessingProgress = Double(chunkIndex + 1) / Double(totalChunks) }
                }
            }
        }
        
        let rawText = accumulatedText.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let prettyFormattedText = TextFormatter.formatIntoParagraphs(rawText)
        let processingTimeSecs = Date().timeIntervalSince(processStartTime)
        let calculatedSpeedup = max(1.0, realAudioSecs / max(0.1, processingTimeSecs))
        
        if isFileImport {
            try? FileManager.default.removeItem(at: tempWavURL)
        }
        
        DispatchQueue.main.async {
            self.isProcessingFile = false
            if prettyFormattedText.isEmpty {
                AppLogger.shared.warn("Recognition", "Речь не распознана", details: String(format: "аудио %.1f с", realAudioSecs))
                Telemetry.shared.event("dictation_failed", ["audio_duration_sec": realAudioSecs])
                OverlayPanelManager.shared.showWarning(message: String(localized: "Речь не распознана"))
            } else {
                self.transcribedText = prettyFormattedText
                self.isSuccessDone = true
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy, HH:mm"
                let dateStr = formatter.string(from: Date())
                
                let newItem = TranscriptionItem(id: UUID(), date: dateStr, text: prettyFormattedText, duration: durationFormatted, speedup: calculatedSpeedup, isUnread: true)
                
                self.saveAudioForNote(id: newItem.id, sourceURL: sourceURL)
                self.history.insert(newItem, at: 0)
                
                NotificationCenter.default.post(name: NSNotification.Name("AutoSelectNote"), object: newItem.id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyFormattedText, forType: .string)
                
                if !isFileImport && self.autoPasteEnabled {
                    self.pasteToActiveApp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { SoundEffect.playSuccess() }
                } else {
                    SoundEffect.playSuccess()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { OverlayPanelManager.shared.hideOverlay() }
            }
            
            self.sendTelemetry(eventType: isFileImport ? "file_import" : "dictation", audioDurationSec: realAudioSecs, characterCount: rawText.count, speedup: calculatedSpeedup)
        }
    }
    
    func markAsRead(id: UUID) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            if history[idx].isUnread == true { history[idx].isUnread = false }
        }
    }

    private func convertWithFFmpeg(inputURL: URL, outputURL: URL) -> Bool {
        let bundledFFmpeg = Bundle.main.path(forResource: "ffmpeg", ofType: nil)
        var ffmpegPaths: [String] = []
        if let bundledFFmpeg { ffmpegPaths.append(bundledFFmpeg) }
        ffmpegPaths.append(contentsOf: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"])
        guard let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            AppLogger.shared.warn("Import", "ffmpeg не найден (встроенный или системный)", details: inputURL.lastPathComponent)
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = ["-i", inputURL.path, "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_f32le", outputURL.path, "-y"]
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path)
            if ok {
                AppLogger.shared.info("Import", "Конвертация аудио выполнена", details: "ffmpeg: \(ffmpegPath)")
            } else {
                AppLogger.shared.warn("Import", "ffmpeg не смог конвертировать файл", details: "\(inputURL.lastPathComponent), exit \(process.terminationStatus)")
            }
            return ok
        } catch { return false }
    }

    private func convertMediaTo16kHzWav(inputURL: URL, outputURL: URL) -> Bool {
        let asset = AVURLAsset(url: inputURL)
        let semaphore = DispatchSemaphore(value: 0)
        var audioTrack: AVAssetTrack?
        Task.detached {
            do {
                audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            } catch {
                audioTrack = nil
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let track = audioTrack else { return false }
        do {
            let reader = try AVAssetReader(asset: asset)
            let outputSettings: [String: Any] = [ AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: true ]
            let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            reader.add(readerOutput)
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
            reader.startReading()
            while reader.status == .reading {
                autoreleasepool {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer(), let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                        var length: Int = 0
                        var dataPointer: UnsafeMutablePointer<Int8>?
                        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                        if let ptr = dataPointer, length > 0 {
                            let frameCount = AVAudioFrameCount(length / 4)
                            if let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) {
                                pcmBuffer.frameLength = frameCount
                                memcpy(pcmBuffer.floatChannelData?[0], ptr, length)
                                try? outputFile.write(from: pcmBuffer)
                            }
                        }
                    }
                }
            }
            return reader.status == .completed
        } catch { return false }
    }

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
                    if framesToRead == 0 { currentFrame = totalFrames; return }
                    do { try inputFile.read(into: inputBuffer, frameCount: framesToRead) } catch { hasError = true; return }
                    let framesRead = inputBuffer.frameLength
                    if framesRead == 0 { currentFrame = totalFrames; return }
                    currentFrame += Int64(framesRead)
                    var error: NSError?
                    var allConsumed = false
                    let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                        if allConsumed { outStatus.pointee = .noDataNow; return nil }
                        allConsumed = true; outStatus.pointee = .haveData; return inputBuffer
                    }
                    if status != .error && error == nil { try? outputFile.write(from: outputBuffer) } else { hasError = true }
                }
            }
            return !hasError
        } catch { return false }
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
        if playingItemId == item.id { audioPlayer?.stop(); playingItemId = nil; return }
        do { audioPlayer = try AVAudioPlayer(contentsOf: fileURL); audioPlayer?.play(); playingItemId = item.id } catch {}
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
        let store = ModelStore.shared
        guard let model = store.model(named: store.activeModelID) else { return "" }
        if model.isBundled {
            guard let cliPath = Bundle.main.path(forResource: "transcribe-cli", ofType: nil),
                  let modelPath = Bundle.main.path(forResource: model.fileName, ofType: "gguf") else {
                AppLogger.shared.error("Recognition", "transcribe-cli или встроенная модель не найдены в бандле")
                return ""
            }
            let output = runCLIProcess(cliPath, arguments: ["-m", modelPath, wavURL.path])
            let lines = output.components(separatedBy: .newlines)
            if let textLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("text:") }) {
                let extracted = String(textLine.trimmingCharacters(in: .whitespaces).dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                if extracted != "(empty)" { return extracted }
            }
            return ""
        } else {
            guard let cliPath = Bundle.main.path(forResource: "whisper-cli", ofType: nil),
                  let modelPath = store.localModelPath(for: model.id) else {
                AppLogger.shared.error("Recognition", "whisper-cli или модель \(model.id) не найдены", details: model.id)
                return ""
            }
            let output = runCLIProcess(cliPath, arguments: ["-m", modelPath, "-f", wavURL.path, "-l", model.languageCode, "-nt"])
            let parts = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.lowercased().hasPrefix("whisper") }
            return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func runCLIProcess(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch { return "" }
    }
    
    private func pasteToActiveApp() {
        guard autoPasteEnabled else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        guard let target = pasteTarget else { return }
        let pid = target.processIdentifier
        target.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard self.canAcceptPaste(pid: pid) else {
                AppLogger.shared.info("Paste", "Вставка пропущена: под фокусом нет редактируемого поля", details: target.localizedName)
                Telemetry.shared.event("paste_skipped", ["paste_reason": "no_focus"])
                return
            }
            AppLogger.shared.info("Paste", "Cmd+V отправлен", details: target.localizedName)
            Telemetry.shared.event("paste_success", ["paste_method": "cgkey"])
            let source = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
            keyDown.flags = .maskCommand; keyUp.flags = .maskCommand
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        }
    }

    private func canAcceptPaste(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else { return true }
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXRoleAttribute as CFString, &roleRef) == .success,
              let roleString = roleRef as? String else { return true }
        switch roleString {
        case "AXTextField", "AXTextArea", "AXTextView", "AXComboBox", "AXSearchField",
             "AXDocument", "AXScrollArea", "AXWebArea":
            return true
        default:
            return false
        }
    }
    
    private func sendTelemetry(eventType: String, audioDurationSec: Double, characterCount: Int, speedup: Double) {
        Telemetry.shared.event(eventType, [
            "audio_duration_sec": audioDurationSec,
            "character_count": characterCount,
            "speedup_factor": speedup
        ])
    }
    
    // ЭКСПОРТ В ВАЛИДНЫЙ UTF-8 С BOM ДЛЯ MS EXCEL / NUMBERS
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
            case "csv":
                // \u{FEFF} — это BOM маркер для того, чтобы Excel открывал русский язык в идеальном UTF-8!
                content = "\u{FEFF}\"Дата\",\"Длительность\",\"Текст\"\n\"\(item.date)\",\"\(item.duration)\",\"\(item.text.replacingOccurrences(of: "\"", with: "\"\""))\""
            case "json":
                let dict: [String: Any] = ["id": item.id.uuidString, "date": item.date, "duration": item.duration, "text": item.text]
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) { content = String(data: data, encoding: .utf8) ?? "" }
            default: content = prettyText
            }
            try? content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }
    
    func checkUpdates(force: Bool = false) {
        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheckAt") as? Date
        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < 12 * 3600 {
            if let data = UserDefaults.standard.data(forKey: "cachedUpdateInfo"),
               let cached = try? JSONDecoder().decode(UpdateInfo?.self, from: data) {
                DispatchQueue.main.async { self.updateInfo = cached }
            }
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/Berliner187/Golosok/releases/latest") else { return }
        let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10.0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String, let releaseName = json["name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let firstAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                  let downloadUrlString = firstAsset["browser_download_url"] as? String,
                  let downloadUrl = URL(string: downloadUrlString) else {
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckAt")
                return
            }
            let cleanCurrent = currentVer.replacingOccurrences(of: "v", with: "")
            let cleanLatest = tagName.replacingOccurrences(of: "v", with: "")
            let result: UpdateInfo?
            if cleanLatest.compare(cleanCurrent, options: .numeric) == .orderedDescending {
                let codename = releaseName.components(separatedBy: " ").last ?? "UPDATE"
                result = UpdateInfo(version: tagName, codename: codename.uppercased(), url: downloadUrl)
            } else {
                result = nil
            }
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckAt")
            if let encoded = try? JSONEncoder().encode(result) {
                UserDefaults.standard.set(encoded, forKey: "cachedUpdateInfo")
            }
            DispatchQueue.main.async { self.updateInfo = result }
        }.resume()
    }
    
    func cancelUpdateDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        DispatchQueue.main.async { self.isDownloadingUpdate = false; self.updateProgressText = "" }
    }
    
    func downloadAndInstallUpdate() {
        guard let updateUrl = updateInfo?.url else { return }
        DispatchQueue.main.async { self.isDownloadingUpdate = true; self.updateProgressText = "Подключение..." }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Golosok_Update.dmg")
        if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        downloadTask = session.downloadTask(with: updateUrl)
        downloadTask?.resume()
    }
    
    func deleteItem(at index: Int) {
        let item = history[index]
        history.remove(at: index)
        deleteAudioFile(for: item.id)
    }
    func clearAllHistory() {
        history.forEach { deleteAudioFile(for: $0.id) }
        history.removeAll()
    }
    private func saveHistory() { if let e = try? JSONEncoder().encode(history) { UserDefaults.standard.set(e, forKey: "transcription_history") } }
    private func loadHistory() {
        if let d = UserDefaults.standard.data(forKey: "transcription_history"), let dec = try? JSONDecoder().decode([TranscriptionItem].self, from: d) {
            isLoadingHistory = true
            defer { isLoadingHistory = false }
            self.history = dec.map { item in
                if !item.text.contains("\n\n") && item.text.count > 120 {
                    let pretty = TextFormatter.formatIntoParagraphs(item.text)
                    return TranscriptionItem(id: item.id, date: item.date, text: pretty, duration: item.duration, speedup: item.speedup, isUnread: item.isUnread)
                }
                return item
            }
        }
    }

    private func deleteAudioFile(for id: UUID) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let fileURL = appSupport.appendingPathComponent("Golosok/Audio/\(id.uuidString).wav")
        if FileManager.default.fileExists(atPath: fileURL.path) { try? FileManager.default.removeItem(at: fileURL) }
    }
}

extension AudioCapture: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let mbWritten = Double(totalBytesWritten) / (1024.0 * 1024.0)
        let mbTotal = Double(totalBytesExpectedToWrite) / (1024.0 * 1024.0)
        let percent = Int(progress * 100.0)
        let text = String(format: "%.0f / %.0f МБ (%d%%)", mbWritten, mbTotal, percent)
        DispatchQueue.main.async { self.fileProcessingProgress = progress; self.updateProgressText = text }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("Golosok_Update.dmg")
        if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.isDownloadingUpdate = false
                self.updateProgressText = "Открытие..."
                NSWorkspace.shared.open(dest)
            }
        } catch { DispatchQueue.main.async { self.isDownloadingUpdate = false; self.updateProgressText = "Ошибка" } }
    }
}
