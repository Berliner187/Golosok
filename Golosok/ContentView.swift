import SwiftUI

struct ContentView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var permissions = PermissionManager.shared
    @State private var selectedItemId: UUID?
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            // Если хотя бы одного разрешения нет — показываем экран анбординга
            if !permissions.isAllGranted || showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
            } else {
                mainInterface
            }
        }
        .onAppear {
            permissions.checkPermissions()
            if !permissions.isAllGranted {
                showOnboarding = true
            }
        }
    }
    
    // Основной интерфейс истории и деталей
    var mainInterface: some View {
        HStack(spacing: 0) {
            // ЛЕВАЯ ПАНЕЛЬ: Сайдбар
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Голосок")
                        .font(UIStyleFont.display(size: 16, weight: .semibold))
                        .foregroundColor(.uiInk)
                    Spacer()
                    UIBadge(text: "GigaAM v3")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                ScrollView {
                    VStack(spacing: 8) {
                        if audioCapture.history.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 20))
                                    .foregroundColor(.uiMidGray)
                                Text("История пуста")
                                    .font(UIStyleFont.body(size: 13, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(audioCapture.history) { item in
                                HistoryCard(item: item, isSelected: selectedItemId == item.id)
                                    .onTapGesture {
                                        selectedItemId = item.id
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                
                Spacer()
                
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
            .frame(width: 280)
            .background(Color.uiSidebar)
            
            Divider()
                .background(Color.uiHairline)
            
            // ПРАВАЯ ПАНЕЛЬ: Главное окно
            ZStack {
                Color.uiCanvas.ignoresSafeArea()
                
                VStack {
                    if let selected = audioCapture.history.first(where: { $0.id == selectedItemId }) {
                        UICard {
                            VStack(alignment: .leading, spacing: 20) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selected.date)
                                            .font(UIStyleFont.display(size: 14, weight: .semibold))
                                            .foregroundColor(.uiInk)
                                        Text("Длительность: \(selected.duration)")
                                            .font(UIStyleFont.body(size: 12, weight: .regular))
                                            .foregroundColor(.uiMidGray)
                                    }
                                    Spacer()
                                    
                                    UIOutlineButton(title: "Скопировать") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(selected.text, forType: .string)
                                    }
                                    
                                    UIDestructiveButton(title: "Удалить") {
                                        if let idx = audioCapture.history.firstIndex(where: { $0.id == selectedItemId }) {
                                            audioCapture.deleteItem(at: idx)
                                            selectedItemId = nil
                                        }
                                    }
                                }
                                
                                Divider()
                                    .background(Color.uiHairline)
                                
                                ScrollView {
                                    Text(selected.text)
                                        .font(UIStyleFont.body(size: 15, weight: .regular))
                                        .foregroundColor(.uiInk)
                                        .lineSpacing(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
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
                                        .tracking(-0.5)
                                    
                                    Text("Нажмите горячие клавиши в любом месте системы, чтобы запустить плавающий виджет диктовки.")
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
        }
        .frame(minWidth: 780, minHeight: 480)
    }
}

// MARK: - Карточка элемента истории в сайдбаре
struct HistoryCard: View {
    let item: TranscriptionItem
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.date)
                    .font(UIStyleFont.body(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .uiInk : .uiMidGray)
                Spacer()
                Text(item.duration)
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .foregroundColor(.uiMidGray)
            }
            
            Text(item.text)
                .font(UIStyleFont.body(size: 13, weight: .regular))
                .foregroundColor(.uiInk)
                .lineLimit(2)
        }
        .padding(12)
        .background(isSelected ? Color.uiPaper : Color.clear)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.uiHairline : Color.clear, lineWidth: 1)
        )
        .shadow(color: isSelected ? Color.black.opacity(0.02) : Color.clear, radius: 2, x: 0, y: 1)
    }
}
