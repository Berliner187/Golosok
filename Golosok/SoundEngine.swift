import Foundation
import AVFoundation
import CoreAudio

// MARK: - Воспроизведение

/// Звуковая айдентика Голосок. Все звуки в одной тональности (D) и одном тембре:
/// мягкий «стеклянный» тон + глухой «удар закрывающейся двери» + воздух + короткий реверб.
/// Всё рендерится один раз в фоне при старте; воспроизведение — через AVAudioEngine
/// с пулом плееров, поэтому звуки накладываются друг на друга и не обрывают друг друга (нет щелчков).
final class SoundEngine: @unchecked Sendable {
    static let shared = SoundEngine()

    enum Cue: CaseIterable { case start, stop, success, cancel, copy, delete, warning }

    /// Рендерим на 12 кГц: в звуках нет ничего выше ~1 кГц, а считать в 4 раза меньше сэмплов
    /// критично для Debug-сборки. Приведение к частоте выхода делает миксер AVAudioEngine.
    private let sampleRate = 12_000.0
    private var engine = AVAudioEngine()          // var: пересоздаётся при смене устройства вывода
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: 12_000, channels: 2)!
    private var players: [AVAudioPlayerNode] = []
    private var busyUntil: [TimeInterval] = []
    private var cueBuffers: [Cue: AVAudioPCMBuffer] = [:]
    private var startupBuffer: AVAudioPCMBuffer?
    private var pendingStartupOrigin: Date?
    private var warmedUp = false
    private var configured = false
    private var restartWork: DispatchWorkItem?
    private var configObserver: NSObjectProtocol?
    private var startFailures = 0
    private var boundOutputDevice: AudioObjectID = 0     // устройство вывода, к которому привязан текущий движок
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var startupPlayer: Int?                 // индекс плеера, на котором играет стартовый звук

    private init() {}

    // MARK: API

    /// Вызвать как можно раньше (GolosokApp.init). Рендер идёт в фоне: сначала стартовый звук, потом остальные.
    func warmUp() {
        guard !warmedUp else { return }
        warmedUp = true
        // Движок запускаем сразу (десятки–сотни мс), чтобы к моменту звука он уже работал.
        DispatchQueue.main.async { [weak self] in self?.ensureRunning() }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let startup = Synth().renderStartup()
            DispatchQueue.main.async { self?.storeStartup(startup) }
            // Звуки записи нужны первыми (запись можно включить сразу после запуска), остальные — тихо в фоне,
            // чтобы рендер не отбирал процессор у запуска записи.
            DispatchQueue.global(qos: .userInitiated).async {
                for cue in [Cue.start, Cue.stop] {
                    let sound = Synth().render(cue)
                    DispatchQueue.main.async { self?.store(cue, sound) }
                }
                DispatchQueue.global(qos: .background).async {
                    for cue in Cue.allCases where cue != .start && cue != .stop {
                        let sound = Synth().render(cue)
                        DispatchQueue.main.async { self?.store(cue, sound) }
                    }
                }
            }
        }
    }

    /// Сплэш стартует сразу и НЕ ждёт звук. `origin` — момент старта сплэша.
    /// Если звук уже готов — играем с начала; если дорендерился позже — вступаем с нужного места
    /// (offset = сколько уже прошло), поэтому звук всё равно совпадает с картинкой.
    func playStartup(origin: Date) {
        let go = { [self] in
            guard AudioCapture.shared.soundEnabled else { return }
            pendingStartupOrigin = origin
            playPendingStartup()
        }
        if Thread.isMainThread { go() } else { DispatchQueue.main.async { go() } }
    }

    func play(_ cue: Cue) {
        let go = { [self] in
            guard AudioCapture.shared.soundEnabled, let buf = cueBuffers[cue] else { return }
            schedule(buf)
        }
        if Thread.isMainThread { go() } else { DispatchQueue.main.async { go() } }
    }

    // MARK: Внутреннее (только main)

    private func storeStartup(_ s: RenderedSound) {
        startupBuffer = makeBuffer(s)
        ensureRunning()
        playPendingStartup()
    }

    private func playPendingStartup() {
        guard let origin = pendingStartupOrigin, let buf = startupBuffer else { return }
        pendingStartupOrigin = nil
        ensureRunning()
        let offset = Date().timeIntervalSince(origin)
        if offset > 1.25 { return }          // удар «замка» (1.15 с) уже прошёл — в середину не вступаем
        if offset < 0.03 {
            schedule(buf, startup: true)
        } else if let tail = suffix(of: buf, from: offset) {
            schedule(tail, startup: true)
        }
    }

    /// Копия буфера без первых `seconds` секунд — чтобы вступить синхронно с уже идущей анимацией.
    private func suffix(of buf: AVAudioPCMBuffer, from seconds: Double) -> AVAudioPCMBuffer? {
        let skip = AVAudioFrameCount(seconds * sampleRate)
        guard skip < buf.frameLength, let src = buf.floatChannelData else { return nil }
        let n = buf.frameLength - skip
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n),
              let dst = out.floatChannelData else { return nil }
        out.frameLength = n
        for c in 0..<2 {
            memcpy(dst[c], src[c] + Int(skip), Int(n) * MemoryLayout<Float>.size)
        }
        return out
    }

    private func store(_ cue: Cue, _ s: RenderedSound) {
        if let buf = makeBuffer(s) { cueBuffers[cue] = buf }
    }

    private func makeBuffer(_ s: RenderedSound) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(s.left.count)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n),
              let ch = buf.floatChannelData else { return nil }
        buf.frameLength = n
        let bytes = s.left.count * MemoryLayout<Float>.size
        s.left.withUnsafeBufferPointer { memcpy(ch[0], $0.baseAddress!, bytes) }
        s.right.withUnsafeBufferPointer { memcpy(ch[1], $0.baseAddress!, bytes) }
        return buf
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        observeOutputDevice()
        buildGraph()
    }

    // MARK: Устройство вывода (наушники вынули / вставили)

    private static func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    /// Независимый от AVAudioEngine триггер: CoreAudio сам сообщает, что системное устройство вывода сменилось.
    /// Уведомление движка о смене конфигурации приходит не всегда (при вынутых наушниках он может остаться
    /// «запущенным», но привязанным к ушедшему устройству — и звук пропадает насовсем).
    private func observeOutputDevice() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            AppLogger.shared.warn("Sound", "Устройство вывода звука сменилось — пересоздаю движок")
            self?.scheduleRebuild(after: 0.3)
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
    }

    /// Граф: 6 плееров → миксер → выход. Собирается при старте и при каждом пересоздании движка.
    private func buildGraph() {
        boundOutputDevice = SoundEngine.defaultOutputDevice()
        players.removeAll()
        busyUntil.removeAll()
        startupPlayer = nil
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
            busyUntil.append(0)
        }
        // Запас по уровню: когда звуки накладываются, сумма не должна доходить до 0 dBFS (клиппинг = хрип).
        engine.mainMixerNode.outputVolume = 0.8

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.handleConfigurationChange() }
    }

    /// Смена устройства/формата (наушники вынули или вставили, AirPods, включение микрофона).
    /// Уведомления приходят пачкой, пока устройство перестраивается, — реагируем один раз, с паузой.
    private func handleConfigurationChange() {
        AppLogger.shared.warn("Sound", "Аудио-конфигурация изменилась — пересоздаю движок звука",
                              details: "AVAudioEngineConfigurationChange")
        scheduleRebuild(after: 0.3)
    }

    private func scheduleRebuild(after delay: TimeInterval) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildEngine() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Полностью пересоздаёт движок. После смены устройства вывода старый граф остаётся привязанным
    /// к ушедшему устройству: простой `start()` не помогает, и звук пропадает насовсем.
    private func rebuildEngine() {
        if let o = configObserver {
            NotificationCenter.default.removeObserver(o)
            configObserver = nil
        }
        for p in players { p.stop() }
        engine.stop()
        engine = AVAudioEngine()
        buildGraph()
        startEngine()
    }

    private func startEngine() {
        engine.prepare()
        do {
            try engine.start()
            startFailures = 0
        } catch {
            AppLogger.shared.warn("Sound", "Не удалось запустить аудиодвижок",
                                  details: error.localizedDescription)
            startFailures += 1
            if startFailures <= 5 { scheduleRebuild(after: 0.5) }   // устройство ещё перестраивается — пробуем снова
        }
    }

    private func ensureRunning() {
        configureIfNeeded()
        // Страховка: если устройство вывода сменилось, а уведомления не пришли, — пересоздаём движок прямо сейчас.
        if boundOutputDevice != SoundEngine.defaultOutputDevice() {
            rebuildEngine()
            return
        }
        guard !engine.isRunning else { return }
        startEngine()
    }

    private func schedule(_ buf: AVAudioPCMBuffer, startup: Bool = false) {
        ensureRunning()
        guard engine.isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var idx = busyUntil.firstIndex(where: { $0 <= now })
        if idx == nil {
            idx = busyUntil.indices.min(by: { busyUntil[$0] < busyUntil[$1] })
            if let i = idx { players[i].stop() }
        }
        guard let i = idx else { return }
        busyUntil[i] = now + Double(buf.frameLength) / sampleRate
        players[i].volume = 1

        // Наложение: если стартовый звук ещё звучит, а включается другой, плавно приглушаем стартовый хвост —
        // иначе сумма клиппирует, и это слышно как хрип.
        if startup {
            startupPlayer = i
        } else if startupPlayer == i {
            startupPlayer = nil
        }
        players[i].scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        players[i].play()
    }

    /// Плавно (≈150 мс) опускает громкость плеера до 25 %.
    private func duck(_ index: Int) {
        guard players.indices.contains(index) else { return }
        let player = players[index]
        let from = player.volume
        guard from > 0.3 else { return }
        for step in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015 * Double(step)) { [weak self, weak player] in
                guard let self, let player, self.players.indices.contains(index),
                      self.players[index] === player, self.startupPlayer == index else { return }
                player.volume = from + (0.25 - from) * Float(step) / 10
            }
        }
    }
}

