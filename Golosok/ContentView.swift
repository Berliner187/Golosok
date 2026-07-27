import SwiftUI

enum MainTab {
    case dashboard
    case history
}

struct ContentView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var permissions = PermissionManager.shared
    
    @State private var currentTab: MainTab = .dashboard
    @State private var selectedItemId: UUID?
    @State private var showOnboarding = false
    
    // Поиск и Удаление
    @State private var searchText = ""
    @State private var itemToDelete: UUID?
    @State private var showingDeleteAlert = false
    
    var filteredHistory: [TranscriptionItem] {
        if searchText.isEmpty {
            return audioCapture.history
        } else {
            return audioCapture.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        Group {
            if !permissions.isAllGranted || showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
            } else {
                mainInterface
            }
        }
        .onAppear {
            permissions.checkPermissions()
            if !permissions.isAllGranted { showOnboarding = true }
        }
    }
    
    var mainInterface: some View {
        HStack(spacing: 0) {
            // ЛЕВАЯ ПАНЕЛЬ
            VStack(alignment: .leading, spacing: 16) {
                // ШАПКА
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.uiInk)
                    
                    VStack(alignment: .leading, spacing: -2) {
                        Text("Голосок")
                            .font(UIStyleFont.display(size: 16, weight: .bold))
                            .foregroundColor(.uiInk)
                        Text("v1.1.0")
                            .font(UIStyleFont.body(size: 10, weight: .medium))
                            .foregroundColor(.uiMidGray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                VStack(spacing: 4) {
                    SidebarTabButton(title: "Борд", icon: "chart.bar.fill", isActive: currentTab == .dashboard) {
                        currentTab = .dashboard
                        searchText = ""
                    }
                    
                    SidebarTabButton(title: "История", icon: "clock.fill", isActive: currentTab == .history) {
                        currentTab = .history
                    }
                }
                .padding(.horizontal, 8)
                
                Divider().background(Color.uiHairline)
                
                if currentTab == .history {
                    // ПОИСК
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.uiMidGray)
                        TextField("Поиск...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(UIStyleFont.body(size: 13, weight: .regular))
                            .foregroundColor(.uiInk)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.uiMidGray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color.uiPaper)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            if filteredHistory.isEmpty {
                                Text(searchText.isEmpty ? "История пуста" : "Ничего не найдено")
                                    .font(UIStyleFont.body(size: 13, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(filteredHistory) { item in
                                    HistoryCard(item: item, isSelected: selectedItemId == item.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedItemId = item.id }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                } else {
                    Spacer()
                }
                
                // ФУТЕР
                HStack {
                    Circle()
                        .fill(audioCapture.isRecording ? Color.uiEmber : Color.green)
                        .frame(width: 8, height: 8)
                    Text(audioCapture.isRecording ? "Запись..." : "Готов к работе")
                        .font(UIStyleFont.body(size: 12, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 270)
            .background(Color.uiSidebar)
            
            Divider().background(Color.uiHairline)
            
            // ПРАВАЯ ПАНЕЛЬ
            Group {
                if currentTab == .dashboard {
                    DashboardView()
                } else {
                    historyDetailView
                }
            }
        }
        .frame(minWidth: 840, minHeight: 520)
    }
    
    var historyDetailView: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            
            VStack {
                if let selected = audioCapture.history.first(where: { $0.id == selectedItemId }) {
                    UICard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    let parts = selected.date.components(separatedBy: ", ")
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(parts.first ?? selected.date)
                                            .font(UIStyleFont.display(size: 16, weight: .bold))
                                            .foregroundColor(.uiInk)
                                        if parts.count > 1 {
                                            Text(parts[1])
                                                .font(UIStyleFont.body(size: 12, weight: .medium))
                                                .foregroundColor(.uiMidGray)
                                        }
                                    }
                                    
                                    // КРАСИВЫЕ ЦВЕТНЫЕ БЕЙДЖИ-ТАБЛЕТКИ ИЗ СКРИНШОТА
                                    HStack(spacing: 8) {
                                        MetadataPill(icon: "waveform", text: selected.duration, color: Color.blue)
                                        MetadataPill(icon: "text.alignleft", text: "\(selected.text.count) зн", color: Color(hex: "#10B981"))
                                    }
                                }
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 8) {
                                    CopyFeedbackButton(textToCopy: selected.text)
                                    UIDestructiveButton(title: "Удалить") {
                                        itemToDelete = selected.id
                                        showingDeleteAlert = true
                                    }
                                }
                            }
                            
                            Divider().background(Color.uiHairline).padding(.vertical, 4)
                            
                            ScrollView {
                                Text(selected.text)
                                    .font(UIStyleFont.body(size: 15, weight: .regular))
                                    .foregroundColor(.uiInk)
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled) // ВЫДЕЛЕНИЕ МЫШЬЮ
                            }
                        }
                    }
                } else {
                    UICard {
                        VStack(spacing: 20) {
                            Image(systemName: "command")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.uiMidGray)
                            
                            VStack(spacing: 8) {
                                Text("⌥ + Пробел")
                                    .font(UIStyleFont.display(size: 28, weight: .semibold))
                                    .foregroundColor(.uiInk)
                                
                                Text("Нажмите горячие клавиши в любом месте системы, чтобы запустить диктовку.")
                                    .font(UIStyleFont.body(size: 13, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 320)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(20)
        }
        .alert("Удалить запись?", isPresented: $showingDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                if let id = itemToDelete, let idx = audioCapture.history.firstIndex(where: { $0.id == id }) {
                    withAnimation {
                        audioCapture.deleteItem(at: idx)
                        if selectedItemId == id { selectedItemId = nil }
                    }
                }
            }
        } message: { Text("Это действие нельзя отменить.") }
    }
}

// MARK: - Вспомогательные компоненты (ВНЕ ContentView)

// Умная кнопка копирования
struct CopyFeedbackButton: View {
    let textToCopy: String
    @State private var isCopied = false
    
    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            withAnimation(.spring()) { isCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring()) { isCopied = false }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                Text(isCopied ? "Скопировано!" : "Скопировать")
            }
            .font(UIStyleFont.body(size: 13, weight: .medium))
            .foregroundColor(isCopied ? Color(hex: "#10B981") : .uiInk)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Color.uiPaper)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isCopied ? Color(hex: "#10B981").opacity(0.5) : Color.uiHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Цветная таблетка
