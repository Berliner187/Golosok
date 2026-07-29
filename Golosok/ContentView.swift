import SwiftUI

enum MainTab { case history, dashboard, settings }

struct DateFormattingHelper {
    static func formatRussianDate(_ dateStr: String) -> (date: String, time: String) {
        let parts = dateStr.components(separatedBy: ", ")
        let datePart = parts.first ?? dateStr
        let timePart = parts.count > 1 ? parts[1] : ""
        
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd.MM.yyyy"
        
        if let dateObj = inputFormatter.date(from: datePart) {
            let outputFormatter = DateFormatter()
            outputFormatter.locale = Locale(identifier: "ru_RU")
            outputFormatter.dateFormat = "d MMMM yyyy"
            return (outputFormatter.string(from: dateObj), timePart)
        }
        
        return (datePart, timePart)
    }
}

struct ContentView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var permissions = PermissionManager.shared
    
    @State private var isSplashFinished = false
    
    @State private var currentTab: MainTab = .history
    @State private var selectedItemId: UUID?
    @State private var showOnboarding = false
    
    @State private var searchText = ""
    @State private var itemToDelete: UUID?
    @State private var showingDeleteAlert = false
    
    @State private var formattedDetailText: String = ""
    @State private var isFormattingText: Bool = false
    
    var filteredHistory: [TranscriptionItem] {
        if searchText.isEmpty { return audioCapture.history }
        else { return audioCapture.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) } }
    }
    
    var body: some View {
        ZStack {
            if !isSplashFinished {
                SplashView(isFinished: $isSplashFinished)
                    .transition(.opacity)
                    .zIndex(2)
            } else {
                Group {
                    if !permissions.onboardingCompleted {
                        OnboardingView(isPresented: $showOnboarding)
                    } else {
                        mainInterface
                    }
                }
                .transition(.opacity)
                .onAppear {
                    permissions.checkPermissions()
                }
            }
        }
    }

    
    var mainInterface: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image("AppLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 22, height: 22).cornerRadius(4)
                    VStack(alignment: .leading, spacing: -2) {
                        Text("Голосок").font(UIStyleFont.display(size: 16, weight: .bold)).foregroundColor(.uiInk)
                        HStack(spacing: 4) {
                            if let update = audioCapture.updateInfo {
                                Text(update.codename).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.5).foregroundColor(Color(hex: "#10B981")).padding(.horizontal, 4).padding(.vertical, 2).background(Color(hex: "#10B981").opacity(0.15)).cornerRadius(4)
                            } else {
                                Text((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "v1.4.0")).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.5).foregroundColor(Color(hex: "#10B981")).padding(.horizontal, 4).padding(.vertical, 2).background(Color(hex: "#10B981").opacity(0.15)).cornerRadius(4)
                            }
                        }
                    }
                    Spacer()
                }.padding(.horizontal, 16).padding(.top, 16)
                
                VStack(spacing: 4) {
                    SidebarTabButton(title: "История", icon: "clock.fill", isActive: currentTab == .history) { currentTab = .history }
                    SidebarTabButton(title: "Борд", icon: "chart.bar.fill", isActive: currentTab == .dashboard) { currentTab = .dashboard; searchText = "" }
                    SidebarTabButton(title: "Настройки", icon: "gearshape.fill", isActive: currentTab == .settings) { currentTab = .settings; searchText = "" }
                }.padding(.horizontal, 8)
                
                Divider().background(Color.uiHairline)
                
                if currentTab == .history {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.uiMidGray)
                        TextField("Поиск...", text: $searchText).textFieldStyle(PlainTextFieldStyle()).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiInk)
                        if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.uiMidGray) }.buttonStyle(.plain) }
                    }.padding(8).background(Color.uiPaper).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1)).padding(.horizontal, 12).padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            if filteredHistory.isEmpty { Text(searchText.isEmpty ? "История пуста" : "Ничего не найдено").font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiMidGray).padding(.vertical, 20) }
                            else { ForEach(filteredHistory) { item in HistoryCard(item: item, isSelected: selectedItemId == item.id).contentShape(Rectangle()).onTapGesture { selectedItemId = item.id } } }
                        }.padding(.horizontal, 8)
                    }
                } else { Spacer() }
                
                HStack {
                    Circle().fill(audioCapture.isRecording ? Color.uiEmber : Color.green).frame(width: 8, height: 8)
                    Text(audioCapture.isRecording ? "Запись..." : "Готов к работе").font(UIStyleFont.body(size: 12, weight: .regular)).foregroundColor(.uiMidGray)
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            .frame(width: 270).background(Color.uiSidebar)
            
            Divider().background(Color.uiHairline)
            
            Group {
                switch currentTab {
                case .history: historyDetailView
                case .dashboard: DashboardView()
                case .settings: SettingsView()
                }
            }
        }.frame(minWidth: 840, minHeight: 520)
    }
    
    var historyDetailView: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            VStack {
                if let selected = audioCapture.history.first(where: { $0.id == selectedItemId }) {
                    UICard {
                        VStack(alignment: .leading, spacing: 16) {
                            
                            // 1. ВЕРХНЯЯ СТРОКА: ДАТА И КНОПКИ УПРАВЛЕНИЯ
                            HStack(alignment: .center) {
                                let formattedDate = DateFormattingHelper.formatRussianDate(selected.date)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(formattedDate.date)
                                        .font(UIStyleFont.display(size: 16, weight: .bold))
                                        .foregroundColor(.uiInk)
                                    if !formattedDate.time.isEmpty {
                                        Text(formattedDate.time)
                                            .font(UIStyleFont.body(size: 11, weight: .medium))
                                            .foregroundColor(.uiMidGray)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.uiCanvas)
                                            .cornerRadius(6)
                                    }
                                }
                                
                                Spacer(minLength: 12)
                                
                                HStack(spacing: 8) {
                                    CopyFeedbackButton(textToCopy: selected.text)
                                    
                                    Menu {
                                        Button("Markdown (.md)") { audioCapture.exportTranscription(selected, format: "md") }
                                        Button("Текст (.txt)") { audioCapture.exportTranscription(selected, format: "txt") }
                                        Button("Excel (.csv)") { audioCapture.exportTranscription(selected, format: "csv") }
                                        Button("JSON (.json)") { audioCapture.exportTranscription(selected, format: "json") }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .medium))
                                            Text("Экспорт").font(UIStyleFont.body(size: 13, weight: .medium))
                                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.uiMidGray)
                                        }
                                        .lineLimit(1)
                                        .foregroundColor(.uiInk)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(Color.uiPaper)
                                        .cornerRadius(18)
                                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize(horizontal: true, vertical: false)
                                    
                                    UIDestructiveButton(title: "Удалить") {
                                        itemToDelete = selected.id
                                        showingDeleteAlert = true
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                            }
                            
                            HStack(spacing: 8) {
                                MetadataPill(icon: "waveform", text: selected.duration, color: Color.blue)
                                MetadataPill(icon: "bolt.fill", text: selected.formattedSpeedup, color: Color.orange)
                                MetadataPill(icon: "text.alignleft", text: "\(selected.text.count) зн", color: Color(hex: "#10B981"))
                                
                                let readMin = max(1, selected.text.count / 900)
                                MetadataPill(icon: "book.fill", text: "~\(readMin) мин чтения", color: Color.purple)
                                
                                if audioCapture.hasAudioFile(for: selected) {
                                    Button(action: {
                                        audioCapture.toggleAudioPlayback(for: selected)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: audioCapture.playingItemId == selected.id ? "pause.fill" : "play.fill")
                                                .font(.system(size: 9, weight: .bold))
                                            Text(audioCapture.playingItemId == selected.id ? "Пауза" : "Слушать голос")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                        }
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.12))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Divider().background(Color.uiHairline).padding(.vertical, 4)
                            
                            // 3. ТЕКСТ ТРАНСКРИПЦИИ
                            if isFormattingText {
                                VStack(spacing: 12) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Оптимизация текста...").font(UIStyleFont.body(size: 12, weight: .regular)).foregroundColor(.uiMidGray)
                                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView {
                                    Text(formattedDetailText)
                                        .font(UIStyleFont.body(size: 15, weight: .regular))
                                        .foregroundColor(.uiInk)
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .task(id: selectedItemId) {
                        guard let id = selectedItemId, let item = audioCapture.history.first(where: { $0.id == id }) else { formattedDetailText = ""; return }
                        isFormattingText = true
                        let raw = item.text
                        let formatted = await Task.detached(priority: .userInitiated) { return TextFormatter.formatIntoParagraphs(raw) }.value
                        self.formattedDetailText = formatted
                        self.isFormattingText = false
                    }
                } else {
                    UICard {
                        VStack(spacing: 20) {
                            Image(systemName: "command").font(.system(size: 32, weight: .light)).foregroundColor(.uiMidGray)
                            VStack(spacing: 8) {
                                Text("⌥ + ПРОБЕЛ").font(UIStyleFont.display(size: 28, weight: .semibold)).foregroundColor(.uiInk)
                                Text("Нажмите горячие клавиши в любом месте системы, чтобы запустить диктовку.").font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiMidGray).multilineTextAlignment(.center).frame(maxWidth: 320)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }.padding(20)
        }
        .alert("Удалить запись?", isPresented: $showingDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                if let id = itemToDelete, let idx = audioCapture.history.firstIndex(where: { $0.id == id }) {
                    withAnimation { audioCapture.deleteItem(at: idx); if selectedItemId == id { selectedItemId = nil } }
                }
            }
        } message: { Text("Это действие нельзя отменить.") }
    }
}

