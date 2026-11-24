import Foundation

/// Фасад над `SoundEngine` — прежний API сохранён, вызывающий код (`SoundEffect.*`) не меняется.
/// Проверка `soundEnabled` и наложение звуков друг на друга — внутри `SoundEngine`.
final class LuxurySoundSynth {
    static let shared = LuxurySoundSynth()

    init() {}

    func playStart()   { SoundEngine.shared.play(.start) }
    func playStop()    { SoundEngine.shared.play(.stop) }
    func playSuccess() { SoundEngine.shared.play(.success) }
    func playCancel()  { SoundEngine.shared.play(.cancel) }
    func playCopy()    { SoundEngine.shared.play(.copy) }
    func playDelete()  { SoundEngine.shared.play(.delete) }
    func playWarning() { SoundEngine.shared.play(.warning) }
}
