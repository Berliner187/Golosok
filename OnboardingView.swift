import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions = PermissionManager.shared
    @Binding var isPresented: Bool
    
    var canContinue: Bool {
        return permissions.isMicGranted
    }
    
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Заголовок
                VStack(spacing: 8) {
                    Text("Настройка Голоска")
                        .font(UIStyleFont.display(size: 22, weight: .semibold))
                        .foregroundColor(.uiInk)
                    
                    Text("Для работы распознавания речи требуется микрофон. Автоматическая вставка текста настраивается опционально.")
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                
                // Карточка разрешений
                UICard {
                    VStack(spacing: 20) {
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
                                Text("Запись голоса для работы расшифровок")
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
                        
                        // ШАГ 2: Автовставка
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isAccessibilityGranted ? Color(hex: "#10B981") : Color.uiMidGray.opacity(0.4))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Автовставка")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("Опционально")
                                        .font(UIStyleFont.body(size: 10, weight: .regular))
                                        .foregroundColor(.uiMidGray)
                                }
                                Text("Автовставка текста в поле ввода")
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
