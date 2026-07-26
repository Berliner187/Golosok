import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions = PermissionManager.shared
    @Binding var isPresented: Bool
    
    // Таймер, который проверяет тумблеры в настройках macOS каждые 0.5 сек
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
                    
                    Text("Для работы фоновой диктовки и автоматической вставки необходимо выдать два системных разрешения.")
                        .font(UIStyleFont.body(size: 13, weight: .regular))
                        .foregroundColor(.uiMidGray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 400)
                
                // Карточка с шагами
                UICard {
                    VStack(spacing: 20) {
                        // ШАГ 1: Микрофон
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isMicGranted ? Color(hex: "#10B981") : Color.uiMidGray.opacity(0.3))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Доступ к микрофону")
                                    .font(UIStyleFont.display(size: 14, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Требуется для записи и обработки голоса")
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
                        
                        // ШАГ 2: Вставка (Accessibility)
                        HStack(spacing: 16) {
                            Circle()
                                .fill(permissions.isAccessibilityGranted ? Color(hex: "#10B981") : Color.uiMidGray.opacity(0.3))
                                .frame(width: 10, height: 10)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Универсальный доступ")
                                    .font(UIStyleFont.display(size: 14, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Требуется для эмуляции нажатия Cmd + V")
                                    .font(UIStyleFont.body(size: 12, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            
                            Spacer()
                            
                            if permissions.isAccessibilityGranted {
                                UIBadge(text: "Готово")
                            } else {
                                UIOutlineButton(title: "Настройки") {
                                    permissions.requestAccessibilityPermission()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 480)
                
                // Кнопка продолжить
                UIPrimaryButton(title: "Начать использование") {
                    if permissions.isAllGranted {
                        isPresented = false
                    }
                }
                .disabled(!permissions.isAllGranted)
                .opacity(permissions.isAllGranted ? 1.0 : 0.4)
            }
            .padding(40)
        }
        .onReceive(timer) { _ in
            permissions.checkPermissions()
        }
    }
}
