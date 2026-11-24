import SwiftUI
import AppKit

// MARK: - Секция «ИИ-провайдер»

struct AIProviderSection: View {
    @ObservedObject var store = AIProviderStore.shared
    @ObservedObject var account = AccountStore.shared

    private var byoPresets: [AIProviderPreset] {
        AIProviderPresets.all.filter { !$0.isProxy }
    }
    private var proxyPreset: AIProviderPreset? {
        AIProviderPresets.all.first { $0.isProxy }
    }
    private var isProxySelected: Bool {
        store.currentPreset?.isProxy == true
    }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 16) {
                Text("ИИ-ПРОВАЙДЕР")
                    .font(UIStyleFont.body(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.uiMidGray)

                Text(LocalizedStringKey("BYO-ключ. Транскрипция уходит напрямую в ваш OpenAI-совместимый сервис — Голосок не выступает оператором данных."))
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(byoPresets) { preset in
                        PresetChip(preset: preset, isSelected: store.providerID == preset.id) {
                            store.apply(preset)
                        }
                    }
                }

                if let proxy = proxyPreset {
                    proxyCard(proxy)
                }

                if isProxySelected {
                    Text(LocalizedStringKey("Авторизуйтесь на сайте, скопируйте токен авторизации и вставьте его в раздел Аккаунт ниже для активации. Запросы отправляются через наш сервер."))
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.uiMidGray)
                        Text("Модель выбирается на сайте — по подписке.")
                            .font(UIStyleFont.body(size: 12, weight: .regular))
                            .foregroundColor(.uiMidGray)
                    }
                } else if store.providerID == AppleLocalAI.presetID {
                    appleLocalBlock
                } else {
                    AIInputField(title: "Base URL", text: $store.baseURL, placeholder: "https://api.openai.com/v1")
                    AIInputField(title: "API-ключ", text: $store.apiKey, placeholder: "sk-…", isSecure: true)

                    if store.providerID == "ollama" {
                        ollamaModelField
                    } else {
                        AIInputField(title: "Модель", text: $store.model, placeholder: "gpt-4o-mini")
                    }

                    HStack(spacing: 10) {
                        UIOutlineButton(title: "Проверить") {
                            store.testConnection()
                        }
                        .disabled(store.isTesting)

                        if store.isTesting {
                            ProgressView().controlSize(.small)
                        }

                        if let result = store.testResult {
                            Text(result)
                                .font(UIStyleFont.body(size: 12, weight: .medium))
                                .foregroundColor(store.testOK ? Color(hex: "#10B981") : .uiEmber)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func proxyCard(_ proxy: AIProviderPreset) -> some View {
        let isSelected = store.providerID == proxy.id
        let accent = Color(hex: "#10B981")
        return Button(action: {
            if account.isConnected { store.apply(proxy) }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.uiPaper.opacity(0.18) : accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? Color.uiPaper : accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(proxy.name))
                            .font(UIStyleFont.body(size: 13, weight: .semibold))
                            .foregroundColor(isSelected ? .uiPaper : .uiInk)
                        Text(LocalizedStringKey("Облако"))
                            .font(UIStyleFont.body(size: 9, weight: .bold))
                            .foregroundColor(isSelected ? Color.uiPaper : accent)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(isSelected ? Color.uiPaper.opacity(0.15) : accent.opacity(0.14))
                            .cornerRadius(10)
                    }
                    Text(proxy.hint)
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(isSelected ? Color.uiPaper.opacity(0.72) : .uiMidGray)
                }
                Spacer()
                if !account.isConnected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.uiMidGray)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.uiPaper)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.uiMidGray)
                }
            }
            .padding(14)
            .background(isSelected ? Color.uiInk : accent.opacity(0.06))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.uiInk : accent.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
    }

    private var appleLocalBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: AppleLocalAI.isSupported ? "cpu.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppleLocalAI.isSupported ? Color(hex: "#10B981") : .uiEmber)
                Text(AppleLocalAI.status().title)
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiInk)
            }
            Text(LocalizedStringKey("Текст расшифровки обрабатывается системной моделью Apple прямо на устройстве: без сервера, без API-ключа и без скачивания весов. Работает не на всех Mac и только при включённом Apple Intelligence с английским языком Siri. Качество ниже облачных моделей, зато данные не покидают Mac."))
                .font(UIStyleFont.body(size: 11, weight: .regular))
                .foregroundColor(.uiMidGray)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                UIOutlineButton(title: "Проверить") {
                    store.testConnection()
                }
                .disabled(store.isTesting)

                if store.isTesting {
                    ProgressView().controlSize(.small)
                }

                if let result = store.testResult {
                    Text(result)
                        .font(UIStyleFont.body(size: 12, weight: .medium))
                        .foregroundColor(store.testOK ? Color(hex: "#10B981") : .uiEmber)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var ollamaModelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Модель")
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            HStack(spacing: 8) {
                UIDropdownPicker(selection: $store.model, options: {
                    var arr: [UIDropdownOption<String>] = []
                    if !store.model.isEmpty && !store.installedModels.contains(store.model) {
                        arr.append(.init(store.model, value: store.model))
                    }
                    arr.append(contentsOf: store.installedModels.map { .init($0, value: $0) })
                    return arr
                }(), fullWidth: true)

                Button(action: { store.refreshModels() }) {
                    if store.isLoadingModels {
                        ProgressView().controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.uiInk)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(TactileButtonStyle())
                .background(Color.uiPaper)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.uiHairline, lineWidth: 1))
                .help(String(localized: "Обновить список моделей"))
            }
            if store.installedModels.isEmpty && !store.isLoadingModels {
                Text("Нет скачанных моделей — запустите Ollama и нажмите ↻")
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if store.installedModels.isEmpty && !store.isLoadingModels {
                store.refreshModels()
            }
        }
    }
}