// MARK: - Рендер (чистый DSP, без AVFoundation)

struct RenderedSound: Sendable {
    var left: [Float]
    var right: [Float]
}

private final class Noise {
    private var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    private func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    private func uniform() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
    func gauss() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
    func vector(_ n: Int) -> [Double] { (0..<n).map { _ in gauss() } }
}

private struct Mix {
    var l: [Double]
    var r: [Double]
    let sr: Double

    init(seconds: Double, sr: Double) {
        let z = [Double](repeating: 0, count: Int(seconds * sr))
        l = z
        r = z
        self.sr = sr
    }

    var seconds: Double { Double(l.count) / sr }

    /// Панорама по закону равной мощности.
    mutating func add(_ sig: [Double], at t0: Double, pan: Double = 0, gain: Double = 1) {
        let i = Int(t0 * sr)
        guard i < l.count else { return }
        let m = min(sig.count, l.count - i)
        let a = (pan + 1) * Double.pi / 4
        let gl = cos(a) * gain, gr = sin(a) * gain
        for k in 0..<m {
            l[i + k] += sig[k] * gl
            r[i + k] += sig[k] * gr
        }
    }
}

private final class Synth {
    let sr = 12_000.0
    let noise = Noise()

    // Ноты (тональность D) — только низкий регистр, выше D4 не поднимаемся
    static func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
    static let D2 = Synth.hz(38), A2 = Synth.hz(45), D3 = Synth.hz(50), A3 = Synth.hz(57), D4 = Synth.hz(62)

