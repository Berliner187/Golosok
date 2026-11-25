import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import Observation

// MARK: - Кастомная акустическая айдентика
struct SoundEffect {
    static func playStart() { LuxurySoundSynth.shared.playStart() }
    static func playSuccess() { LuxurySoundSynth.shared.playSuccess() }
    static func playCancel() { LuxurySoundSynth.shared.playCancel() }
    static func playCopy() { LuxurySoundSynth.shared.playCopy() }
    static func playDelete() { LuxurySoundSynth.shared.playDelete() }
    static func playWarning() { LuxurySoundSynth.shared.playWarning() }
    static func playStop() { LuxurySoundSynth.shared.playStop() }
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

struct TimedWord: Codable, Hashable {
    let text: String
    let start: Double
    let end: Double
}

struct TimingFilePayload: Codable {
    let words: [TimedWord]
    let duration: Double
}

struct SubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}

/// Состояние плеера отдельно от AudioCapture: тик playhead (10 Гц) не должен
/// инвалидировать всех, кто подписан на AudioCapture.
@Observable
final class PlaybackState {
    var playingItemId: UUID? = nil
    var playheadTime: Double = 0
    var isPlayerPlaying: Bool = false
}

class AudioCapture: NSObject, ObservableObject {
    static let shared = AudioCapture()

    private var captureSession: AVCaptureSession?
    private var audioOutputFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private var currentDeviceUID: String?
    private let captureQueue = DispatchQueue(label: "com.golosok.audiocapture")
    private let captureQueueKey = DispatchSpecificKey<Void>()
    private let meterLock = NSLock()
    private var meterSquareSum: Double = 0
    private var meterSampleCount: Int = 0
    private var timer: Timer?
    private var startTime: Date?
    private var escMonitor: Any?
    private var escLocalMonitor: Any?
    private var pasteTarget: NSRunningApplication?
    /// Очередь импорта: файлы, которые не удалось распознать (имя, причина). Только main.
    private var queueFailures: [(name: String, reason: String)] = []
    
    @Published var isRecording = false
    @Published var isProcessingFile = false

    // АПДЕЙТЫ
    @Published var updateInfo: UpdateInfo? = nil
    @Published var isDownloadingUpdate = false
    @Published var updateProgressText: String = ""
    private var downloadTask: URLSessionDownloadTask?
    
    let playback = PlaybackState()
    var playingItemId: UUID? {
        get { playback.playingItemId }
        set { playback.playingItemId = newValue }
    }
    var playheadTime: Double {
        get { playback.playheadTime }
        set { playback.playheadTime = newValue }
    }
    var isPlayerPlaying: Bool {
        get { playback.isPlayerPlaying }
        set { playback.isPlayerPlaying = newValue }
    }
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var preloadedPlayerId: UUID?

    private var meterSamples: [Float] = Array(repeating: 0.15, count: 18)

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
        captureQueue.setSpecific(key: captureQueueKey, value: ())
        
        if UserDefaults.standard.object(forKey: "analyticsEnabled") == nil {
            self.analyticsEnabled = true
        }

        let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if let lastActive = UserDefaults.standard.string(forKey: "lastActiveVersion"), lastActive != currentVer {
            UserDefaults.standard.removeObject(forKey: "cachedUpdateInfo")
            UserDefaults.standard.removeObject(forKey: "updateCheckETag")
            UserDefaults.standard.removeObject(forKey: "lastUpdateCheckAt")
            DispatchQueue.main.async { self.updateInfo = nil }
        }
        UserDefaults.standard.set(currentVer, forKey: "lastActiveVersion")