struct PresetChip: View {
    let preset: AIProviderPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? Color.uiPaper : Color.uiMidGray)
                    .frame(width: 6, height: 6)
                Text(LocalizedStringKey(preset.name))
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .uiPaper : .uiInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.uiInk : Color.uiPaper)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.uiInk : Color.uiHairline, lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
    }
}

struct AIInputField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(PlainTextFieldStyle())
            .font(UIStyleFont.body(size: 13, weight: .regular))
            .foregroundColor(.uiInk)
            .padding(8)
            .background(Color.uiCanvas)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
        }
    }
}

// MARK: - Секция «Аккаунт»

struct AccountSection: View {
    @ObservedObject var store = AccountStore.shared
    @State private var tokenInput = ""
    @State private var heroHover = false
    @State private var burstID = 0
    @State private var confirmSignOut = false
    @FocusState private var fieldFocused: Bool

    private let green = Color(hex: "#10B981")

    private var isVerifying: Bool {
        if case .verifying = store.status { return true }
        return false
    }

    private var showsInput: Bool {
        switch store.status {
        case .notConnected, .invalid: return true
        case .connected, .verifying: return false
        }
    }

    private var accent: Color {
        if case .invalid = store.status { return Color.uiEmber }
        return green
    }

    private var orbMode: AccountOrb.Mode {
        switch store.status {
        case .notConnected: return .off
        case .verifying: return .verifying
        case .connected: return .on
        case .invalid: return .failed
        }
    }

    private var statusKey: String {
        switch store.status {
        case .notConnected: return "off"
        case .verifying: return "verifying"
        case .connected: return "on"
        case .invalid: return "failed"
        }
    }

    private var tokenIsEmpty: Bool {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 16) {
                header
                hero
                if showsInput {
                    inputRow
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if store.isConnected {
                    connectedActions
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.status)
        }
        .onChange(of: store.isConnected) { old, new in
            if new && !old { burstID += 1 }
        }
    }

    // MARK: Части

