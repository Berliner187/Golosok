import Foundation
import AppKit

final class LuxurySoundSynth {
    static let shared = LuxurySoundSynth()
        
    private var startSound: NSSound?
    private var successSound: NSSound?
    private var cancelSound: NSSound?
    private var copySound: NSSound?
    private var deleteSound: NSSound?
    private var warningSound: NSSound?
    
    init() {
        prepareSounds()
    }
    
    private func prepareSounds() {
        if let d = generateStartSound() { startSound = NSSound(data: d) }
        if let d = generateSuccessSound() { successSound = NSSound(data: d) }
        if let d = generateCancelSound() { cancelSound = NSSound(data: d) }
        if let d = generateCopySound() { copySound = NSSound(data: d) }
        if let d = generateDeleteSound() { deleteSound = NSSound(data: d) }
        if let d = generateWarningSound() { warningSound = NSSound(data: d) }
    }
    
    func playStart() {
        guard AudioCapture.shared.soundEnabled else { return }
        startSound?.stop()
        startSound?.play()
    }
    
    func playSuccess() {
        guard AudioCapture.shared.soundEnabled else { return }
        successSound?.stop()
        successSound?.play()
    }
    
    func playCancel() {
        guard AudioCapture.shared.soundEnabled else { return }
        cancelSound?.stop()
        cancelSound?.play()
    }
    
    func playCopy() {
        guard AudioCapture.shared.soundEnabled else { return }
        copySound?.stop()
        copySound?.play()
    }
    
    func playDelete() {
        guard AudioCapture.shared.soundEnabled else { return }
        deleteSound?.stop()
        deleteSound?.play()
    }
    
    func playWarning() {
        guard AudioCapture.shared.soundEnabled else { return }
        warningSound?.stop()
        warningSound?.play()
    }

    // ==========================================
    // DSP GENERATORS (С ЗАПАСОМ ГРОМКОСТИ -3dB FS)
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
            
            // ХЕДРУМ -3dB (23000 вместо 32767) - ИЗБАВЛЯЕТ ОТ ХРИПА!
            let sampleVal = Int16(tanh(rawSignal) * 23000.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }
    
    private func generateSuccessSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.67
        let volume: Double = 0.42
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        let releaseDuration = 0.2
        let releaseStart = duration - releaseDuration
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            let fundamental = sin(2.0 * .pi * 146.83 * t) * 0.65 * exp(-2.8 * t)
            
            let body = sin(2.0 * .pi * 220.00 * t) * 0.30 * exp(-4.2 * t)
            
            let chime = sin(2.0 * .pi * 293.66 * t) * 0.18 * exp(-6.5 * t)
            
            let malletHit = sin(2.0 * .pi * 587.33 * t) * 0.05 * exp(-30.0 * t)
            
            let attack = min(1.0, t / 0.015)
            
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

    private func generateCancelSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.12
        let volume: Double = 0.60
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let freq = 90.0 - (50.0 * progress)
            let signal = sin(2.0 * .pi * freq * t)
            
            let attack = min(1.0, t / 0.003)
            let decay = exp(-28.0 * t)
            
            let rawSignal = signal * attack * decay * volume
            let sampleVal = Int16(tanh(rawSignal) * 23000.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

    private func generateCopySound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.045
        let volume: Double = 0.50
        
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
            let sampleVal = Int16(tanh(rawSignal) * 23000.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

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
            let sampleVal = Int16(tanh(rawSignal) * 23000.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }
    
    private func generateWarningSound() -> Data? {
        let sampleRate = 48000.0
        let duration = 0.16
        let volume: Double = 0.60
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        let t1 = 0.0
        let t2 = 0.052
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            var s1 = 0.0
            if t >= t1 {
                let dt1 = t - t1
                let freq1 = 140.0 - (60.0 * pow(min(1.0, dt1 / 0.05), 0.5))
                s1 = sin(2.0 * .pi * freq1 * dt1) * exp(-42.0 * dt1) * min(1.0, dt1 / 0.002)
            }
            
            var s2 = 0.0
            if t >= t2 {
                let dt2 = t - t2
                let freq2 = 115.0 - (50.0 * pow(min(1.0, dt2 / 0.05), 0.5))
                s2 = sin(2.0 * .pi * freq2 * dt2) * exp(-42.0 * dt2) * min(1.0, dt2 / 0.002) * 0.7
            }
            
            let release = min(1.0, (duration - t) / 0.015)
            let rawSignal = (s1 + s2) * release * volume
            let sampleVal = Int16(tanh(rawSignal) * 23000.0).littleEndian
            
            var left = sampleVal, right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        return createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
    }

    private func createWavHeader(dataLength: Int, sampleRate: Int, numChannels: Int) -> Data {
        let fileSize = UInt32(36 + dataLength)
        let byteRate = UInt32(sampleRate * numChannels * 2)
        let blockAlign = UInt16(numChannels * 2)
        let bitsPerSample: UInt16 = 16
        let sampleRateU32 = UInt32(sampleRate)
        let channelsU16 = UInt16(numChannels)
        let formatU16: UInt16 = 1
        let subchunk1Size: UInt32 = 16
        
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        withUnsafeBytes(of: fileSize.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        header.append(contentsOf: [0x66, 0x6d, 0x74, 0x20])
        withUnsafeBytes(of: subchunk1Size.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: formatU16.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: channelsU16.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: sampleRateU32.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        withUnsafeBytes(of: UInt32(dataLength).littleEndian) { header.append(contentsOf: $0) }
        
        return header
    }
}