struct MetadataPill: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }
}

// Кнопка сайдбара
struct SidebarTabButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(UIStyleFont.body(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundColor(isActive ? .uiPaper : .uiInk)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isActive ? Color.uiInk : Color.clear)
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Карточка истории
struct HistoryCard: View {
    let item: TranscriptionItem
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                let parts = item.date.components(separatedBy: ", ")
                Text(parts.first ?? item.date)
                    .font(UIStyleFont.body(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .uiInk : .uiInkSoft)
                
                if parts.count > 1 {
                    Text(parts[1])
                        .font(UIStyleFont.body(size: 10, weight: .regular))
                        .foregroundColor(isSelected ? .uiMidGray : .uiMidGray.opacity(0.8))
                }
                
                Spacer()
                
                Text(item.duration)
                    .font(UIStyleFont.body(size: 10, weight: .regular))
                    .foregroundColor(.uiMidGray)
            }
            
            Text(item.text)
                .font(UIStyleFont.body(size: 13, weight: .regular))
                .foregroundColor(isSelected ? .uiInk : .uiMidGray)
                .lineLimit(2)
        }
        .padding(12)
        .background(isSelected ? Color.uiPaper : Color.clear)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.uiHairline : Color.clear, lineWidth: 1)
        )
        .shadow(color: isSelected ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 2)
    }
}