        loadHistory()
        NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.isRecording,
                  let device = note.object as? AVCaptureDevice,
                  device.uniqueID == self.currentDeviceUID else { return }
            AppLogger.shared.warn("Recording", "Микрофон отключён во время записи — запись отменена", details: device.localizedName)
            Telemetry.shared.event("mic_disconnected_mid_recording", ["device_uid": device.uniqueID])
            self.cancelRecording()
        }
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
        teardownCaptureSession()
        SoundEffect.playCancel()
        
        DispatchQueue.main.async {
            self.isRecording = false
            OverlayPanelPresenter.hide()
        }
    }

    func startRecording() {
        guard !SplashGate.shared.isActive else { return }
        guard !isProcessingFile, !isRecording, captureSession == nil else { return }
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted { DispatchQueue.main.async { self.startRecording() } }
            }
            return
        case .denied, .restricted:
            return
        case .authorized: break
        @unknown default: break
        }

        guard let device = MicrophoneStore.shared.resolveDevice() else {
            AppLogger.shared.warn("Recording", "Нет доступного микрофона для записи")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: tempAudioURL.path) { try FileManager.default.removeItem(at: tempAudioURL) }
            try startCaptureSession(device: device)

            startTime = Date()
            SoundEffect.playStart()

            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.cancelRecording() }
            }
            // Глобальный монитор не видит события, пока фокус у самого Голосок —
            // для этого случая добавляем локальный монитор.
            escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { self?.cancelRecording() }
                return event
            }

            DispatchQueue.main.async {
                self.isRecording = true
                AppLogger.shared.info("Recording", "Запись началась", details: "микрофон: \(device.localizedName), режим: \(HotKeySettings.shared.mode == .pushToTalk ? "рация" : "переключатель")")
                OverlayPanelPresenter.showRecording()
            }
            let meteringTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateMetering() }
            RunLoop.main.add(meteringTimer, forMode: .common)
            timer = meteringTimer
        } catch {
            teardownCaptureSession()
            AppLogger.shared.error("Recording", "Не удалось запустить захват аудио", details: String(describing: error))
        }
    }

    private func startCaptureSession(device: AVCaptureDevice) throws {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "Golosok", code: 1, userInfo: [NSLocalizedDescriptionKey: "canAddInput failed"])
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "Golosok", code: 2, userInfo: [NSLocalizedDescriptionKey: "canAddOutput failed"])
        }
        session.addOutput(output)

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: tempAudioURL, settings: targetFormat.settings)

        captureSession = session
        audioOutputFile = file
        currentDeviceUID = device.uniqueID
        session.startRunning()
    }

    private func teardownCaptureSession() {
        captureSession?.stopRunning()
        // Drain: дожидаемся блоков captureOutput, уже стоящих в очереди,
        // чтобы хвост записи дописался в файл до его освобождения.
        if DispatchQueue.getSpecific(key: captureQueueKey) == nil {
            captureQueue.sync {}
        }
        captureSession = nil
        audioConverter = nil
        audioOutputFile = nil
        currentDeviceUID = nil
    }

    func stopRecording() {
        removeEscMonitor()
        pasteTarget = NSWorkspace.shared.frontmostApplication
        timer?.invalidate()
        timer = nil
        teardownCaptureSession()
        SoundEffect.playStop()

        let durationSec = Date().timeIntervalSince(startTime ?? Date())

        AppLogger.shared.info("Recording", "Запись остановлена", details: String(format: "длительность %.1f с, цель вставки: %@", durationSec, NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"))

        DispatchQueue.main.async {
            self.isRecording = false
            self.isProcessingFile = true
            OverlayPanelPresenter.showTranscribing()
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.processLongFileInChunks(fileURL: self.tempAudioURL, isFileImport: false, audioDurationSec: durationSec)
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = escLocalMonitor {
            NSEvent.removeMonitor(monitor)
            escLocalMonitor = nil
        }
    }

    private func updateMetering() {
        guard isRecording else { return }

        meterLock.lock()
        let squareSum = meterSquareSum
        let sampleCount = meterSampleCount
        meterSquareSum = 0
        meterSampleCount = 0
        meterLock.unlock()

        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        let rms = sampleCount > 0 ? sqrt(squareSum / Double(sampleCount)) : 0
        let power = 20.0 * log10(max(rms, 0.00001))
        let level = max(0.15, min(1.0, (power + 40.0) / 35.0))
        let time = CACurrentMediaTime()

        var newSamples: [Float] = []
        newSamples.reserveCapacity(meterSamples.count)
        for index in meterSamples.indices {
            let shape = 0.76 + (0.24 * sin((time * 6.8) + Double(index) * 0.52))
            let target = max(0.15, min(1.0, Double(level) * shape))
            newSamples.append((meterSamples[index] * 0.35) + Float(target * 0.65))
        }
        meterSamples = newSamples

        OverlayPanelPresenter.updateRecording(elapsedSeconds: elapsed, samples: newSamples)
    }

    func importAndTranscribeFile() {
        if isRecording || isProcessingFile {
            SoundEffect.playCancel()
            return
        }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let webmType = UTType(filenameExtension: "webm") ?? .movie
        let mkvType = UTType(filenameExtension: "mkv") ?? .movie
        let oggType = UTType(filenameExtension: "ogg") ?? .audio
        panel.allowedContentTypes = [.audio, .movie, .mp3, .mpeg4Audio, .wav, webmType, mkvType, oggType]
        
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            importFiles(panel.urls)
        }
    }
    
    func importFiles(_ urls: [URL]) {
        guard !isRecording, !isProcessingFile else {
            SoundEffect.playCancel()
            return
        }
        let media = urls.filter { Self.isMediaURL($0) }
        guard !media.isEmpty else { return }
        DispatchQueue.main.async {
            self.isProcessingFile = true
            self.queueFailures = []
            OverlayPanelPresenter.showProcessing(
                progress: 0,
                file: OverlayFileContext(name: media[0].lastPathComponent, index: 1, total: media.count))
        }
        DispatchQueue.global(qos: .utility).async {
            self.processQueue(media)
        }
    }

    private func processQueue(_ urls: [URL]) {
        processNextInQueue(urls, index: 0)
    }

    private func processNextInQueue(_ urls: [URL], index: Int) {
        guard index < urls.count else {
            DispatchQueue.main.async {
                self.isProcessingFile = false
                self.presentQueueResult(total: urls.count)
            }
            return
        }
        let url = urls[index]
        let context = OverlayFileContext(name: url.lastPathComponent, index: index + 1, total: urls.count)
        DispatchQueue.main.async {
            self.isProcessingFile = true
            OverlayPanelPresenter.showProcessing(progress: Double(index) / Double(urls.count), file: context)
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.processLongFileInChunks(fileURL: url, isFileImport: true, audioDurationSec: 0, fileContext: context) { failure in
                DispatchQueue.main.async {
                    if let failure { self.queueFailures.append((name: url.lastPathComponent, reason: failure)) }
                    self.processNextInQueue(urls, index: index + 1)
                }
            }
        }
    }

    /// Единый итог по очереди: раньше таймер скрытия от последнего файла (0,8 с) перезаписывал
    /// предупреждение, и ошибка мигала секунду. Теперь итог показывается один раз и держится дольше.
    private func presentQueueResult(total: Int) {
        guard let first = queueFailures.first else {
            OverlayPanelPresenter.showSuccess(file: OverlayFileContext(name: "", index: total, total: total))
            SoundEffect.playSuccess()
            OverlayPanelPresenter.scheduleHide(after: OverlayTiming.fileSuccessHold)
            return
        }
        let context = OverlayFileContext(name: first.name, index: total, total: total)
        if total == 1 {
            OverlayPanelPresenter.showWarning(message: first.reason, detail: first.name, file: context)
        } else {
            let more = queueFailures.count > 1 ? " +\(queueFailures.count - 1)" : ""
            OverlayPanelPresenter.showWarning(
                message: String(localized: "Не распознано: \(queueFailures.count) из \(total)"),
                detail: first.name + more,
                file: context)
        }
    }
    
    private static func isMediaURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let mediaExts: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "aac", "flac", "ogg", "opus", "mp4", "mov", "m4v", "webm", "mkv", "avi"]
        if mediaExts.contains(ext) { return true }
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]), let ut = values.contentType {
            return ut.conforms(to: .audio) || ut.conforms(to: .movie)
        }
        return false
    }
    
    private func processLongFileInChunks(fileURL: URL, isFileImport: Bool, audioDurationSec: Double,
                                         fileContext: OverlayFileContext? = nil,
                                         completion: ((String?) -> Void)? = nil) async {
        let processStartTime = Date()
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_file_full.wav")
        let sourceURL = isFileImport ? tempWavURL : fileURL
        
        /// `failure` — причина неудачи (только импорт файла); nil — успех.
        func finish(failure: String? = nil) {
            if let completion {
                completion(failure)
            } else {
                DispatchQueue.main.async { self.isProcessingFile = false }
            }
        }
        
        /// Импорт: причину покажет очередь одним итогом после последнего файла.
        /// Диктовка: предупреждение сразу.
        func fail(_ reason: String) {
            if isFileImport {
                finish(failure: reason)
            } else {
                OverlayPanelPresenter.showWarning(message: reason)
                finish()
            }
        }
        
        if isFileImport {
            var conversionSuccess = false
            conversionSuccess = await convertMediaTo16kHzWav(inputURL: fileURL, outputURL: tempWavURL)
            if !conversionSuccess { conversionSuccess = convertWithFFmpeg(inputURL: fileURL, outputURL: tempWavURL) }
            if !conversionSuccess { conversionSuccess = convertAudioTo16kHzWav(inputURL: fileURL, outputURL: tempWavURL) }
            
            if !conversionSuccess {
                fail(String(localized: "Не удалось извлечь аудио"))
                return
            }
        }

        guard let inputFile = try? AVAudioFile(forReading: sourceURL) else {
            fail(String(localized: "Ошибка чтения файла"))
            return
        }
        
        let totalFrames = inputFile.length
        let sampleRate = inputFile.processingFormat.sampleRate
        let realAudioSecs = isFileImport ? (Double(totalFrames) / sampleRate) : audioDurationSec
        
        let durationFormatted: String
        if realAudioSecs >= 60.0 { durationFormatted = String(format: String(localized: "%.0f мин"), realAudioSecs / 60.0) }
        else { durationFormatted = String(format: String(localized: "%.0f сек"), realAudioSecs.rounded()) }
        
        let chunkSizeInSeconds: Double = 25.0
        let framesPerChunk = AVAudioFrameCount(chunkSizeInSeconds * sampleRate)
        let totalChunks = max(1, Int(ceil(Double(totalFrames) / Double(framesPerChunk))))
        
        var accumulatedText: [String] = []
        var accumulatedWords: [TimedWord] = []
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
                    let chunkResult = runCLIOnWav(wavURL: chunkWavURL)
                    let chunkText = chunkResult.text
                    if !chunkText.isEmpty && chunkText != String(localized: "Речь не распознана") { accumulatedText.append(chunkText) }
                    let chunkStart = Double(chunkIndex) * chunkSizeInSeconds
                    for word in chunkResult.words {
                        accumulatedWords.append(TimedWord(text: word.text, start: word.start + chunkStart, end: word.end + chunkStart))
                    }
                    try? FileManager.default.removeItem(at: chunkWavURL)
                }
                
                if isFileImport {
                    // Общий прогресс по всей очереди: кольцо идёт плавно через все файлы.
                    let fileProgress = Double(chunkIndex + 1) / Double(totalChunks)
                    let context = fileContext ?? OverlayFileContext(name: fileURL.lastPathComponent, index: 1, total: 1)
                    let overall = (Double(context.index - 1) + fileProgress) / Double(context.total)
                    OverlayPanelPresenter.showProcessing(progress: overall, file: context)
                }
            }
        }
        
        let rawText = accumulatedText.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let prettyFormattedText = TextFormatter.formatIntoParagraphs(rawText)
        let processingTimeSecs = Date().timeIntervalSince(processStartTime)
        let calculatedSpeedup = max(1.0, realAudioSecs / max(0.1, processingTimeSecs))
        let noSpeechReason: String? = prettyFormattedText.isEmpty ? String(localized: "Речь не распознана") : nil
        
        DispatchQueue.main.async {
            if let noSpeechReason {
                AppLogger.shared.warn("Recognition", "Речь не распознана", details: String(format: "аудио %.1f с", realAudioSecs))
                Telemetry.shared.event("dictation_failed", ["audio_duration_sec": realAudioSecs])
                if !isFileImport { OverlayPanelPresenter.showWarning(message: noSpeechReason) }
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy, HH:mm"
                let dateStr = formatter.string(from: Date())

                let newItem = TranscriptionItem(id: UUID(), date: dateStr, text: prettyFormattedText, duration: durationFormatted, speedup: calculatedSpeedup, isUnread: true)

                self.saveAudioForNote(id: newItem.id, sourceURL: sourceURL)
                if !accumulatedWords.isEmpty {
                    self.saveTimingsForNote(id: newItem.id, words: accumulatedWords, duration: realAudioSecs)
                }
                if isFileImport { try? FileManager.default.removeItem(at: sourceURL) }
                self.history.insert(newItem, at: 0)

                NotificationCenter.default.post(name: NSNotification.Name("AutoSelectNote"), object: newItem.id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prettyFormattedText, forType: .string)

                // Импорт: итог и звук показывает очередь после последнего файла (presentQueueResult).
                if !isFileImport {
                    OverlayPanelPresenter.showSuccess()
                    if self.autoPasteEnabled {
                        self.pasteToActiveApp()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { SoundEffect.playSuccess() }
                    } else {
                        SoundEffect.playSuccess()
                    }
                    OverlayPanelPresenter.scheduleHide(after: OverlayTiming.dictationSuccessHold)
                }
            }

            self.sendTelemetry(eventType: isFileImport ? "file_import" : "dictation", audioDurationSec: realAudioSecs, characterCount: rawText.count, speedup: calculatedSpeedup)
            finish(failure: isFileImport ? noSpeechReason : nil)
        }
    }
    
    func markAsRead(id: UUID) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            if history[idx].isUnread == true { history[idx].isUnread = false }
        }
    }

    func appendTextToNote(id: UUID, text: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let item = history[idx]
        let current = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = current.isEmpty ? text : current + "\n\n----------------\n\n" + text
        history[idx] = TranscriptionItem(id: item.id, date: item.date, text: newText, duration: item.duration, speedup: item.speedup, isUnread: item.isUnread)
    }

    func replaceNoteText(id: UUID, text: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let item = history[idx]
        history[idx] = TranscriptionItem(id: item.id, date: item.date, text: text, duration: item.duration, speedup: item.speedup, isUnread: item.isUnread)
    }

    func replaceRangeInNote(id: UUID, range: NSRange, newText: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let item = history[idx]
        let nsText = item.text as NSString
        guard range.location != NSNotFound, range.location + range.length <= nsText.length else { return }
        let result = nsText.replacingCharacters(in: range, with: newText)
        history[idx] = TranscriptionItem(id: item.id, date: item.date, text: result, duration: item.duration, speedup: item.speedup, isUnread: item.isUnread)
    }

    @discardableResult
    func addNote(text: String) -> UUID {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        let dateStr = formatter.string(from: Date())
        let item = TranscriptionItem(id: UUID(), date: dateStr, text: text, duration: "—", speedup: nil, isUnread: false)
        history.insert(item, at: 0)
        return item.id
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

    private func convertMediaTo16kHzWav(inputURL: URL, outputURL: URL) async -> Bool {
        let asset = AVURLAsset(url: inputURL)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return false }
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
    
    private func audioFileURL(for id: UUID) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent("Golosok/Audio/\(id.uuidString).wav")
    }
    
    private func timingsFileURL(for id: UUID) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent("Golosok/Audio/\(id.uuidString).segments.json")
    }
    
    private func saveTimingsForNote(id: UUID, words: [TimedWord], duration: Double) {
        guard let url = timingsFileURL(for: id),
              let data = try? JSONEncoder().encode(TimingFilePayload(words: words, duration: duration)) else { return }
        try? data.write(to: url, options: .atomic)
        AppLogger.shared.info("Recognition", "Тайминги слов сохранены", details: "\(words.count) слов, длительность \(String(format: "%.1f с", duration))")
    }
    
    func timings(for id: UUID) -> (words: [TimedWord], duration: Double)? {
        guard let result = readTimings(for: id) else { return nil }
        preloadAudio(for: id)
        return result
    }

    private func readTimings(for id: UUID) -> (words: [TimedWord], duration: Double)? {
        guard let url = timingsFileURL(for: id),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(TimingFilePayload.self, from: data),
              !payload.words.isEmpty else { return nil }
        return (Self.normalizedWords(payload.words, duration: payload.duration), payload.duration)
    }

    static func normalizedWords(_ words: [TimedWord], duration: Double) -> [TimedWord] {
        guard let last = words.last, last.end > duration * 100 else { return words }
        return words.map { TimedWord(text: $0.text, start: $0.start / 1000, end: $0.end / 1000) }
    }

    private func preloadAudio(for id: UUID) {
        guard preloadedPlayerId != id else { return }
        preloadedPlayerId = id
        guard let fileURL = audioFileURL(for: id) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let player = try? AVAudioPlayer(contentsOf: fileURL) else { return }
            DispatchQueue.main.async {
                guard self?.preloadedPlayerId == id, self?.playingItemId == nil else { return }
                self?.audioPlayer = player
            }
        }
    }

    func toggleSyncedPlayback(for id: UUID) {
        guard audioFileURL(for: id) != nil else { return }
        if playingItemId == id {
            if audioPlayer?.isPlaying == true {
                audioPlayer?.pause(); stopPlaybackTimer(); isPlayerPlaying = false
            } else if let player = audioPlayer {
                player.play(); startPlaybackTimer(for: id); isPlayerPlaying = true
            }
            return
        }
        audioPlayer?.stop()
        if preloadedPlayerId != id, let url = audioFileURL(for: id) {
            do { audioPlayer = try AVAudioPlayer(contentsOf: url) } catch { return }
        }
        preloadedPlayerId = nil
        audioPlayer?.play()
        playingItemId = id
        playheadTime = 0
        isPlayerPlaying = true
        startPlaybackTimer(for: id)
    }
    
    func seekSynced(to time: Double, for id: UUID) {
        guard let player = audioPlayer else { return }
        player.currentTime = min(max(time, 0), player.duration)
        if playingItemId == id {
            if !player.isPlaying {
                player.play()
                startPlaybackTimer(for: id)
                isPlayerPlaying = true
            }
            playheadTime = time
        }
    }
    
    func stopSyncedPlayback() {
        audioPlayer?.stop()
        playingItemId = nil
        preloadedPlayerId = nil
        playheadTime = 0
        isPlayerPlaying = false
        stopPlaybackTimer()
    }
    
    private func startPlaybackTimer(for id: UUID) {
        stopPlaybackTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.audioPlayer else {
                self?.stopPlaybackTimer()
                return
            }
            guard self.playingItemId == id else { self.stopPlaybackTimer(); return }
            if player.isPlaying {
                self.playheadTime = player.currentTime
            } else {
                if player.duration > 0 && player.currentTime >= player.duration - 0.05 {
                    self.stopSyncedPlayback()
                } else {
                    self.stopPlaybackTimer()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }
    
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    func hasAudioFile(for item: TranscriptionItem) -> Bool {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let fileURL = appSupport.appendingPathComponent("Golosok/Audio/\(item.id.uuidString).wav")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    func toggleAudioPlayback(for item: TranscriptionItem) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let fileURL = appSupport.appendingPathComponent("Golosok/Audio/\(item.id.uuidString).wav")
        if playingItemId == item.id { audioPlayer?.stop(); playingItemId = nil; isPlayerPlaying = false; return }
        do { audioPlayer = try AVAudioPlayer(contentsOf: fileURL); audioPlayer?.play(); playingItemId = item.id; isPlayerPlaying = true } catch {}
    }
    
    private func writeBufferToWav(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat, outputURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) { try FileManager.default.removeItem(at: outputURL) }
            let file = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
            try file.write(from: buffer)
            return true
        } catch { return false }
    }
    
    private func runCLIOnWav(wavURL: URL) -> (text: String, words: [TimedWord]) {
        let store = ModelStore.shared
        guard let model = store.model(named: store.activeModelID) else { return ("", []) }
        if model.isBundled {
            guard let cliPath = Bundle.main.path(forResource: "transcribe-cli", ofType: nil),
                  let modelPath = Bundle.main.path(forResource: model.fileName, ofType: "gguf") else {
                AppLogger.shared.error("Recognition", "transcribe-cli или встроенная модель не найдены в бандле")
                return ("", [])
            }
            let output = runCLIProcess(cliPath, arguments: ["-m", modelPath, "--timestamps", "word", wavURL.path])
            let words = Self.finalizeWords(parseGigaAMTokens(output))
            let lines = output.components(separatedBy: .newlines)
            if let textLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("text:") }) {
                let extracted = String(textLine.trimmingCharacters(in: .whitespaces).dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                if extracted != "(empty)" { return (extracted, words) }
            }
            return ("", words)
        } else {
            guard let cliPath = Bundle.main.path(forResource: "whisper-cli", ofType: nil),
                  let modelPath = store.localModelPath(for: model.id) else {
                AppLogger.shared.error("Recognition", "whisper-cli или модель \(model.id) не найдены", details: model.id)
                return ("", [])
            }
            let output = runCLIProcess(cliPath, arguments: ["-m", modelPath, "-f", wavURL.path, "-l", model.languageCode, "-nt", "-ojf"])
            let parts = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.lowercased().hasPrefix("whisper") }
            let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (text, Self.finalizeWords(readWhisperWords(wavURL: wavURL)))
        }
    }

    private func parseGigaAMTokens(_ output: String) -> [TimedWord] {
        var words: [TimedWord] = []
        var currentText = ""
        var wordStart = -1.0
        var wordEnd = -1.0
        let pattern = #"\[\s*([0-9.]+)\s*->\s*([0-9.]+)\]\s*p=[0-9.eE+-]+\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsOutput = output as NSString
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
        for m in matches where m.numberOfRanges == 4 {
            let s = Double(nsOutput.substring(with: m.range(at: 1))) ?? -1
            let e = Double(nsOutput.substring(with: m.range(at: 2))) ?? -1
            var body = nsOutput.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { continue }
            if body.hasPrefix("[_") && body.hasSuffix("_]") { continue }
            let startsNewWord: Bool
            if body.hasPrefix("▁") {
                body = String(body.dropFirst())
                startsNewWord = true
            } else {
                startsNewWord = false
            }
            if currentText.isEmpty || startsNewWord {
                if !currentText.isEmpty { words.append(TimedWord(text: currentText, start: max(wordStart, 0), end: max(wordEnd, 0))) }
                currentText = body
                wordStart = s
                wordEnd = e
            } else {
                currentText += body
                wordEnd = e
            }
        }
        if !currentText.isEmpty { words.append(TimedWord(text: currentText, start: max(wordStart, 0), end: max(wordEnd, 0))) }
        return words
    }

    private static func finalizeWords(_ words: [TimedWord]) -> [TimedWord] {
        guard !words.isEmpty else { return [] }
        var result = words
        for i in 0..<(result.count - 1) {
            let nextStart = result[i + 1].start
            var end = result[i].end
            if end <= result[i].start || end >= nextStart { end = nextStart }
            if end <= result[i].start { end = result[i].start + 0.3 }
            result[i] = TimedWord(text: result[i].text, start: result[i].start, end: end)
        }
        let last = result.count - 1
        if result[last].end <= result[last].start {
            result[last] = TimedWord(text: result[last].text, start: result[last].start, end: result[last].start + 0.3)
        }
        return result
    }

    private func readWhisperWords(wavURL: URL) -> [TimedWord] {
        let jsonURL = wavURL.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }
        guard let data = try? Data(contentsOf: jsonURL) else {
            AppLogger.shared.warn("Recognition", "whisper JSON не найден", details: jsonURL.lastPathComponent)
            return []
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let transcription = json["transcription"] as? [[String: Any]] else { return [] }

        let wavEndSecs = Self.audioDurationSeconds(of: wavURL)
        var words: [TimedWord] = []

        for entry in transcription {
            guard let tokens = entry["tokens"] as? [[String: Any]] else { continue }

            var segmentWords: [TimedWord] = []
            var currentText = ""
            var wordStart = -1.0
            var wordEnd = -1.0
            var reliable = true
            var lastEnd = -1.0

            func appendSegmentWord(_ text: String, _ start: Double, _ end: Double) {
                let w = TimedWord(text: text, start: max(start, 0), end: max(end, 0))
                segmentWords.append(w)
                if start < 0 || end < 0 || end <= start || start < lastEnd { reliable = false }
                lastEnd = max(lastEnd, end)
            }

            for token in tokens {
                guard let raw = token["text"] as? String,
                      let offsets = token["offsets"] as? [String: Any],
                      let fromMs = offsets["from"] as? Double,
                      let toMs = offsets["to"] as? Double else { continue }
                let from = fromMs / 1000.0
                let to = toMs / 1000.0
                let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if body.isEmpty || (body.hasPrefix("[_") && body.hasSuffix("_]")) { continue }
                if currentText.isEmpty || raw.hasPrefix(" ") {
                    if !currentText.isEmpty { appendSegmentWord(currentText, wordStart, wordEnd) }
                    currentText = body
                    wordStart = from
                    wordEnd = to
                } else {
                    currentText += body
                    wordEnd = to
                }
            }
            if !currentText.isEmpty { appendSegmentWord(currentText, wordStart, wordEnd) }

            if !reliable && segmentWords.count > 1 {
                let offsets = entry["offsets"] as? [String: Any]
                var fromSecs = ((offsets?["from"] as? Double) ?? 0) / 1000.0
                var toSecs = ((offsets?["to"] as? Double) ?? 0) / 1000.0
                if wavEndSecs > 0 {
                    fromSecs = min(max(fromSecs, 0), wavEndSecs)
                    toSecs = min(toSecs, wavEndSecs)
                }
                if toSecs <= fromSecs { toSecs = fromSecs + Double(segmentWords.count) * 0.3 }
                segmentWords = Self.interpolateTimings(segmentWords, from: fromSecs, to: toSecs)
            }
            words.append(contentsOf: segmentWords)
        }

        return Self.finalizeWords(words)
    }

    private static func audioDurationSeconds(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static func interpolateTimings(_ words: [TimedWord], from startSecs: Double, to endSecs: Double) -> [TimedWord] {
        guard words.count > 1, endSecs > startSecs else { return words }
        let weights: [Double] = words.map { max(1.0, Double(($0.text as NSString).length)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return words }
        var result: [TimedWord] = []
        var cursor = startSecs
        var acc = 0.0
        for (i, w) in words.enumerated() {
            acc += weights[i]
            let wordEndSecs = startSecs + min(1.0, acc / total) * (endSecs - startSecs)
            result.append(TimedWord(text: w.text, start: cursor, end: max(wordEndSecs, cursor + 0.001)))
            cursor = max(wordEndSecs, cursor + 0.001)
        }
        return result
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
        guard AXIsProcessTrusted() else {
            AppLogger.shared.warn("Paste", "Доступ AX недоступен — пропускаем вставку. Пользователь должен включить её в Настройках.")
            Telemetry.shared.event("paste_skipped", ["paste_reason": "no_ax_access"])
            return
        }
        guard let target = pasteTarget else { return }
        let pid = target.processIdentifier
        target.activate()
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
    
    // MARK: - Субтитры

    static func makeSubtitleCues(from words: [TimedWord]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var buffer: [String] = []
        var cueStart = 0.0
        var cueEnd = 0.0

        func flush() {
            guard !buffer.isEmpty else { return }
            let end = max(cueEnd, cueStart + 0.5)
            cues.append(SubtitleCue(start: cueStart, end: end, text: buffer.joined(separator: " ")))
            buffer.removeAll()
        }

        for word in words {
            if buffer.isEmpty { cueStart = word.start }
            buffer.append(word.text)
            cueEnd = max(word.end, word.start + 0.2)
            let last = word.text.last
            let isSentenceEnd = last == "." || last == "!" || last == "?" || last == "…"
            if isSentenceEnd || buffer.count >= 12 || (word.end - cueStart) >= 6.0 {
                flush()
            }
        }
        flush()
        return cues
    }

    static func makeSubtitleCuesFromText(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var t = 0.0
        for sentence in Self.splitIntoSentences(text) {
            let words = sentence.split(separator: " ").count
            let dur = max(1.2, Double(words) * 0.4)
            cues.append(SubtitleCue(start: t, end: t + dur, text: sentence))
            t += dur + 0.05
        }
        return cues
    }

    static func splitIntoSentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" || ch == "…" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { result.append(trimmed) }
        return result
    }

    static func srtContent(cues: [SubtitleCue]) -> String {
        var out = ""
        for (i, cue) in cues.enumerated() {
            out += "\(i + 1)\n"
            out += "\(srtTime(cue.start)) --> \(srtTime(cue.end))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    static func vttContent(cues: [SubtitleCue]) -> String {
        var out = "WEBVTT\n\n"
        for cue in cues {
            out += "\(vttTime(cue.start)) --> \(vttTime(cue.end))\n"
            out += "\(cue.text)\n\n"
        }
        return out
    }

    static func srtTime(_ t: Double) -> String {
        let ms = Int((t * 1000).rounded())
        let h = ms / 3_600_000
        let m = (ms % 3_600_000) / 60_000
        let s = (ms % 60_000) / 1000
        let millis = ms % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, millis)
    }

    static func vttTime(_ t: Double) -> String {
        let ms = Int((t * 1000).rounded())
        let h = ms / 3_600_000
        let m = (ms % 3_600_000) / 60_000
        let s = (ms % 60_000) / 1000
        let millis = ms % 1000
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, millis)
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
            case "srt", "vtt":
                let cues: [SubtitleCue]
                if let timings = readTimings(for: item.id), !timings.words.isEmpty {
                    cues = Self.makeSubtitleCues(from: timings.words)
                } else {
                    cues = Self.makeSubtitleCuesFromText(item.text)
                }
                content = format.lowercased() == "srt" ? Self.srtContent(cues: cues) : Self.vttContent(cues: cues)
            default: content = prettyText
            }
            try? content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }
    