struct CopyFeedbackButton: View {
    let textToCopy: String
    @State private var isCopied = false
    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            withAnimation(.spring()) { isCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(.spring()) { isCopied = false } }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .medium))
                Text(isCopied ? "Готово!" : "Скопировать")
            }
            .lineLimit(1)
            .font(UIStyleFont.body(size: 13, weight: .medium))
            .foregroundColor(isCopied ? Color(hex: "#10B981") : .uiInk)
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Color.uiPaper).cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isCopied ? Color(hex: "#10B981").opacity(0.5) : Color.uiHairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct MetadataPill: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text).font(.system(size: 10, weight: .bold, design: .rounded))
        }.foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.12)).cornerRadius(6)
    }
}

struct SidebarTabButton: View {
    let title: String; let icon: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: icon).font(.system(size: 13)); Text(title).font(UIStyleFont.body(size: 13, weight: .medium)); Spacer() }
            .foregroundColor(isActive ? .uiPaper : .uiInk).padding(.vertical, 8).padding(.horizontal, 12)
            .background(isActive ? Color.uiInk : Color.clear).cornerRadius(12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct HistoryCard: View {
    let item: TranscriptionItem; let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                let formatted = DateFormattingHelper.formatRussianDate(item.date)
                Text(formatted.date).font(UIStyleFont.body(size: 12, weight: .semibold)).foregroundColor(isSelected ? .uiInk : .uiInkSoft)
                if !formatted.time.isEmpty { Text(formatted.time).font(UIStyleFont.body(size: 10, weight: .regular)).foregroundColor(isSelected ? .uiMidGray : .uiMidGray.opacity(0.8)) }
                Spacer()
                Text(item.duration).font(UIStyleFont.body(size: 10, weight: .regular)).foregroundColor(.uiMidGray)
            }
            Text(item.text).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(isSelected ? .uiInk : .uiMidGray).lineLimit(2)
        }
        .padding(12).background(isSelected ? Color.uiPaper : Color.clear).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.uiHairline : Color.clear, lineWidth: 1))
        .shadow(color: isSelected ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 2)
    }
}