    // MARK: примитивы

    func raisedAttack(_ x: inout [Double], _ secs: Double) {
        let k = min(max(1, Int(secs * sr)), x.count)
        for i in 0..<k { x[i] *= 0.5 * (1 - cos(Double.pi * Double(i) / Double(k))) }
    }

    func tailFade(_ x: inout [Double], _ secs: Double) {
        let k = min(x.count, Int(secs * sr))
        guard k > 0 else { return }
        for i in 0..<k {
            x[x.count - k + i] *= 0.5 * (1 + cos(Double.pi * Double(i) / Double(k)))
        }
    }

    func lowpass1(_ x: [Double], _ fc: Double) -> [Double] {
        let a = exp(-2 * Double.pi * fc / sr)
        var y = [Double](repeating: 0, count: x.count)
        var prev = 0.0
        for i in 0..<x.count {
            prev = (1 - a) * x[i] + a * prev
            y[i] = prev
        }
        return y
    }

    func highpass(_ x: [Double], fc: Double, q: Double = 0.707) -> [Double] {
        let w0 = 2 * Double.pi * fc / sr
        let al = sin(w0) / (2 * q)
        let c = cos(w0)
        let a0 = 1 + al
        let b0 = (1 + c) / 2 / a0, b1 = -(1 + c) / a0, b2 = b0
        let a1 = -2 * c / a0, a2 = (1 - al) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var y = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]
            y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }

    func lowpass2(_ x: [Double], fc: Double, q: Double = 0.707) -> [Double] {
        let w0 = 2 * Double.pi * fc / sr
        let al = sin(w0) / (2 * q)
        let c = cos(w0)
        let a0 = 1 + al
        let b0 = (1 - c) / 2 / a0, b1 = (1 - c) / a0, b2 = b0
        let a1 = -2 * c / a0, a2 = (1 - al) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var y = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]
            y2 = y1; y1 = v
            y[i] = v
        }
        return y
    }

    // MARK: голоса

    /// Мягкий «стеклянно-маримбовый» тон. Частоты фиксированы, затухание — рекуррентное умножение.
    func pluck(_ freq: Double, tau: Double, attack: Double = 0.005, maxDur: Double = 8,
               partials custom: [(Double, Double, Double)]? = nil) -> [Double] {
        let partials = custom ?? [(1, 1, 1), (2, 0.22, 0.55), (2.76, 0.07, 0.25), (5.4, 0.02, 0.10)]
        let n = Int(min(tau * 6.5 + attack, maxDur) * sr)
        var out = [Double](repeating: 0, count: n)
        for (ratio, amp, decayScale) in partials {
            let f = freq * ratio
            if f > sr * 0.4 { continue }
            let w = 2 * Double.pi * f / sr
            let dec = exp(-1 / (sr * tau * decayScale))
            var env = 1.0
            for i in 0..<n {
                out[i] += amp * sin(w * Double(i)) * env
                env *= dec
            }
        }
        raisedAttack(&out, attack)
        tailFade(&out, 0.05)
        return out
    }

    func note(_ m: inout Mix, _ f: Double, at t: Double, tau: Double, attack: Double = 0.005,
              pan: Double = 0, gain: Double, partials: [(Double, Double, Double)]? = nil) {
        m.add(pluck(f, tau: tau, attack: attack, maxDur: max(0.01, m.seconds - t), partials: partials),
              at: t, pan: pan, gain: gain)
    }

    /// Тёплая «подушка» под аккордом: два слегка расстроенных синуса на ноту.
    func pad(_ freqs: [Double], dur: Double, attack: Double, tau: Double, h2: Double = 0.18) -> [Double] {
        let n = Int(dur * sr)
        var out = [Double](repeating: 0, count: n)
        for f in freqs {
            for det in [-0.0009, 0.0009] {
                let ff = f * (1 + det)
                let w = 2 * Double.pi * ff / sr
                for i in 0..<n {
                    let p = w * Double(i)
                    out[i] += sin(p) + h2 * sin(2 * p)
                }
            }
        }
        let norm = 1 / Double(freqs.count * 2)
        for i in 0..<n {
            let t = Double(i) / sr
            out[i] *= (1 - exp(-t / attack)) * exp(-t / tau) * norm
        }
        tailFade(&out, 0.1)
        return out
    }

    /// «Закрывающаяся дверь»: глухое тело + подушка воздуха + едва заметный щелчок защёлки.
    func thock(f0: Double, f1: Double, tau: Double, noiseFc: Double, noiseAmt: Double, click: Double) -> [Double] {
        let n = Int((tau * 7 + 0.03) * sr)
        let k = 0.03
        var body = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let ph = 2 * Double.pi * (f1 * t + (f0 - f1) * k * (1 - exp(-t / k)))
            body[i] = sin(ph) * exp(-t / tau) + 0.38 * sin(2 * ph) * exp(-t / (tau * 0.45))
        }
        raisedAttack(&body, 0.0015)

        var nz = lowpass1(lowpass1(noise.vector(n), noiseFc), noiseFc)
        raisedAttack(&nz, 0.001)
        for i in 0..<n { nz[i] *= exp(-(Double(i) / sr) / 0.011) * noiseAmt * 3.2 }

        var cl = [Double](repeating: 0, count: n)
        if click > 0 {
            let c0 = noise.vector(n)
            let lp = lowpass1(c0, 2500)
            var c = [Double](repeating: 0, count: n)
            for i in 0..<n { c[i] = c0[i] - lp[i] }
            c = lowpass1(c, 6500)
            raisedAttack(&c, 0.0004)
            for i in 0..<n { cl[i] = c[i] * exp(-(Double(i) / sr) / 0.0016) * click }
        }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n { out[i] = body[i] + nz[i] + cl[i] }
        tailFade(&out, 0.02)
        return out
    }

    /// Короткая тональная «тяга» (доводчик): линейный глайд частоты, фаза накапливается.
    func sweep(dur: Double, f0: Double, f1: Double, shape: (Double) -> Double) -> [Double] {
        let n = Int(dur * sr)
        var out = [Double](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let p = Double(i) / Double(n)
            phase += 2 * Double.pi * (f0 + (f1 - f0) * p) / sr
            out[i] = sin(phase) * shape(p)
        }
        return out
    }

    /// Шум через полосовой SVF с плавающей частотой — «воздух» (подъём, блик, выдох).
    func air(dur: Double, fc0: Double, fc1: Double, q: Double = 1.4, shape: (Double) -> Double) -> [Double] {
        let n = Int(dur * sr)
        let x = noise.vector(n)
        var low = 0.0, band = 0.0
        let qq = 1 / q
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let p = Double(i) / Double(n)
            let fc = min(max(fc0 * pow(fc1 / fc0, p), 15), sr * 0.2)
            let f = 2 * sin(Double.pi * fc / sr)
            low += f * band
            let high = x[i] - low - qq * band
            band += f * high
            out[i] = band * shape(p) * 0.5
        }
        return out
    }

    /// Гармонический «разгон»: три расстроенных голоса, фаза накапливается, фильтр раскрывается.
    func riser(dur: Double, fStart: Double, octaves: Double, fc0: Double, fc1: Double, harm: Int = 12) -> [([Double], Double)] {
        let n = Int(dur * sr)
        var result: [([Double], Double)] = []
        for (detCents, pan) in [(-7.0, -0.5), (0.0, 0.0), (7.0, 0.5)] {
            let detMul = pow(2, detCents / 1200)
            var s = [Double](repeating: 0, count: n)
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let p = t / dur
                let f = fStart * pow(2, octaves * pow(p, 1.8)) * detMul
                let fc = fc0 * pow(fc1 / fc0, pow(p, 1.4))
                phase += 2 * Double.pi * f / sr
                var acc = 0.0
                for k in 1...harm {
                    let fk = f * Double(k)
                    if fk >= sr * 0.4 { break }
                    acc += (1 / Double(k)) / (1 + pow(fk / fc, 4)) * sin(Double(k) * phase)
                }
                let tail = 0.5 * (1 + cos(Double.pi * min(max((t - (dur - 0.03)) / 0.03, 0), 1)))
                s[i] = acc * pow(p, 2.2) * tail   // последние 30 мс — в ноль, до удара
            }
            result.append((s, pan))
        }
        return result
    }

    // MARK: реверб и мастеринг

    /// Schroeder/Moorer: 6 гребёнок с демпфированием + 2 all-pass на канал, предзадержка, тёмный хвост.
    func reverb(_ mix: Mix, rt60: Double, wet: Double, damp: Double = 0.35, predelay: Double = 0.016,
                tone: Double = 5200) -> ([Double], [Double]) {
        let n = mix.l.count
        var mono = [Double](repeating: 0, count: n)
        let pd = Int(predelay * sr)
        if pd < n { for i in pd..<n { mono[i] = 0.5 * (mix.l[i - pd] + mix.r[i - pd]) } }

        let combMs = [29.7, 37.1, 41.1, 43.7, 47.9, 52.3]
        var outs: [[Double]] = []
        for side in 0..<2 {
            var acc = [Double](repeating: 0, count: n)
            for (i, ms) in combMs.enumerated() {
                let d = Int(ms * 1e-3 * sr) + (side == 1 ? 23 : 0) + i * 3
                let g = pow(10, -3 * Double(d) / (sr * rt60))
                var lp = [Double](repeating: 0, count: n)
                for j in 0..<n {
                    let xin = j >= d ? mono[j - d] : 0
                    let fb = j >= d ? lp[j - d] : 0
                    let y = xin + g * fb
                    lp[j] = (1 - damp) * y + damp * (j > 0 ? lp[j - 1] : 0)
                    acc[j] += y
                }
            }
            for j in 0..<n { acc[j] /= Double(combMs.count) }
            for ms in [5.0, 1.7] {
                let d = Int(ms * 1e-3 * sr) + (side == 1 ? 7 : 0)
                let g = 0.5
                var y = [Double](repeating: 0, count: n)
                for j in 0..<n {
                    let xd = j >= d ? acc[j - d] : 0
                    let yd = j >= d ? y[j - d] : 0
                    y[j] = -g * acc[j] + xd + g * yd
                }
                acc = y
            }
            outs.append(lowpass1(acc, tone))
        }
        var l = mix.l, r = mix.r
        for j in 0..<n {
            l[j] += wet * outs[0][j] * 2.2
            r[j] += wet * outs[1][j] * 2.2
        }
        return (l, r)
    }

    /// Реверб → срез ниже 45 Гц → нормализация пика (запас до 0 dBFS, клиппинг невозможен) → фейды по краям.
    func master(_ mix: Mix, peak: Double, rt60: Double, wet: Double, fadeOut: Double,
                ceiling: Double? = nil, tone: Double = 5200, hp: Double = 45) -> RenderedSound {
        var (l, r) = reverb(mix, rt60: rt60, wet: wet, tone: tone)
        l = highpass(l, fc: hp)
        r = highpass(r, fc: hp)
        if let ceiling {                       // жёсткий потолок частот (4-й порядок): ничего «звенящего»
            l = lowpass2(lowpass2(l, fc: ceiling), fc: ceiling)
            r = lowpass2(lowpass2(r, fc: ceiling), fc: ceiling)
        }
        var m = 1e-9
        for v in l { m = max(m, abs(v)) }
        for v in r { m = max(m, abs(v)) }
        let g = peak / m
        let n = l.count
        for i in 0..<n { l[i] *= g; r[i] *= g }
        let ko = min(n, Int(fadeOut * sr))
        for i in 0..<ko {
            let f = 0.5 * (1 + cos(Double.pi * Double(i) / Double(ko)))
            l[n - ko + i] *= f
            r[n - ko + i] *= f
        }
        let ki = min(n, Int(0.002 * sr))
        for i in 0..<ki {
            let f = 0.5 * (1 - cos(Double.pi * Double(i) / Double(ki)))
            l[i] *= f
            r[i] *= f
        }
        return RenderedSound(left: l.map { Float($0) }, right: r.map { Float($0) })
    }

    // MARK: звуки — глубокое семейство
    //
    // ГЛАВНАЯ РУЧКА — `depth`. Это множитель высоты ВСЕХ звуков сразу (тела ударов, тоны, подложка, фильтры):
    //   1.0 — первая «звонкая» версия, 0.5 — на октаву ниже, 0.4 — ещё глубже (сейчас), 0.33 — совсем низ.
    // Слишком гулко/глухо — поднимай depth (0.45, 0.5…). Слишком высоко — опускай (0.35, 0.33…).
    // `level` — общая громкость (1.0 = как есть; если глубина кажется тихой — 1.2…1.4, пик ограничен 0.95).

    private let depth = 0.4
    private let level = 1.0

    private func d(_ f: Double) -> Double { f * depth }

    /// Основной тон + заметные 2-я и 3-я гармоники: на таких низах именно они делают звук слышимым и «объёмным».
    private let low: [(Double, Double, Double)] = [(1, 1, 1), (2, 0.45, 0.6), (3, 0.15, 0.4)]

    func deepMaster(_ b: Mix, peak: Double, rt60: Double, wet: Double, fadeOut: Double = 0.1) -> RenderedSound {
        master(b, peak: min(0.95, peak * level), rt60: rt60, wet: wet, fadeOut: fadeOut,
               ceiling: 300 + 600 * depth, tone: 200 + 300 * depth, hp: 20)
    }

    /// Старт: набор → глубокий удар двери + доводчик → низкий «гул салона» → выдох. Совпадает с SplashTime.
    func renderStartup() -> RenderedSound {
        var b = Mix(seconds: 5.6, sr: sr)             // с запасом: хвост доживает до тишины, а не обрубается
        b.add(pluck(d(Synth.D3), tau: 0.06, attack: 0.006, maxDur: 0.5, partials: low), at: 0.10, gain: 0.10)  // точка

        for (s, pan) in riser(dur: 1.0, fStart: d(Synth.D2), octaves: 1.0, fc0: d(140), fc1: d(520), harm: 8) { // 0.15 → 1.15
            b.add(s, at: 0.15, pan: pan, gain: 0.30)
        }
        let swell = air(dur: 0.95, fc0: d(60), fc1: d(330), q: 0.9) { p in
            pow(p, 2.2) * 0.5 * (1 + cos(Double.pi * min(max((p - 0.93) / 0.07, 0), 1)))
        }
        b.add(swell, at: 0.20, gain: 0.35)

        let T = 1.15                                   // сфера собрана — «закрылась дверь»
        b.add(thock(f0: d(130), f1: d(64), tau: 0.18, noiseFc: d(380), noiseAmt: 0.5, click: 0), at: T, gain: 1.0)
        b.add(pluck(36.71, tau: 0.5, attack: 0.01, maxDur: b.seconds - T,
                    partials: [(1, 1, 1), (2, 0.5, 0.7)]), at: T, gain: 0.55)                              // саб D1 (фиксированный)
        b.add(thock(f0: d(250), f1: d(185), tau: 0.02, noiseFc: d(500), noiseAmt: 0.25, click: 0), at: T + 0.09, gain: 0.28) // защёлка
        b.add(sweep(dur: 0.2, f0: d(70), f1: d(115)) { p in pow(sin(Double.pi * p), 2) }, at: T + 0.12, gain: 0.14)         // тяга
        b.add(pad([d(Synth.D2), d(Synth.A2), d(Synth.D3), d(Synth.A3)], dur: 4.2, attack: 0.5, tau: 1.1, h2: 0.4),
              at: T, gain: 0.55)

        let exhale = air(dur: 0.55, fc0: d(420), fc1: d(120), q: 0.8) { p in pow(sin(Double.pi * p), 1.5) }
        b.add(exhale, at: 3.05, gain: 0.16)            // выдох на уходе сплэша

        return deepMaster(b, peak: 1.0, rt60: 1.8, wet: 0.30, fadeOut: 1.4)
    }

    func render(_ cue: SoundEngine.Cue) -> RenderedSound {
        switch cue {
        case .start:      // начало записи: мягкое касание + восходящая квинта
            var b = Mix(seconds: 0.9, sr: sr)
            b.add(thock(f0: d(150), f1: d(100), tau: 0.07, noiseFc: d(420), noiseAmt: 0.25, click: 0), at: 0, gain: 0.8)
            note(&b, d(Synth.D3), at: 0.0, tau: 0.25, attack: 0.006, pan: -0.1, gain: 0.40, partials: low)
            note(&b, d(Synth.A3), at: 0.08, tau: 0.30, attack: 0.006, pan: 0.1, gain: 0.42, partials: low)
            return deepMaster(b, peak: 0.50, rt60: 0.7, wet: 0.14)

        case .stop:       // конец записи: «закрытие» — нисходящая квинта
            var b = Mix(seconds: 1.0, sr: sr)
            b.add(thock(f0: d(130), f1: d(80), tau: 0.09, noiseFc: d(380), noiseAmt: 0.30, click: 0), at: 0, gain: 0.9)
            note(&b, d(Synth.A3), at: 0.0, tau: 0.18, attack: 0.006, pan: 0.1, gain: 0.34, partials: low)
            note(&b, d(Synth.D3), at: 0.08, tau: 0.40, attack: 0.006, pan: -0.1, gain: 0.46, partials: low)
            return deepMaster(b, peak: 0.50, rt60: 0.8, wet: 0.16)

        case .success:    // текст готов: быстрое низкое арпеджио с длинным мягким затуханием
            // Ноты чуть ниже общей высоты (×0.89 ≈ на 2 полутона). Арпеджио по-прежнему быстрое (0 / 0.09 / 0.19 с),
            // а хвост доживает до конца: буфер 2.4 с и плавный фейд 0.6 с — звук больше не обрывается.
            let drop = 0.89
            var b = Mix(seconds: 2.4, sr: sr)
            b.add(thock(f0: d(160) * drop, f1: d(105) * drop, tau: 0.05, noiseFc: d(420), noiseAmt: 0.25, click: 0), at: 0, gain: 0.5)
            note(&b, d(Synth.D3) * drop, at: 0.00, tau: 0.65, attack: 0.006, pan: -0.15, gain: 0.40, partials: low)
            note(&b, d(Synth.A3) * drop, at: 0.09, tau: 0.70, attack: 0.006, pan: 0.15, gain: 0.38, partials: low)
            note(&b, d(Synth.D4) * drop, at: 0.19, tau: 0.95, attack: 0.006, gain: 0.26, partials: low)
            return deepMaster(b, peak: 0.45, rt60: 1.5, wet: 0.22, fadeOut: 0.6)

        case .cancel:     // отмена: глухой удар + короткое нисходящее «оседание»
            var b = Mix(seconds: 0.7, sr: sr)
            b.add(thock(f0: d(125), f1: d(70), tau: 0.07, noiseFc: d(350), noiseAmt: 0.35, click: 0), at: 0, gain: 0.9)
            b.add(sweep(dur: 0.18, f0: d(150), f1: d(80)) { p in pow(sin(Double.pi * p), 1.2) }, at: 0, gain: 0.20)
            return deepMaster(b, peak: 0.50, rt60: 0.5, wet: 0.10, fadeOut: 0.08)

        case .copy:       // копирование: микро-касание
            var b = Mix(seconds: 0.5, sr: sr)
            b.add(thock(f0: d(210), f1: d(160), tau: 0.02, noiseFc: d(500), noiseAmt: 0.20, click: 0), at: 0, gain: 0.6)
            note(&b, d(Synth.D3), at: 0.0, tau: 0.06, attack: 0.003, gain: 0.35, partials: low)
            return deepMaster(b, peak: 0.42, rt60: 0.4, wet: 0.08, fadeOut: 0.06)

        case .delete:     // удаление: глубокий удар + низкий выдох
            var b = Mix(seconds: 0.7, sr: sr)
            b.add(thock(f0: d(150), f1: d(80), tau: 0.10, noiseFc: d(350), noiseAmt: 0.45, click: 0), at: 0, gain: 0.9)
            b.add(air(dur: 0.22, fc0: d(420), fc1: d(110), q: 1.0) { p in pow(sin(Double.pi * p), 1.2) }, at: 0, gain: 0.22)
            return deepMaster(b, peak: 0.55, rt60: 0.5, wet: 0.10, fadeOut: 0.08)

        case .warning:    // предупреждение: два глухих удара
            var b = Mix(seconds: 0.9, sr: sr)
            b.add(thock(f0: d(135), f1: d(85), tau: 0.06, noiseFc: d(380), noiseAmt: 0.30, click: 0), at: 0, gain: 0.8)
            note(&b, d(Synth.D3), at: 0.0, tau: 0.12, attack: 0.004, pan: -0.2, gain: 0.35, partials: low)
            b.add(thock(f0: d(125), f1: d(78), tau: 0.06, noiseFc: d(380), noiseAmt: 0.30, click: 0), at: 0.12, gain: 0.8)
            note(&b, d(Synth.A2), at: 0.12, tau: 0.16, attack: 0.004, pan: 0.2, gain: 0.40, partials: low)
            return deepMaster(b, peak: 0.50, rt60: 0.6, wet: 0.12, fadeOut: 0.10)
        }
    }
}
