import Foundation
import AVFoundation

class StartupSoundSynth {
    private static var audioPlayer: AVAudioPlayer?
    
    static func playTeslaChime() {
        let sampleRate = 48000.0
        let duration = 3.0
        let numSamples = Int(sampleRate * duration)
        
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            // =========================================================
            // ФАЗА 1: ВАКУУМНЫЙ СВИП (0.0s - 0.6s)
            // =========================================================
            var phase1Left = 0.0
            var phase1Right = 0.0
            
            if t < 0.65 {
                let attackEnvelope = (1.0 - cos(.pi * min(1.0, t / 0.012))) * 0.5
                let initialThud = sin(2.0 * .pi * 65.0 * t) * exp(-120.0 * t) * attackEnvelope
                
                let riserProgress = min(1.0, t / 0.6)
                let riserFreq = 45.0 + (45.0 * pow(riserProgress, 2.8))
                
                let smoothFadeOut = 0.5 * (1.0 + cos(.pi * min(1.0, max(0.0, t - 0.5) / 0.1)))
                let riserEnvelope = pow(riserProgress, 3.2) * smoothFadeOut
                let riserSub = sin(2.0 * .pi * riserFreq * t) * 0.35 * riserEnvelope
                
                let p1Mono = initialThud + riserSub
                phase1Left = p1Mono
                phase1Right = p1Mono
            }
            
            // =========================================================
            // ФАЗА 2: МОНУМЕНТАЛЬНЫЙ SUB-BOOM (0.85s - 3.0s)
            // =========================================================
            var phase2Left = 0.0
            var phase2Right = 0.0
            
            if t >= 0.85 {
                let t2 = t - 0.85
                let attack2 = (1.0 - cos(.pi * min(1.0, t2 / 0.008))) * 0.5
                
                let subFreq = 90.0 - (64.0 * pow(min(1.0, t2 / 1.4), 0.22))
                let subBass = sin(2.0 * .pi * subFreq * t2) * exp(-1.95 * t2)
                let bodyLow = sin(2.0 * .pi * 36.71 * t2) * 0.55 * exp(-2.8 * t2)
                
                let subLeft = sin(2.0 * .pi * 55.0 * t2) * 0.25 * exp(-4.0 * t2)
                let subRight = sin(2.0 * .pi * 55.0 * (t2 + 0.004)) * 0.25 * exp(-4.0 * t2)
                
                let cabinLeft = sin(2.0 * .pi * 110.0 * t2) * 0.12 * exp(-6.5 * t2)
                let cabinRight = sin(2.0 * .pi * 110.0 * (t2 + 0.002)) * 0.12 * exp(-6.5 * t2)
                
                phase2Left = (subBass + bodyLow + subLeft + cabinLeft) * attack2 * 1.0
                phase2Right = (subBass + bodyLow + subRight + cabinRight) * attack2 * 1.0
            }
            
            // =========================================================
            // ФАЗА 3: ОБЪЕМНЫЙ ГЭБ (1.95s и 2.10s)
            // =========================================================
            var gebLeft = 0.0
            var gebRight = 0.0
            
            if t >= 1.92 && t < 2.06 {
                let tg1 = t - 1.92
                let env1 = sin(.pi * min(1.0, tg1 / 0.12))
                
                let f1 = 140.0 - (70.0 * (tg1 / 0.12))
                let tone = sin(2.0 * .pi * f1 * tg1)
                
                let subStab = sin(2.0 * .pi * 45.0 * tg1) * 0.5
                
                gebLeft += (tone + subStab) * env1 * 0.35
                gebRight += (sin(2.0 * .pi * f1 * (tg1 + 0.003)) + subStab) * env1 * 0.35
            }
            
            if t >= 2.10 && t < 2.25 {
                let tg2 = t - 2.10
                let env2 = sin(.pi * min(1.0, tg2 / 0.13))
                
                let f2 = 125.0 - (65.0 * (tg2 / 0.13))
                let tone = sin(2.0 * .pi * f2 * tg2)
                let subStab = sin(2.0 * .pi * 40.0 * tg2) * 0.6
                
                gebLeft += (tone + subStab) * env2 * 0.40
                gebRight += (sin(2.0 * .pi * f2 * (tg2 + 0.004)) + subStab) * env2 * 0.40
            }
            
            // =========================================================
            // СВЕДЕНИЕ И НАСЫЩЕНИЕ
            // =========================================================
            let rawLeft = (phase1Left + phase2Left + gebLeft) * 1.1
            let rawRight = (phase1Right + phase2Right + gebRight) * 1.1
            
            let satLeft = rawLeft / (1.0 + abs(rawLeft) * 0.20)
            let satRight = rawRight / (1.0 + abs(rawRight) * 0.20)
            
            let sampleValLeft = Int16(max(-32767, min(32767, satLeft * 29000.0))).littleEndian
            let sampleValRight = Int16(max(-32767, min(32767, satRight * 29000.0))).littleEndian
            
            var left = sampleValLeft
            var right = sampleValRight
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        
        let wavData = createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("[Synth Error] \(error.localizedDescription)")
        }
    }
    
    private static func createWavHeader(dataLength: Int, sampleRate: Int, numChannels: Int) -> Data {
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
