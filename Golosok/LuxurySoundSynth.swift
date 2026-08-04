import Foundation
import AudioToolbox

final class LuxurySoundSynth {
    static let shared = LuxurySoundSynth()
    
    private var startSoundID: SystemSoundID = 0
    private var successSoundID: SystemSoundID = 0
    private var cancelSoundID: SystemSoundID = 0
    private var copySoundID: SystemSoundID = 0
    private var deleteSoundID: SystemSoundID = 0
    private var warningSoundID: SystemSoundID = 0
    
    init() {
        prepareSounds()
    }
    
    deinit {
        AudioServicesDisposeSystemSoundID(startSoundID)
        AudioServicesDisposeSystemSoundID(successSoundID)
        AudioServicesDisposeSystemSoundID(cancelSoundID)
        AudioServicesDisposeSystemSoundID(copySoundID)
        AudioServicesDisposeSystemSoundID(deleteSoundID)
        AudioServicesDisposeSystemSoundID(warningSoundID)
    }
    
    private func prepareSounds() {
        if let startData = generateStartSound() {
            startSoundID = createSystemSound(from: startData, fileName: "golosok_start.wav")
        }
        if let successData = generateSuccessSound() {
            successSoundID = createSystemSound(from: successData, fileName: "golosok_success.wav")
        }
        if let cancelData = generateCancelSound() {
            cancelSoundID = createSystemSound(from: cancelData, fileName: "golosok_cancel.wav")
        }
        if let copyData = generateCopySound() {
            copySoundID = createSystemSound(from: copyData, fileName: "golosok_copy.wav")
        }
        if let deleteData = generateDeleteSound() {
            deleteSoundID = createSystemSound(from: deleteData, fileName: "golosok_delete.wav")
        }
        if let warningData = generateWarningSound() {
            warningSoundID = createSystemSound(from: warningData, fileName: "golosok_warning.wav")
        }
    }
    
    private func createSystemSound(from data: Data, fileName: String) -> SystemSoundID {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: tempURL)
        
