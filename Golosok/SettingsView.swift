import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var permissions = PermissionManager.shared
    @State private var showingClearHistoryAlert = false
    @State private var showingAboutSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // РАЗДЕЛ 1: ОСНОВНЫЕ
                UICard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ОСНОВНЫЕ")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.uiMidGray)
                        
                        // 1. Автозапуск
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Запуск при входе")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Автоматически открывать в строке меню")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            Toggle("", isOn: $audioCapture.launchAtLoginEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        // 2. Авто-вставка
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Авто-вставка текста")
                                        .font(UIStyleFont.body(size: 13, weight: .medium))
                                        .foregroundColor(.uiInk)
                                    
                                    if !permissions.isAccessibilityGranted {
                                        Text("Разрешите доступ")
                                            .font(UIStyleFont.body(size: 10, weight: .bold))
                                            .foregroundColor(.uiWarn)
                                    }
                                }
                                
                                Text(permissions.isAccessibilityGranted ?
                                     "Печатать расшифровку прямо в место курсора" :
                                     "Выдайте доступ в Универсальном доступе macOS")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            
                            if permissions.isAccessibilityGranted {
                                Toggle("", isOn: $audioCapture.autoPasteEnabled)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                            } else {
                                UIOutlineButton(title: "Настройки") {
                                    permissions.requestAccessibilityPermission()
                                }
                            }
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Сразу открывать в истории")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Автоматически открывать свежую заметку по завершении расшифровки")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            Toggle("", isOn: $audioCapture.autoOpenNoteEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Делиться аналитикой")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Автоматическая отправка анонимных метрик производительности")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            Toggle("", isOn: $audioCapture.analyticsEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        // 4. Звуки
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Системные звуки")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Акустический отклик при активации, копировании и ошибках")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            Toggle("", isOn: $audioCapture.soundEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                    }
                }
                
                // РАЗДЕЛ 2: УПРАВЛЕНИЕ
                UICard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("УПРАВЛЕНИЕ")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.uiMidGray)
                        
                        HStack {
                            Text("Диктовка (Старт / Стоп)")
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Spacer()
                            UIBadge(text: "⌥ + ПРОБЕЛ")
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        HStack {
                            Text("Отмена записи")
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Spacer()
                            UIBadge(text: "ESC")
                        }
                    }
                }
                
                // РАЗДЕЛ 3: ДВИЖОК
                UICard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("ДВИЖОК И УСКОРЕНИЕ")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.uiMidGray)
                        
                        HStack {
                            Text("Языковая модель")
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Spacer()
                            Text("Sber GigaAM v3 (E2E-RNNT)")
                                .font(UIStyleFont.body(size: 12, weight: .regular))
                                .foregroundColor(.uiMidGray)
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        HStack {
                            Text("Аппаратное ускорение")
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Spacer()
                            Text("Apple Metal (MTL0)")
                                .font(UIStyleFont.body(size: 12, weight: .regular))
                                .foregroundColor(.uiMidGray)
                        }
                        
                        Divider().background(Color.uiHairline)

                        HStack {
                            Text("О программе Golosok")
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Spacer()
                            UIOutlineButton(title: "Открыть") {
                                showingAboutSheet = true
                            }
                        }
                        .sheet(isPresented: $showingAboutSheet) {
                            AboutView()
                        }
                    }
                }
                
                // РАЗДЕЛ 4: ДАННЫЕ
                UICard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Стереть историю")
                                .font(UIStyleFont.body(size: 13, weight: .bold))
                                .foregroundColor(.uiEmber)
                            Text("Безвозвратное удаление ВСЕХ заметок на устройстве")
                                .font(UIStyleFont.body(size: 11, weight: .regular))
                                .foregroundColor(.uiMidGray)
                        }
                        Spacer()
                        UIDestructiveButton(title: "Очистить") {
                            showingClearHistoryAlert = true
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.uiCanvas)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.checkPermissions()
        }
        .alert("Стереть всю историю?", isPresented: $showingClearHistoryAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Стереть", role: .destructive) {
                audioCapture.clearAllHistory()
            }
        } message: { Text("Все сохраненные транскрипции будут удалены безвозвратно. Это действие нельзя отменить.") }
    }
}
