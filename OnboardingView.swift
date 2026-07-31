import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var audioCapture = AudioCapture.shared
    @Binding var isPresented: Bool
    
    var canContinue: Bool {
        return permissions.isMicGranted
    }
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Настройка Голоска")
                        .font(UIStyleFont.display(size: 22, weight: .semibold))
                        .foregroundColor(.uiInk)
                    
                    Text("Для работы распознавания речи требуется микрофон. Остальные параметры можно настроить по желанию.")
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                
                UICard {
                    VStack(spacing: 18) {
                        // ШАГ 1: Микрофон (Обязательно)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isMicGranted ? Color(hex: "#10B981") : Color.uiEmber)
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Доступ к микрофону")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("Обязательно")
                                        .font(UIStyleFont.body(size: 10, weight: .bold))
                                        .foregroundColor(.uiEmber)
                                }
                                Text("Запись голоса для нейросети GigaAM v3")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isMicGranted {
                                UIBadge(text: "Готово")
                            } else {
                                UIPrimaryButton(title: "Включить") {
                                    permissions.requestMicPermission()
                                }
                            }
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        // ШАГ 2: Авто-вставка (По желанию)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isAccessibilityGranted ? Color(hex: "#10B981") : Color.uiMidGray.opacity(0.4))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Автоматическая вставка")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("По желанию")
                                        .font(UIStyleFont.body(size: 10, weight: .regular))
                                        .foregroundColor(.uiMidGray)
                                }
                                Text("Эмуляция Cmd+V в место курсора")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isAccessibilityGranted {
                                UIBadge(text: "Готово")
                            } else {
                                UIOutlineButton(title: "Открыть настройки") {
                                    permissions.requestAccessibilityPermission()
                                }
                            }
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        // ШАГ 3: Анонимная аналитика (Включена по умолчанию)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(audioCapture.analyticsEnabled ? Color(hex: "#10B981") : Color.uiMidGray.opacity(0.4))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Анонимная аналитика")
                                    .font(UIStyleFont.display(size: 14, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Отправка обезличенной статистики запускa")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $audioCapture.analyticsEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                    }
                }
                .frame(maxWidth: 480)
                
                UIPrimaryButton(title: canContinue ? "Начать использование" : "Сначала включите микрофон") {
                    if canContinue {
                        permissions.completeOnboarding()
                        isPresented = false
                    }
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1.0 : 0.4)
            }
            .padding(40)
        }
        .onReceive(timer) { _ in
            permissions.checkPermissions()
        }
    }
}