    private var header: some View {
        HStack {
            Text("АККАУНТ")
                .font(UIStyleFont.body(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.uiMidGray)
            Spacer()
            if store.isConnected {
                tierBadge
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }

    private var hero: some View {
        Button {
            NSWorkspace.shared.open(store.isConnected ? AccountStore.cloudURL : AccountStore.loginURL)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    AccountOrb(mode: orbMode, accent: accent)
                        .frame(width: 54, height: 54)
                    if burstID > 0 {
                        AccountBurstRing(color: green).id(burstID)
                    }
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(statusTitle))
                        .font(UIStyleFont.display(size: 17, weight: .semibold))
                        .foregroundColor(.uiInk)
                    if let detail = statusDetail {
                        Text(detail)
                            .font(UIStyleFont.body(size: 12, weight: .regular))
                            .foregroundColor(.uiMidGray)
                            .lineLimit(2)
                    }
                    if store.isConnected, !store.tokenHint.isEmpty {
                        Text(store.tokenHint)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.uiMidGray.opacity(0.8))
                    }
                }
                .id(statusKey)
                .transition(.opacity.combined(with: .offset(y: 4)))

                Spacer(minLength: 8)

                if !isVerifying {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(heroHover ? Color.dynamic(light: "#ffffff", dark: "#000000") : .uiMidGray)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(heroHover ? accent : Color.uiHairline.opacity(0.6)))
                        .offset(x: heroHover ? 1.5 : 0, y: heroHover ? -1.5 : 0)
                        .transition(.opacity)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.uiCanvas.opacity(heroHover ? 0.9 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.opacity(heroHover ? 0.45 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(AccountHeroButtonStyle())
        .animation(.easeOut(duration: 0.18), value: heroHover)
        .onHover { inside in
            heroHover = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if heroHover { NSCursor.pop(); heroHover = false }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                SecureField("gls_…", text: $tokenInput)
                    .textFieldStyle(.plain)
                    .font(UIStyleFont.body(size: 13, weight: .regular))
                    .foregroundColor(.uiInk)
                    .focused($fieldFocused)
                    .onSubmit { connect() }

                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        tokenInput = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(.uiMidGray)
                }
                .buttonStyle(.plain)
                .help("Вставить из буфера")
            }
            .padding(10)
            .background(Color.uiCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(fieldFocused ? accent.opacity(0.75) : Color.uiHairline,
                            lineWidth: fieldFocused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.18), value: fieldFocused)

            UIPrimaryButton(title: "Подключить") { connect() }
                .disabled(tokenIsEmpty)
                .opacity(tokenIsEmpty ? 0.45 : 1)
                .animation(.easeOut(duration: 0.15), value: tokenIsEmpty)
        }
    }

    private var connectedActions: some View {
        HStack(spacing: 8) {
            UIPrimaryButton(title: "Открыть облако ↗") {
                NSWorkspace.shared.open(AccountStore.cloudURL)
            }
            UIOutlineButton(title: "Проверить") { store.verify() }
            Spacer()
            UIOutlineButton(title: confirmSignOut ? "Точно отключить?" : "Отключить") {
                handleSignOut()
            }
        }
    }

    private var tierBadge: some View {
        Text(store.tierName)
            .font(UIStyleFont.body(size: 10, weight: .bold))
            .foregroundColor(green)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(green.opacity(0.12))
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(green.opacity(0.25), lineWidth: 1))
    }

    // MARK: Логика

    private func connect() {
        guard !tokenIsEmpty else { return }
        store.save(token: tokenInput)
        tokenInput = ""
        fieldFocused = false
    }

    private func handleSignOut() {
        if confirmSignOut {
            confirmSignOut = false
            store.signOut()
            return
        }
        confirmSignOut = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            confirmSignOut = false
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    private var statusTitle: String {
        switch store.status {
        case .notConnected: return "Не подключён"
        case .verifying: return "Проверка токена…"
        case .connected: return store.subscription == "echo" ? "Голосок+" : "Базовый"
        case .invalid: return "Токен не принят"
        }
    }

    private var statusDetail: String? {
        switch store.status {
        case .notConnected:
            return String(localized: "Войдите на сайте и вставьте токен приложения")
        case .verifying:
            return nil
        case .connected(let sub, let expiresAt):
            // Дату показываем только для платной подписки и только если она реально в будущем.
            guard sub == "echo", let expiresAt, expiresAt.timeIntervalSinceNow > 36 * 3600 else {
                return String(localized: "Подписка активна")
            }
            let days = Int(expiresAt.timeIntervalSinceNow / 86_400)
            return String(localized: "До") + " " + Self.dateFormatter.string(from: expiresAt)
                + " · \(days) " + String(localized: "дн.")
        case .invalid(let message):
            return message
        }
    }
}

private struct AccountHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Вспышка при подключении

private struct AccountBurstRing: View {
    let color: Color
    @State private var go = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.55), lineWidth: 1.5)
            .frame(width: 30, height: 30)
            .scaleEffect(go ? 2.4 : 0.6)
            .opacity(go ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.8)) { go = true } }
    }
}