func checkUpdates(force: Bool = false) {
        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheckAt") as? Date
        let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < 4 * 3600 {
            if let data = UserDefaults.standard.data(forKey: "cachedUpdateInfo") {
                if let cached = try? JSONDecoder().decode(UpdateInfo.self, from: data),
                   Self.compareVersions(cached.version, currentVer) == .orderedDescending {
                    DispatchQueue.main.async { self.updateInfo = cached }
                } else {
                    UserDefaults.standard.removeObject(forKey: "cachedUpdateInfo")
                    DispatchQueue.main.async { self.updateInfo = nil }
                }
            }
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/Berliner187/Golosok/releases/latest") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10.0)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let etag = UserDefaults.standard.string(forKey: "updateCheckETag") {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            if http?.statusCode == 304 {
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckAt")
                return
            }
            if let etag = http?.value(forHTTPHeaderField: "Etag") {
                UserDefaults.standard.set(etag, forKey: "updateCheckETag")
            }
            defer { UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckAt") }
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String, let releaseName = json["name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let firstAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                  let downloadUrlString = firstAsset["browser_download_url"] as? String,
                  let downloadUrl = URL(string: downloadUrlString) else { return }
            let result: UpdateInfo?
            if Self.compareVersions(tagName, currentVer) == .orderedDescending {
                let codename = releaseName.components(separatedBy: " ").last ?? "UPDATE"
                result = UpdateInfo(version: tagName, codename: codename.uppercased(), url: downloadUrl)
            } else {
                result = nil
                UserDefaults.standard.removeObject(forKey: "updateCheckETag")
            }
            if let result, let encoded = try? JSONEncoder().encode(result) {
                UserDefaults.standard.set(encoded, forKey: "cachedUpdateInfo")
            } else {
                UserDefaults.standard.removeObject(forKey: "cachedUpdateInfo")
            }
            DispatchQueue.main.async { self.updateInfo = result }
        }.resume()
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let cleanA = a.replacingOccurrences(of: "v", with: "")
        let cleanB = b.replacingOccurrences(of: "v", with: "")
        let ta = cleanA.split(separator: ".").compactMap { Int($0) }
        let tb = cleanB.split(separator: ".").compactMap { Int($0) }
        let n = max(ta.count, tb.count)
        for i in 0..<n {
            let av = i < ta.count ? ta[i] : 0
            let bv = i < tb.count ? tb[i] : 0
            if av != bv { return av < bv ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
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
    private func historyStoreURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("Golosok", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
    
    private let historySaveQueue = DispatchQueue(label: "com.golosok.history.save", qos: .utility)
    private var pendingHistorySave: DispatchWorkItem?

    private func saveHistory() {
        guard let url = historyStoreURL() else { return }
        let snapshot = history   // копия по значению, дёшево
        pendingHistorySave?.cancel()
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        pendingHistorySave = work
        historySaveQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Дописать на диск немедленно (вызывается при выходе из приложения).
    func flushHistorySave() {
        guard let url = historyStoreURL() else { return }
        pendingHistorySave?.cancel()
        pendingHistorySave = nil
        let snapshot = history
        historySaveQueue.sync {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
    
    private func loadHistory() {
        guard let url = historyStoreURL() else { return }
        var items: [TranscriptionItem] = []
        var needsSave = false
        if !FileManager.default.fileExists(atPath: url.path),
           let udData = UserDefaults.standard.data(forKey: "transcription_history"),
           let dec = try? JSONDecoder().decode([TranscriptionItem].self, from: udData) {
            items = dec
            UserDefaults.standard.removeObject(forKey: "transcription_history")
            needsSave = true
        } else if let data = try? Data(contentsOf: url),
                  let dec = try? JSONDecoder().decode([TranscriptionItem].self, from: data) {
            items = dec
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        self.history = items.map { item in
            if !item.text.contains("\n\n") && item.text.count > 120 {
                needsSave = true
                let pretty = TextFormatter.formatIntoParagraphs(item.text)
                return TranscriptionItem(id: item.id, date: item.date, text: pretty, duration: item.duration, speedup: item.speedup, isUnread: item.isUnread)
            }
            return item
        }
        if needsSave { saveHistory() }
    }

    private func deleteAudioFile(for id: UUID) {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let fileURL = appSupport.appendingPathComponent("Golosok/Audio/\(id.uuidString).wav")
        if FileManager.default.fileExists(atPath: fileURL.path) { try? FileManager.default.removeItem(at: fileURL) }
        let segURL = appSupport.appendingPathComponent("Golosok/Audio/\(id.uuidString).segments.json")
        if FileManager.default.fileExists(atPath: segURL.path) { try? FileManager.default.removeItem(at: segURL) }
    }
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let bufferFormat = AVAudioFormat(streamDescription: asbdPointer),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard let ptr = dataPointer, length > 0 else { return }

        let bytesPerFrame = Int(asbdPointer.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }
        let frameCount = AVAudioFrameCount(length / bytesPerFrame)
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: frameCount) else { return }
        inputBuffer.frameLength = frameCount
        guard let dst = inputBuffer.mutableAudioBufferList.pointee.mBuffers.mData else { return }
        memcpy(dst, ptr, length)

        guard let file = audioOutputFile else { return }
        if audioConverter == nil {
            audioConverter = AVAudioConverter(from: bufferFormat, to: file.processingFormat)
        }
        guard let converter = audioConverter else { return }

        let ratio = file.processingFormat.sampleRate / bufferFormat.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(frameCount) * ratio) + 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: max(outputCapacity, 1)) else { return }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, conversionError == nil, outputBuffer.frameLength > 0 else { return }

        if let channelData = outputBuffer.floatChannelData {
            let frames = Int(outputBuffer.frameLength)
            var squareSum: Float = 0
            let samples = channelData[0]
            for i in 0..<frames { squareSum += samples[i] * samples[i] }
            meterLock.lock()
            meterSquareSum += Double(squareSum)
            meterSampleCount += frames
            meterLock.unlock()
        }

        do {
            try file.write(from: outputBuffer)
        } catch {
            AppLogger.shared.error("Recording", "Ошибка записи аудиофайла", details: String(describing: error))
            audioConverter = nil
            audioOutputFile = nil
        }
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
        DispatchQueue.main.async { self.updateProgressText = text }
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
