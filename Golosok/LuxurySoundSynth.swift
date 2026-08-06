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
        let duration = 0.18
        let volume: Double = 0.70
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let mainFreq = 105.0 - (67.0 * pow(progress, 0.4))
            let mainBody = sin(2.0 * .pi * mainFreq * t)
            
            let subFreq = 55.0 - (25.0 * progress)
            let subBody = sin(2.0 * .pi * subFreq * t) * 0.55 * exp(-14.0 * t)
            
            let latchClick = (t < 0.0025) ? sin(2.0 * .pi * 220.0 * t) * 0.35 : 0.0
            
            let attack = min(1.0, t / 0.002)
            let decay = exp(-12.5 * t)
            let release = min(1.0, (duration - t) / 0.03)
            
            let rawSignal = (mainBody + subBody + latchClick) * attack * decay * release * volume
            
            let sampleVal = Int16(tanh(rawSignal) * 26000.0).littleEndian
            
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
        let duration = 0.058
        let volume: Double = 0.55
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let glideFreq = 220.0 - (132.0 * pow(progress, 0.28))
            
            let mainSignalLeft = sin(2.0 * .pi * glideFreq * t)
            let mainSignalRight = sin(2.0 * .pi * glideFreq * (t + 0.0015))
            
            let subTone = sin(2.0 * .pi * (glideFreq * 0.5) * t) * 0.35
            
            let attack = (1.0 - cos(.pi * min(1.0, t / 0.003))) * 0.5
            let decay = exp(-48.0 * t)
            
            let rawLeft = (mainSignalLeft + subTone) * attack * decay * volume
            let rawRight = (mainSignalRight + subTone) * attack * decay * volume
            
            let cleanLeft = rawLeft / (1.0 + abs(rawLeft) * 0.1)
            let cleanRight = rawRight / (1.0 + abs(rawRight) * 0.1)
            
            let sampleValLeft = Int16(max(-32767, min(32767, cleanLeft * 27000.0))).littleEndian
            let sampleValRight = Int16(max(-32767, min(32767, cleanRight * 27000.0))).littleEndian
            
            var left = sampleValLeft, right = sampleValRight
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
        let duration = 0.22
        let volume: Double = 0.65
        
        let numSamples = Int(sampleRate * duration)
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        let t1 = 0.00
        let t2 = 0.045
        let t3 = 0.090
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            var sigLeft = 0.0
            var sigRight = 0.0
            
            if t >= t1 {
                let dt1 = t - t1
                let env1 = exp(-55.0 * dt1) * (1.0 - cos(.pi * min(1.0, dt1 / 0.002))) * 0.5
                let f1 = 125.0 - (60.0 * pow(min(1.0, dt1 / 0.04), 0.4))
                let tone = sin(2.0 * .pi * f1 * dt1) + sin(2.0 * .pi * (f1 * 0.5) * dt1) * 0.4
                
                sigLeft += tone * env1 * 0.75
                sigRight += tone * env1 * 0.45
            }
            
            if t >= t2 {
                let dt2 = t - t2
                let env2 = exp(-55.0 * dt2) * (1.0 - cos(.pi * min(1.0, dt2 / 0.002))) * 0.5
                let f2 = 110.0 - (55.0 * pow(min(1.0, dt2 / 0.04), 0.4))
                let tone = sin(2.0 * .pi * f2 * dt2) + sin(2.0 * .pi * (f2 * 0.5) * dt2) * 0.4
                
                sigLeft += tone * env2 * 0.85
                sigRight += tone * env2 * 0.85
            }
            
            if t >= t3 {
                let dt3 = t - t3
                let env3 = exp(-48.0 * dt3) * (1.0 - cos(.pi * min(1.0, dt3 / 0.002))) * 0.5
                let f3 = 100.0 - (55.0 * pow(min(1.0, dt3 / 0.05), 0.4))
                let tone = sin(2.0 * .pi * f3 * dt3) + sin(2.0 * .pi * (f3 * 0.5) * dt3) * 0.5
                
                sigLeft += tone * env3 * 0.55
                sigRight += tone * env3 * 0.95
            }
            
            let release = min(1.0, (duration - t) / 0.02)
            let rawLeft = sigLeft * release * volume
            let rawRight = sigRight * release * volume
            
            let satLeft = rawLeft / (1.0 + abs(rawLeft) * 0.15)
            let satRight = rawRight / (1.0 + abs(rawRight) * 0.15)
            
            let sampleValLeft = Int16(max(-32767, min(32767, satLeft * 27000.0))).littleEndian
            let sampleValRight = Int16(max(-32767, min(32767, satRight * 27000.0))).littleEndian
            
            var left = sampleValLeft, right = sampleValRight
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
