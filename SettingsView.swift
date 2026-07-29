import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @State private var showingClearHistoryAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                UICard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ОСНОВНЫЕ")
                            .font(UIStyleFont.body(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.uiMidGray)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Автозапуск")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Автоматически запускать при входе в систему")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            Toggle("", isOn: $audioCapture.launchAtLoginEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Авто-вставка текста")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Вставлять расшифровку прямо в активное окно")
                                    .font(UIStyleFont.body(size: 11, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            Spacer()
                            Toggle("", isOn: $audioCapture.autoPasteEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#10B981")))
                        }
                        
                        Divider().background(Color.uiHairline)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Системные звуки")
                                    .font(UIStyleFont.body(size: 13, weight: .medium))
                                    .foregroundColor(.uiInk)
                                Text("Воспроизводить начало, отмену и конец записи")
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
                    }
                }
                
                UICard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Стереть историю")
                                .font(UIStyleFont.body(size: 13, weight: .bold))
                                .foregroundColor(.uiEmber)
                            Text("Безвозвратное удаление всех заметок из базы")
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
        .alert("Стереть всю историю?", isPresented: $showingClearHistoryAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Стереть", role: .destructive) {
                audioCapture.clearAllHistory()
            }
        } message: { Text("Все сохраненные транскрипции будут удалены безвозвратно. Это действие нельзя отменить.") }
    }
}
