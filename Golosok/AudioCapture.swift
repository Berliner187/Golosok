import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct SoundEffect {
    static func playStart() {
        NSSound(named: "Pop")?.play()
    }
    static func playSuccess() {
        NSSound(named: "Tink")?.play()
    }
    static func playCancel() {
        NSSound(named: "Basso")?.play()
    }
}

struct TranscriptionItem: Identifiable, Codable {
    var id = UUID()
    let date: String
    let text: String
    let duration: String
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
    
    @Published var history: [TranscriptionItem] = [] {
        didSet { saveHistory() }
    }
    
    private let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_record.wav")
    
    override init() {
        super.init()
        loadHistory()
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
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
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        
        do {
            if FileManager.default.fileExists(atPath: tempAudioURL.path) {
                try FileManager.default.removeItem(at: tempAudioURL)
            }
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
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateMetering()
            }
        } catch {
            print("[AudioCapture] Ошибка: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        removeEscMonitor()
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        let duration = Date().timeIntervalSince(startTime ?? Date())
        let formattedDuration = String(format: "%.1f сек", duration)
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioSamples = Array(repeating: 0.15, count: 9)
            self.transcribedText = "Расшифровка..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.runTranscription(durationStr: formattedDuration)
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
    
    // MARK: - ИМПОРТ И НАРЕЗКА ДЛИННЫХ ФАЙЛОВ
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
                self.processLongFileInChunks(fileURL: fileURL)
            }
        }
    }
    
    private func processLongFileInChunks(fileURL: URL) {
        let tempWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_file_full.wav")
        
        // 1. Сначала перекодируем файл в стандартный WAV
        guard convertAudioTo16kHzWav(inputURL: fileURL, outputURL: tempWavURL),
              let inputFile = try? AVAudioFile(forReading: tempWavURL) else {
            DispatchQueue.main.async {
                self.isProcessingFile = false
                self.transcribedText = "Ошибка чтения файла"
                OverlayPanelManager.shared.hideOverlay()
            }
            return
        }
        
        let totalFrames = inputFile.length
        let sampleRate = inputFile.processingFormat.sampleRate
        let durationMin = String(format: "%.0f мин", (Double(totalFrames) / sampleRate) / 60.0)
        
        // 25 секунд на 1 чанк
        let chunkSizeInSeconds: Double = 25.0
        let framesPerChunk = AVAudioFrameCount(chunkSizeInSeconds * sampleRate)
        let totalChunks = max(1, Int(ceil(Double(totalFrames) / Double(framesPerChunk))))
        
        var accumulatedText: [String] = []
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        for chunkIndex in 0..<totalChunks {
            let startFrame = Int64(chunkIndex) * Int64(framesPerChunk)
            let frameCountToRead = min(framesPerChunk, AVAudioFrameCount(totalFrames - startFrame))
            
            inputFile.framePosition = startFrame
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: frameCountToRead) else { continue }
            try? inputFile.read(into: pcmBuffer, frameCount: frameCountToRead)
            
            // Сохраняем кусочек 25 сек во временный WAV
            let chunkWavURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_chunk_\(chunkIndex).wav")
            
            if writeBufferToWav(buffer: pcmBuffer, targetFormat: targetFormat, outputURL: chunkWavURL) {
                let chunkText = runCLIOnWav(wavURL: chunkWavURL)
                if !chunkText.isEmpty && chunkText != "Речь не распознана" {
                    accumulatedText.append(chunkText)
                }
                try? FileManager.default.removeItem(at: chunkWavURL)
            }
            
            // Обновляем прогресс (%)
            let progress = Double(chunkIndex + 1) / Double(totalChunks)
            DispatchQueue.main.async {
                self.fileProcessingProgress = progress
            }
        }
        
        let rawText = accumulatedText.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = TextFormatter.formatIntoParagraphs(rawText)
        
        DispatchQueue.main.async {
            self.isProcessingFile = false
            if finalText.isEmpty {
                self.transcribedText = "Речь не распознана"
            } else {
                self.transcribedText = finalText
                
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy, HH:mm"
                let dateStr = formatter.string(from: Date())
                
                let newItem = TranscriptionItem(date: dateStr, text: finalText, duration: durationMin)
                self.history.insert(newItem, at: 0)
                
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
            }
            
            SoundEffect.playSuccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                OverlayPanelManager.shared.hideOverlay()
            }
        }
    }
    
    private func writeBufferToWav(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat, outputURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            let file = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }
    
    private func convertAudioTo16kHzWav(inputURL: URL, outputURL: URL) -> Bool {
        guard let inputFile = try? AVAudioFile(forReading: inputURL) else { return false }
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings)
            guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: targetFormat) else { return false }
            
            let bufferSize: AVAudioFrameCount = 8192
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: bufferSize) else { return false }
            
            let ratio = 16000.0 / inputFile.processingFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(bufferSize) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { return false }
            
            while inputFile.framePosition < inputFile.length {
                try inputFile.read(into: inputBuffer)
                var error: NSError?
                var allConsumed = false
                
                let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                    if allConsumed { outStatus.pointee = .noDataNow; return nil }
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }
                
                if status == .error || error != nil { break }
                try outputFile.write(from: outputBuffer)
            }
            return true
        } catch {
            return false
        }
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
        } catch {
            return ""
        }
    }
    
    private func runTranscription(durationStr: String) {
        let text = runCLIOnWav(wavURL: tempAudioURL)
        
        DispatchQueue.main.async {
            if text.isEmpty {
                self.transcribedText = "Речь не распознана"
            } else {
                self.transcribedText = text
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy, HH:mm"
                let dateStr = formatter.string(from: Date())
                
                let newItem = TranscriptionItem(date: dateStr, text: text, duration: durationStr)
                self.history.insert(newItem, at: 0)
                
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.pasteToActiveApp()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                OverlayPanelManager.shared.hideOverlay()
            }
        }
    }
    
    private func pasteToActiveApp() {
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
    
    func exportTranscription(_ item: TranscriptionItem, format: String = "md") {
        let panel = NSSavePanel()
        panel.title = "Сохранить транскрипцию"
        panel.nameFieldStringValue = "Заметка_\(item.date.replacingOccurrences(of: ":", with: "-")).\(format)"
        
        if panel.runModal() == .OK, let saveURL = panel.url {
            let content = "# Транскрипция Голосок\n**Дата:** \(item.date)\n**Длительность:** \(item.duration)\n\n---\n\n\(item.text)"
            try? content.write(to: saveURL, atomically: true, encoding: .utf8)
        }
    }
    
    func deleteItem(at index: Int) { history.remove(at: index) }
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) { UserDefaults.standard.set(encoded, forKey: "transcription_history") }
    }
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "transcription_history"),
           let decoded = try? JSONDecoder().decode([TranscriptionItem].self, from: data) { self.history = decoded }
    }
}
