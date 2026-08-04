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
                // ШАПКА
                VStack(spacing: 8) {
                    Text("Давайте начнём")
                        .font(UIStyleFont.display(size: 22, weight: .semibold))
                        .foregroundColor(.uiInk)
                    
                    Text("Разрешите доступ к микрофону для записи речи. Остальные опции можно настроить позже.")
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420)
                
                // КАРТОЧКА НАСТРОЕК
                UICard {
                    VStack(spacing: 18) {
                        // ШАГ 1: Микрофон (Обязательно)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isMicGranted ? Color(hex: "#10B981") : Color.uiWarn)
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Доступ к микрофону")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("Требуется")
                                        .font(UIStyleFont.body(size: 10, weight: .bold))
                                        .foregroundColor(.uiWarn)
                                }
                                Text("Запись голоса для распознавания моделью")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isMicGranted {
                                UIBadge(text: "Готово")
                            } else {
                                UIPrimaryButton(title: "Разрешить") {
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
                                    Text("Вставка под курсор")
                                        .font(UIStyleFont.display(size: 14, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    Text("Опционально")
                                        .font(UIStyleFont.body(size: 10, weight: .regular))
                                        .foregroundColor(.uiMidGray)
                                }
                                Text("Мгновенная вставка распознанного текста в активное окно")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isAccessibilityGranted {
                                UIBadge(text: "Готово")
                            } else {
                                UIOutlineButton(title: "Включить") {
                                    permissions.requestAccessibilityPermission()
                                }
                            }
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        // ШАГ 3: Анонимная аналитика
                        HStack(spacing: 16) {
                            Circle()
                                .fill(audioCapture.analyticsEnabled ? Color(hex: "#10B981") : Color.uiMidGray.opacity(0.4))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Делиться аналитикой")
                                    .font(UIStyleFont.display(size: 14, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Автоматическая отправка данных диагностики поможет совершенствовать продукт")
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
                
                UIPrimaryButton(title: canContinue ? "Начать использование" : "Требуется доступ к микрофону") {
                    if canContinue {
                        permissions.completeOnboarding()
                        isPresented = false
                    }
                }
                .disabled(!canContinue)
                .opacity(canContinue ? 1.0 : 0.4)
                
                Text("Design & Development by Kozak • 2026")
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
                    .padding(.top, 4)
            }
            .padding(40)
        }
        .onReceive(timer) { _ in
            permissions.checkPermissions()
        }
    }
}
