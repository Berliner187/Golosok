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
                    Text(LocalizedStringKey(proxy.hint))
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

    private var ollamaModelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Модель")
                .font(UIStyleFont.body(size: 11, weight: .medium))
                .foregroundColor(.uiMidGray)
            HStack(spacing: 8) {
                if store.installedModels.isEmpty {
                    TextField("llama3.2", text: $store.model)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiInk)
                        .padding(8)
                        .background(Color.uiCanvas)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
                } else {
                    Picker("", selection: $store.model) {
                        if !store.model.isEmpty && !store.installedModels.contains(store.model) {
                            Text(store.model).tag(store.model)
                        }
                        ForEach(store.installedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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
    let title: String
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

    private var isVerifying: Bool {
        if case .verifying = store.status { return true }
        return false
    }

    private var showsInput: Bool {
        switch store.status {
        case .connected: return false
        case .notConnected, .invalid, .verifying: return true
        }
    }

    var body: some View {
        UICard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("АККАУНТ")
                        .font(UIStyleFont.body(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.uiMidGray)
                    Spacer()
                    if store.isConnected {
                        tierBadge
                    }
                }

                HStack(spacing: 12) {
                    indicator

                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(statusTitle))
                            .font(UIStyleFont.body(size: 13, weight: .medium))
                            .foregroundColor(.uiInk)
                        if let detail = statusDetail {
                            Text(detail)
                                .font(UIStyleFont.body(size: 11, weight: .regular))
                                .foregroundColor(.uiMidGray)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    trailingButtons
                }

                if showsInput {
                    HStack(spacing: 8) {
                        SecureField("gls_…", text: $tokenInput)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(UIStyleFont.body(size: 13, weight: .regular))
                            .foregroundColor(.uiInk)
                            .padding(8)
                            .background(Color.uiCanvas)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))

                        UIPrimaryButton(title: "Подключить") {
                            store.save(token: tokenInput)
                            tokenInput = ""
                        }
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .disabled(isVerifying)
                    .opacity(isVerifying ? 0.6 : 1)
                }

                AccountProgressBar()
                    .frame(height: 4)
                    .opacity(isVerifying ? 1 : 0)

                if case .notConnected = store.status {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.uiMidGray)
                            .padding(.top, 1)
                        Text(String(localized: "Подключите аккаунт, чтобы использовать облачный ИИ «Голосок+» без собственного API-ключа."))
                            .font(UIStyleFont.body(size: 11, weight: .regular))
                            .foregroundColor(.uiMidGray)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: store.status)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch store.status {
        case .verifying:
            PulsingDot(color: Color(hex: "#10B981"))
        case .connected:
            Circle()
                .fill(Color(hex: "#10B981"))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: "#10B981").opacity(0.7), radius: 3, x: 0, y: 0)
        case .invalid:
            Circle().fill(Color.uiEmber).frame(width: 8, height: 8)
        case .notConnected:
            Circle().fill(Color.uiMidGray).frame(width: 8, height: 8)
        }
    }

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
        case .connected(_, let expiresAt):
            guard let expiresAt else { return String(localized: "Подписка активна") }
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMMM yyyy"
            return String(localized: "До") + " " + formatter.string(from: expiresAt)
        case .invalid(let message):
            return message
        }
    }

    private var tierBadge: some View {
        Text(store.tierName)
            .font(UIStyleFont.body(size: 10, weight: .bold))
            .foregroundColor(Color(hex: "#10B981"))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color(hex: "#10B981").opacity(0.12))
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#10B981").opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var trailingButtons: some View {
        switch store.status {
        case .connected:
            HStack(spacing: 8) {
                UIOutlineButton(title: "Проверить") { store.verify() }
                UIOutlineButton(title: "Отключить") { store.signOut() }
            }
        case .notConnected, .invalid:
            UIOutlineButton(title: "Войти на сайте") {
                NSWorkspace.shared.open(AccountStore.loginURL)
            }
        case .verifying:
            EmptyView()
        }
    }
}

// MARK: - Анимированный прогресс-бар проверки токена

struct AccountProgressBar: View {
    @State private var fill: CGFloat = 0
    private let accent = Color(hex: "#10B981")

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(accent.opacity(0.12))

                Capsule()
                    .fill(LinearGradient(
                        colors: [accent.opacity(0.35), accent, accent.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing))
                    .frame(width: max(geo.size.width * fill, 6))
                    .shadow(color: accent.opacity(0.5), radius: 2, x: 0, y: 0)
            }
            .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                fill = 1
            }
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
