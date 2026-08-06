import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var language = LanguageSettings.shared
    @ObservedObject var models = ModelStore.shared
    @State private var showingClearHistoryAlert = false
    @State private var showingAboutSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // РАЗДЕЛ 0: ЯЗЫК
                UICard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Язык приложения")
                                .font(UIStyleFont.body(size: 13, weight: .medium))
                                .foregroundColor(.uiInk)
                            Text("Приложение перезапустится автоматически")
                                .font(UIStyleFont.body(size: 11, weight: .regular))
                                .foregroundColor(.uiMidGray)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { language.current },
                            set: { language.select($0) }
                        )) {
                            Text("Система").tag(AppLanguage.system)
                            Text("Русский").tag(AppLanguage.ru)
                            Text("English").tag(AppLanguage.en)
                        }
                        .labelsHidden()
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 140)
                    }
                }
                
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
                                     LocalizedStringKey("Печатать расшифровку прямо в место курсора") :
                                     LocalizedStringKey("Выдайте доступ в Универсальном доступе macOS"))
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
                            UIBadge(text: String(localized: "⌥ + ПРОБЕЛ"))
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
                            Picker("", selection: Binding(
                                get: { models.activeModelID },
                                set: { models.activeModelID = $0 }
                            )) {
                                ForEach(ModelStore.catalog) { m in
                                    Text(LocalizedStringKey(m.name)).tag(m.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 200)
                        }

                        ActiveModelStatusRow()
                            .padding(.vertical, 4)

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

struct ActiveModelStatusRow: View {
    @ObservedObject var models = ModelStore.shared

    var body: some View {
        if let active = models.model(named: models.activeModelID), !active.isBundled {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(active.name))
                        .font(UIStyleFont.body(size: 13, weight: .medium))
                        .foregroundColor(.uiInk)
                    Text("\(active.sizeMB) МБ — Apple Metal")
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
                Spacer()
                if models.downloadingID == active.id {
                    ProgressView(value: models.downloadProgress)
                        .frame(width: 90)
                    Text(LocalizedStringKey(models.downloadStatus))
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                    UIOutlineButton(title: "Отмена") { models.cancel() }
                } else if models.isDownloaded(active.id) {
                    Text(LocalizedStringKey("RecognitionModel.Installed"))
                        .font(UIStyleFont.body(size: 11, weight: .regular))
                        .foregroundColor(.uiMidGray)
                    UIOutlineButton(title: "Удалить") { models.remove(active.id) }
                } else {
                    UIOutlineButton(title: "Скачать") { models.download(active.id) }
                }
            }
        }
    }
}