        var soundID: SystemSoundID = 0
        AudioServicesCreateSystemSoundID(tempURL as CFURL, &soundID)
        return soundID
    }
    
    func playStart() {
        guard AudioCapture.shared.soundEnabled, startSoundID != 0 else { return }
        AudioServicesPlaySystemSound(startSoundID)
    }
    
    func playSuccess() {
        guard AudioCapture.shared.soundEnabled, successSoundID != 0 else { return }
        AudioServicesPlaySystemSound(successSoundID)
    }
    
    func playCancel() {
        guard AudioCapture.shared.soundEnabled, cancelSoundID != 0 else { return }
        AudioServicesPlaySystemSound(cancelSoundID)
    }
    
    func playCopy() {
        guard AudioCapture.shared.soundEnabled, copySoundID != 0 else { return }
        AudioServicesPlaySystemSound(copySoundID)
    }
    
    func playDelete() {
        guard AudioCapture.shared.soundEnabled, deleteSoundID != 0 else { return }
        AudioServicesPlaySystemSound(deleteSoundID)
    }
    
    func playWarning() {
        guard AudioCapture.shared.soundEnabled, warningSoundID != 0 else { return }
        AudioServicesPlaySystemSound(warningSoundID)
    }

    // ==========================================
    // DSP GENERATORS
    // ==========================================
    
    // ==========================================
    // 1. ЗВУК СТАРТА (Вектор ВВЕРХ: 60 -> 135 Гц — Открытие аудиоканала)
    // ==========================================
    private func generateStartSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.12
        let volume: Double = 0.85
        let startFreq = 60.0
        let endFreq = 135.0
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let freq = startFreq + ((endFreq - startFreq) * pow(progress, 0.5))
            let fundamental = sin(2.0 * .pi * freq * t)
            let warmHarmonic = sin(2.0 * .pi * (freq * 1.5) * t) * 0.15
            
            let attack = min(1.0, t / 0.004)
            let decay = exp(-22.0 * t)
            
            let rawSignal = (fundamental + warmHarmonic) * attack * decay * volume
            let sampleVal = Int16(tanh(rawSignal) * 32767.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }
    
    // ==========================================
    // 2. ЗВУК УСПЕХА (Сбалансированный акустический бархат)
    // ==========================================
    private func generateSuccessSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.90
        let volume: Double = 0.38     // Едва ощутимо ослаблен общий микс
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            // 1. Фундамент: D3 (146.83 Гц) вместо C3 (130.8 Гц) — убран давящий саб-гул
            let f0_a = sin(2.0 * .pi * 146.83 * t) * 0.75
            let f0_b = sin(2.0 * .pi * 147.05 * t) * 0.30
            let fundamental = (f0_a + f0_b) * exp(-2.6 * t)
            
            // 2. Тело аккорда: A3 (220.00 Гц)
            let body = sin(2.0 * .pi * 220.00 * t) * 0.30 * exp(-4.0 * t)
            
            // 3. Верхушка: опущена с E4 (329.63 Гц) до D4 (293.66 Гц) — без звона и яркости
            let chime = sin(2.0 * .pi * 293.66 * t) * 0.15 * exp(-7.5 * t)
            
            // 4. Мягкий акустический клик колотушки: D5 (587.33 Гц)
            let malletHit = sin(2.0 * .pi * 587.33 * t) * 0.06 * exp(-32.0 * t)
            
            let attack = min(1.0, t / 0.018)
            
            // S-Curve Fade-Out на финише
            let releaseDuration = 0.25
            let releaseStart = duration - releaseDuration
            let release: Double
            if t > releaseStart {
                let progress = (t - releaseStart) / releaseDuration
                release = 0.5 * (1.0 + cos(.pi * progress))
            } else {
                release = 1.0
            }
            
            let rawSignal = (fundamental + body + chime + malletHit) * attack * release * volume
            let sampleVal = Int16(tanh(rawSignal) * 32767.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

    // ==========================================
    // 3. ЗВУК ОТМЕНЫ (Сухой микро-сброс без саб-гула)
    // ==========================================
    private func generateCancelSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.08
        let volume: Double = 0.50
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let freq = 100.0 - (50.0 * progress)
            let signal = sin(2.0 * .pi * freq * t)
            
            let attack = min(1.0, t / 0.003)
            let decay = exp(-38.0 * t)
            
            let rawSignal = signal * attack * decay * volume
            let sampleVal = Int16(tanh(rawSignal) * 32767.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

    // ==========================================
    // 4. ЗВУК КОПИРОВАНИЯ (Тактильная защёлка вверх: 380 -> 520 Гц)
    // ==========================================
    private func generateCopySound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.045
        let volume: Double = 0.45
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let freq = 380.0 + (140.0 * pow(progress, 0.3))
            let signal = sin(2.0 * .pi * freq * t)
            
            let attack = min(1.0, t / 0.0015)
            let decay = exp(-85.0 * t)
            
            let rawSignal = signal * attack * decay * volume
            let sampleVal = Int16(tanh(rawSignal) * 32767.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

    // ==========================================
    // 5. ЗВУК УДАЛЕНИЯ (Тяжёлый глухой сброс: 130 -> 42 Гц)
    // ==========================================
    private func generateDeleteSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.14
        let volume: Double = 0.65
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let freq = 130.0 - (88.0 * pow(progress, 0.5))
            let signal = sin(2.0 * .pi * freq * t)
            
            let attack = min(1.0, t / 0.004)
            let decay = exp(-18.0 * t)
            let release = min(1.0, (duration - t) / 0.02)
            
            let rawSignal = signal * attack * decay * release * volume
            let sampleVal = Int16(tanh(rawSignal) * 32767.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }
    
    // 6. ЗВУК ВАРНИНГА / ОШИБКИ (Мягкий двойной суб-толчок)
    private func generateWarningSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.16          // 160 мс на всю комбинацию
        let volume: Double = 0.60
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        let t1 = 0.0                 // Первый импульс (удар)
        let t2 = 0.052               // Второй импульс через 52 мс (отдача)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            // 1-й импульс: плотный сброс 140 -> 80 Гц
            var s1 = 0.0
            if t >= t1 {
                let dt1 = t - t1
                let freq1 = 140.0 - (60.0 * pow(min(1.0, dt1 / 0.05), 0.5))
                s1 = sin(2.0 * .pi * freq1 * dt1) * exp(-42.0 * dt1) * min(1.0, dt1 / 0.002)
            }
            
            // 2-й импульс: глуше (115 -> 65 Гц) и тише (-30%) — эффект "упора в стену"
            var s2 = 0.0
            if t >= t2 {
                let dt2 = t - t2
                let freq2 = 115.0 - (50.0 * pow(min(1.0, dt2 / 0.05), 0.5))
                s2 = sin(2.0 * .pi * freq2 * dt2) * exp(-42.0 * dt2) * min(1.0, dt2 / 0.002) * 0.7
            }
            
            let release = min(1.0, (duration - t) / 0.015)
            let rawSignal = (s1 + s2) * release * volume
            let sampleVal = Int16(tanh(rawSignal) * 32767.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

    private func createWavHeader(dataLength: Int, sampleRate: Int, numChannels: Int) -> Data {
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var fileSize = UInt32(36 + dataLength).littleEndian
        header.append(Data(bytes: &fileSize, count: 4))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = 16
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        header.append(Data(bytes: &audioFormat, count: 2))
        var channels = UInt16(numChannels).littleEndian
        header.append(Data(bytes: &channels, count: 2))
        var sampleRateU32 = UInt32(sampleRate).littleEndian
        header.append(Data(bytes: &sampleRateU32, count: 4))
        var byteRate = UInt32(sampleRate * numChannels * 2).littleEndian
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(numChannels * 2).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16
        header.append(Data(bytes: &bitsPerSample, count: 2))
        header.append(contentsOf: "data".utf8)
        var dataSize = UInt32(dataLength).littleEndian
        header.append(Data(bytes: &dataSize, count: 4))
        return header
    }
}