// MARK: - Орб аккаунта

private final class AccountOrbDriver {
    var size = 0.0    // 0 — точка, 1 — полная сфера
    var on = 0.0      // 0 — нейтральный цвет, 1 — акцентный
    var spin = 0.35
    var yaw = 0.0
    private var last = 0.0

    func step(now: Double, mode: AccountOrb.Mode, calm: Bool) {
        let dt = min(max(now - last, 0), 0.1)
        last = now
        let targetSize: Double
        switch mode {
        case .off: targetSize = 0
        case .failed: targetSize = 0.55
        case .verifying, .on: targetSize = 1
        }
        size += (targetSize - size) * (1 - exp(-5 * dt))
        on += ((mode == .off ? 0 : 1) - on) * (1 - exp(-6 * dt))
        spin += ((mode == .verifying ? 2.2 : 0.35) - spin) * (1 - exp(-3 * dt))
        if !calm { yaw += dt * spin }
    }
}

struct AccountOrb: View {
    enum Mode { case off, verifying, on, failed }

    let mode: Mode
    let accent: Color

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver = AccountOrbDriver()
    @State private var born = Date()

    private static let points: [(x: Double, y: Double, z: Double)] = {
        let n = 150
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let r = (1 - y * y).squareRoot()
            let a = golden * Double(i)
            return (x: cos(a) * r, y: y, z: sin(a) * r)
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = max(timeline.date.timeIntervalSince(born), 0)
                driver.step(now: t, mode: mode, calm: reduceMotion)
                Self.draw(&ctx, size: size, t: reduceMotion ? 0 : t, d: driver,
                          ink: scheme == .dark ? .white : Color(white: 0.1), accent: accent)
            }
        }
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                             d: AccountOrbDriver, ink: Color, accent: Color) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = Double(min(size.width, size.height)) * 0.36
        let breathe = 1 + 0.04 * d.on * sin(t * 1.6)
        let R = base * (0.12 + 0.88 * d.size) * breathe

        // Мягкое свечение вокруг подключённого орба.
        if d.on > 0.02 {
            let r = base * 1.45
            let g = Gradient(colors: [accent.opacity(0.30 * d.on), accent.opacity(0)])
            ctx.fill(Path(ellipseIn: CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(g, center: c, startRadius: 0, endRadius: r))
        }

        let verify = min(max((d.spin - 0.35) / 1.85, 0), 1)
        let amp = 0.05 + 0.10 * verify
        let sweep = sin(t * 2.4)
        let cp = cos(0.38), sp = sin(0.38)
        let ca = cos(d.yaw), sa = sin(d.yaw)

        var layers = [Path](repeating: Path(), count: 3)
        for p in points {
            let n = sin(p.x * 3.0 + t * 1.1) * cos(p.y * 2.5 - t * 0.9)
            let band = verify > 0.01 ? verify * exp(-pow((p.y - sweep) / 0.25, 2)) : 0
            let rad = 1 + amp * n + 0.15 * band
            let x = p.x * rad, y = p.y * rad, z = p.z * rad
            let x1 = x * ca + z * sa
            let z1 = -x * sa + z * ca
            let y2 = y * cp - z1 * sp
            let z2 = y * sp + z1 * cp
            let depth = min(max((z2 / rad + 1) / 2, 0), 1)
            let persp = 1 + 0.15 * z2
            let px = Double(c.x) + x1 * R * persp
            let py = Double(c.y) + y2 * R * persp
            let dia = (1.0 + 1.2 * depth) * (0.55 + 0.45 * d.size) * (1 + 0.8 * band)
            layers[min(2, Int(depth * 3))]
                .addEllipse(in: CGRect(x: px - dia / 2, y: py - dia / 2, width: dia, height: dia))
        }

        let alphas = [0.28, 0.6, 0.95]
        for i in 0..<3 {
            ctx.fill(layers[i], with: .color(ink.opacity(alphas[i] * (1 - d.on))))
            ctx.fill(layers[i], with: .color(accent.opacity(alphas[i] * d.on)))
        }
    }
}

// MARK: - Пульсирующий индикатор

struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Circle()
                .stroke(color.opacity(0.6), lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 2.4 : 1.0)
                .opacity(pulse ? 0 : 0.9)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
