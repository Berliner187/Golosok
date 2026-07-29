import Foundation
import AVFoundation

class StartupSoundSynth {
    private static var audioPlayer: AVAudioPlayer?
    
    static func playTeslaChime() {
        let sampleRate = 44100.0
        let duration = 3.0
        let numSamples = Int(sampleRate * duration)
        
        var pcmData = Data()
        pcmData.reserveCapacity(numSamples * 4)
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            let baseFreq = 50.0 - (18.0 * pow(progress, 0.35))
            let subBass = sin(2.0 * .pi * baseFreq * t) * 0.65
            
            let pulseFreq = 4.0
            let rhythmPulse = max(0.0, sin(2.0 * .pi * pulseFreq * t))
            let rhythmSynth = sin(2.0 * .pi * (baseFreq * 2.2) * t) * pow(rhythmPulse, 3.5) * 0.35
            
            let secondImpactT = max(0.0, t - 1.0)
            let secondImpact = sin(2.0 * .pi * 40.0 * secondImpactT) * exp(-2.8 * secondImpactT) * 0.5
            
            let attack = min(1.0, t / 0.03)
            let decay = exp(-1.4 * t)
            let mainEnvelope = attack * decay
            
            let rawSignal = (subBass + rhythmSynth + secondImpact) * mainEnvelope * 1.2
            
            let saturatedSignal = tanh(rawSignal) * 0.9
            
            let sampleVal = Int16(max(-32767, min(32767, saturatedSignal * 32767.0))).littleEndian
            
            var left = sampleVal
            var right = sampleVal
            withUnsafeBytes(of: &left) { pcmData.append(contentsOf: $0) }
            withUnsafeBytes(of: &right) { pcmData.append(contentsOf: $0) }
        }
        
        let wavData = createWavHeader(dataLength: pcmData.count, sampleRate: Int(sampleRate), numChannels: 2) + pcmData
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play() // Чистый теплый объемный бас
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
        var audioFormat: UInt16 = 1 // PCM
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
