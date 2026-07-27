import Foundation
import AVFoundation
import AppKit

struct TranscriptionItem: Identifiable, Codable {
    var id = UUID()
    let date: String
    let text: String
    let duration: String
}

// MARK: - Системные звуки macOS
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

class AudioCapture: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var escMonitor: Any?

    static let shared = AudioCapture()
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    
    @Published var isRecording = false
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
    
    // ОТМЕНА ЗАПИСИ ПО ESC
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
        startTime = Date()
        SoundEffect.playStart()
        
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelRecording()
            }
        }
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.transcribedText = "Запись идет..."
            OverlayPanelManager.shared.showOverlay()
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    DispatchQueue.main.async { self.startRecording() }
                }
            }
            return
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.transcribedText = "Нет доступа к микрофону."
            }
            return
        case .authorized:
            break
        @unknown default:
            break
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
    
    private func removeEscMonitor() {
         if let monitor = escMonitor {
             NSEvent.removeMonitor(monitor)
             escMonitor = nil
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
    
    private func updateMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        
        let power = recorder.averagePower(forChannel: 0)
        // Высокая чувствительность эквалайзера (-40дБ ... 0дБ)
        let level = max(0.15, min(1.0, (power + 40.0) / 35.0))
        
        var newSamples: [Float] = []
        for i in 0..<9 {
            let randomFactor = Float.random(in: 0.7...1.3)
            let targetVal = max(0.15, min(1.0, level * randomFactor))
            
            let currentVal = i < audioSamples.count ? audioSamples[i] : 0.15
            let smoothedVal = currentVal * 0.4 + targetVal * 0.6
            newSamples.append(smoothedVal)
        }
        
        DispatchQueue.main.async {
            self.audioSamples = newSamples
        }
    }
    
    private func runTranscription(durationStr: String) {
        guard let cliPath = Bundle.main.path(forResource: "transcribe-cli", ofType: nil),
              let modelPath = Bundle.main.path(forResource: "gigaam", ofType: "gguf") else {
            DispatchQueue.main.async {
                self.transcribedText = "Ошибка ресурсов"
                OverlayPanelManager.shared.hideOverlay()
            }
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-m", modelPath, tempAudioURL.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: data, encoding: .utf8) ?? ""
            
            let lines = rawOutput.components(separatedBy: .newlines)
            var finalText = ""
            
            if let textLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("text:") }) {
                let extracted = String(textLine.trimmingCharacters(in: .whitespaces).dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if extracted != "(empty)" {
                    finalText = extracted
                }
            } else {
                let cleanedLines = lines.filter { line in
                    let l = line.trimmingCharacters(in: .whitespaces)
                    if l.isEmpty || l == "(empty)" { return false }
                    if l.hasPrefix("audio:") || l.hasPrefix("samples:") || l.hasPrefix("duration:") { return false }
                    if l.hasPrefix("sample rate") || l.hasPrefix("model:") || l.hasPrefix("backend:") { return false }
                    if l.hasPrefix("name:") || l.hasPrefix("license:") || l.hasPrefix("max audio:") { return false }
                    if l.hasPrefix("run:") || l.hasPrefix("words:") || l.hasPrefix("tokens:") || l.hasPrefix("realtime:") { return false }
                    return true
                }
                finalText = cleanedLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            DispatchQueue.main.async {
                if finalText.isEmpty {
                    self.transcribedText = "Речь не распознана"
                } else {
                    self.transcribedText = finalText
                    
                    let formatter = DateFormatter()
                    formatter.dateFormat = "dd.MM.yyyy, HH:mm"
                    let dateStr = formatter.string(from: Date())
                    
                    let newItem = TranscriptionItem(date: dateStr, text: finalText, duration: durationStr)
                    self.history.insert(newItem, at: 0)
                    
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalText, forType: .string)
                    
                    self.pasteToActiveApp()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    OverlayPanelManager.shared.hideOverlay()
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.transcribedText = "Ошибка процесса"
                OverlayPanelManager.shared.hideOverlay()
            }
        }
    }
    
    // Эмуляция Cmd+V с запросом прав
    private func pasteToActiveApp() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        SoundEffect.playSuccess() // 🔊 ЗВУК УСПЕШНОЙ ВСТАВКИ
        
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

    func deleteItem(at index: Int) {
        history.remove(at: index)
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "transcription_history")
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "transcription_history"),
           let decoded = try? JSONDecoder().decode([TranscriptionItem].self, from: data) {
            self.history = decoded
        }
    }
}
