import SwiftUI
import AppKit

enum MainTab { case history, dashboard, settings }

struct DateFormattingHelper {
    private static let inputFormatter: DateFormatter = { let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"; return df }()
    private static let outputFormatter: DateFormatter = { let df = DateFormatter(); df.locale = Locale.current; df.dateFormat = "d MMMM yyyy"; return df }()
    static func formatRussianDate(_ dateStr: String) -> (date: String, time: String) {
        let parts = dateStr.components(separatedBy: ", ")
        let datePart = parts.first ?? dateStr; let timePart = parts.count > 1 ? parts[1] : ""
        if let dateObj = inputFormatter.date(from: datePart) { return (outputFormatter.string(from: dateObj), timePart) }
        return (datePart, timePart)
    }
}

struct NativeTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false; textView.isSelectable = true; textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular); textView.textColor = NSColor(Color.uiInk)
        textView.textContainerInset = NSSize(width: 0, height: 10)
        return scrollView
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text; textView.textColor = NSColor(Color.uiInk) }
    }
}

struct SyncedPlayerView: View {
    let text: String
    let words: [TimedWord]
    let audioDuration: Double
    let itemID: UUID
    @ObservedObject var audioCapture = AudioCapture.shared

    private var isPlaying: Bool {
        audioCapture.playingItemId == itemID && audioCapture.isPlayerPlaying
    }

    private var playhead: Double {
        audioCapture.playingItemId == itemID ? audioCapture.playheadTime : 0
    }

    private var currentWordIndex: Int? {
        guard audioCapture.playingItemId == itemID else { return nil }
        let t = audioCapture.playheadTime
        guard !words.isEmpty else { return nil }
        var lo = 0, hi = words.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if t >= words[mid].start && t < words[mid].end { return mid }
            if t < words[mid].start { hi = mid - 1 } else { lo = mid + 1 }
        }
        if t >= words[words.count - 1].end { return words.count - 1 }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: { audioCapture.toggleSyncedPlayback(for: itemID) }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Text(formatTime(playhead))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.uiMidGray)

                Slider(value: Binding(
                    get: { playhead },
                    set: { audioCapture.seekSynced(to: $0, for: itemID) }
                ), in: 0...max(audioDuration, 0.01))

                Text(formatTime(audioDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.uiMidGray)
            }

            SyncedTextView(text: text, words: words, currentWordIndex: currentWordIndex) { time in
                audioCapture.seekSynced(to: time, for: itemID)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct SyncedTextView: NSViewRepresentable {
    let text: String
    let words: [TimedWord]
    let currentWordIndex: Int?
    let onSeek: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSeek: onSeek) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(Color.uiInk)
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(Color.uiInk),
            .underlineStyle: 0,
            .cursor: NSCursor.pointingHand
        ]
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.onSeek = onSeek

        let ranges = context.coordinator.wordRanges(text: text, words: words)
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(Color.uiInk)
        ])
        if !ranges.isEmpty {
            for (i, range) in ranges.enumerated() where i < words.count {
                let url = URL(string: "golosok://seek/\(words[i].start)")
                attributed.addAttribute(.link, value: url as Any, range: range)
                attributed.addAttribute(.underlineStyle, value: 0, range: range)
                if i == currentWordIndex {
                    attributed.addAttribute(.backgroundColor, value: NSColor.blue.withAlphaComponent(0.18), range: range)
                }
            }
        }
        textView.textStorage?.setAttributedString(attributed)
        if let index = currentWordIndex, index < ranges.count {
            textView.scrollRangeToVisible(ranges[index])
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSeek: (Double) -> Void
        init(onSeek: @escaping (Double) -> Void) { self.onSeek = onSeek }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "golosok",
                  let time = Double(url.lastPathComponent) else { return false }
            onSeek(time)
            return true
        }

        func wordRanges(text: String, words: [TimedWord]) -> [NSRange] {
            guard !words.isEmpty else { return [] }
            var ranges: [NSRange] = []
            let nsText = text as NSString
            let length = nsText.length
            var searchFrom = 0
            var wordIndex = 0

            while wordIndex < words.count && searchFrom < length {
                while searchFrom < length {
                    let scalar = UnicodeScalar(nsText.character(at: searchFrom))
                    if !CharacterSet.whitespacesAndNewlines.contains(scalar ?? " ") { break }
                    searchFrom += 1
                }
                guard searchFrom < length else { return [] }
                let word = words[wordIndex].text
                let searchRange = NSRange(location: searchFrom, length: length - searchFrom)
                let range = nsText.range(of: word, options: [], range: searchRange)
                guard range.location != NSNotFound, range.location == searchFrom else { return [] }
                ranges.append(range)
                searchFrom = range.location + range.length
                wordIndex += 1
            }
            return wordIndex == words.count ? ranges : []
        }
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
    @State private var selectedTimings: (words: [TimedWord], duration: Double)?
    
    @State private var showAboutSheet = false
    
    var filteredHistory: [TranscriptionItem] {
        if searchText.isEmpty { return audioCapture.history }
        else { return audioCapture.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) } }
    }
    
    var body: some View {
        ZStack {
            if !isSplashFinished {
                SplashView(isFinished: $isSplashFinished).transition(.opacity).zIndex(2)
            } else {
                Group {
                    if !permissions.onboardingCompleted { OnboardingView(isPresented: $showOnboarding) }
                    else { mainInterface }
                }
                .transition(.opacity).onAppear { permissions.checkPermissions() }
            }
        }
        // Автоматическое открытие заметки
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoSelectNote"))) { notification in
            if audioCapture.autoOpenNoteEnabled, let newId = notification.object as? UUID {
                withAnimation {
                    self.currentTab = .history
                    self.searchText = ""
                    self.selectedItemId = newId
                }
                audioCapture.markAsRead(id: newId)
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAboutModal"))) { _ in
            showAboutSheet = true
        }
    }
    
    var mainInterface: some View {
        HStack(spacing: 0) {
            sidebarView
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
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sidebarHeader
            VStack(spacing: 4) {
                SidebarTabButton(title: "История", icon: "clock.fill", isActive: currentTab == .history) {
                    currentTab = .history
                    selectedItemId = nil
                }
                SidebarTabButton(title: "Борд", icon: "chart.bar.fill", isActive: currentTab == .dashboard) {
                    currentTab = .dashboard
                    searchText = ""
                }
                SidebarTabButton(title: "Настройки", icon: "gearshape.fill", isActive: currentTab == .settings) {
                    currentTab = .settings
                    searchText = ""
                }
            }
            .padding(.horizontal, 8)
            Divider().background(Color.uiHairline)
            if currentTab == .history { historySearchAndList } else { Spacer() }
            sidebarFooter
        }.frame(width: 270).background(Color.uiSidebar)
    }
    
    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image("AppLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 22, height: 22).cornerRadius(4)
            VStack(alignment: .leading, spacing: -2) {
                Text("Голосок").font(UIStyleFont.display(size: 16, weight: .bold)).foregroundColor(.uiInk)
                HStack(spacing: 4) {
                    let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                    Text(versionStr).font(UIStyleFont.body(size: 10, weight: .medium)).foregroundColor(.uiMidGray)
                }
            }
            Spacer()
        }.padding(.horizontal, 16).padding(.top, 16)
    }
    
    private var historySearchAndList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.uiMidGray)
                TextField("Поиск...", text: $searchText).textFieldStyle(PlainTextFieldStyle()).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiInk)
                if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.uiMidGray) }.buttonStyle(.plain) }
            }.padding(8).background(Color.uiPaper).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1)).padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredHistory.isEmpty { Text(searchText.isEmpty ? LocalizedStringKey("История пуста") : LocalizedStringKey("Ничего не найдено")).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiMidGray).padding(.vertical, 20) }
                    else {
                        ForEach(filteredHistory) { item in
                            HistoryCard(item: item, isSelected: selectedItemId == item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedItemId = item.id
                                    audioCapture.markAsRead(id: item.id) // Гасим точку при клике руками
                                }
                        }
                    }
                }.padding(.horizontal, 8)
            }
        }
    }
    
    private var sidebarFooter: some View {
        HStack {
            Circle().fill(audioCapture.isRecording ? Color.uiEmber : Color.green).frame(width: 8, height: 8)
            Text(audioCapture.isRecording ? LocalizedStringKey("Запись...") : LocalizedStringKey("Готов к работе")).font(UIStyleFont.body(size: 12, weight: .regular)).foregroundColor(.uiMidGray)
        }.padding(.horizontal, 16).padding(.bottom, 16)
    }
    
    var historyDetailView: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()
            VStack {
                if let selected = audioCapture.history.first(where: { $0.id == selectedItemId }) {
                    UICard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center) {
                                let formattedDate = DateFormattingHelper.formatRussianDate(selected.date)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(formattedDate.date).font(UIStyleFont.display(size: 16, weight: .bold)).foregroundColor(.uiInk)
                                    if !formattedDate.time.isEmpty { Text(formattedDate.time).font(UIStyleFont.body(size: 11, weight: .medium)).foregroundColor(.uiMidGray).padding(.horizontal, 6).padding(.vertical, 2).background(Color.uiCanvas).cornerRadius(6) }
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
                                        HStack(spacing: 4) { Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .medium)); Text("Экспорт").font(UIStyleFont.body(size: 13, weight: .medium)); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.uiMidGray) }
                                        .lineLimit(1).foregroundColor(.uiInk).padding(.vertical, 8).padding(.horizontal, 14).background(Color.uiPaper).cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
                                    }.menuStyle(.borderlessButton).fixedSize(horizontal: true, vertical: false)
                                    UIDestructiveButton(title: "Удалить") { itemToDelete = selected.id; showingDeleteAlert = true }
                                }.fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                            }
                            
                            HStack(spacing: 8) {
                                MetadataPill(icon: "waveform", text: selected.duration, color: Color.blue)
                                MetadataPill(icon: "bolt.fill", text: selected.formattedSpeedup, color: Color.orange)
                                MetadataPill(icon: "text.alignleft", text: "\(selected.text.count) " + String(localized: "зн"), color: Color(hex: "#10B981"))
                                let readMin = max(1, selected.text.count / 900)
                                MetadataPill(icon: "book.fill", text: "~\(readMin) " + String(localized: "мин чтения"), color: Color.purple)
                                if selectedTimings == nil && audioCapture.hasAudioFile(for: selected) {
                                    Button(action: { audioCapture.toggleAudioPlayback(for: selected) }) {
                                        HStack(spacing: 4) { Image(systemName: audioCapture.playingItemId == selected.id ? "pause.fill" : "play.fill").font(.system(size: 9, weight: .bold)); Text(audioCapture.playingItemId == selected.id ? LocalizedStringKey("Пауза") : LocalizedStringKey("Слушать голос")).font(.system(size: 10, weight: .bold, design: .rounded)) }
                                        .foregroundColor(.blue).padding(.horizontal, 8).padding(.vertical, 4).background(Color.blue.opacity(0.12)).cornerRadius(6)
                                    }.buttonStyle(.plain)
                                }
                            }
                            
                            Divider().background(Color.uiHairline).padding(.vertical, 4)
                            if let timings = selectedTimings {
                                SyncedPlayerView(text: selected.text, words: timings.words, audioDuration: timings.duration, itemID: selected.id)
                            } else {
                                NativeTextView(text: selected.text)
                            }
                        }
                    }
                } else {
                    UICard {
                        VStack(spacing: 24) {
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Image("AppLogo")
                                        .resizable()
                                        .frame(width: 26, height: 26)
                                        .cornerRadius(6)
                                    Text("Голосок")
                                        .font(UIStyleFont.display(size: 20, weight: .bold))
                                        .foregroundColor(.uiInk)
                                }
                                Text("Локальное приложение для надиктовки, расшифровки созвонов и работы с медиафайлами")
                                    .font(UIStyleFont.body(size: 13, weight: .regular))
                                    .foregroundColor(.uiMidGray)
                            }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                CapabilityCard(
                                    icon: "keyboard",
                                    badge: NativeHotKeyManager.shared.displayName(),
                                    title: "Быстрый ввод",
                                    description: "Надиктуйте мысль – текст сразу появится под курсором в любом приложении"
                                )

                                CapabilityCard(
                                    icon: "video.fill",
                                    badge: String(localized: "⌘ + O / МЕНЮ"),
                                    title: "Созвоны и файлы",
                                    description: "Расшифровка встреч Zoom, Телемоста и любых медиафайлов: MP3, MP4, WebM"
                                )

                                CapabilityCard(
                                    icon: "play.circle.fill",
                                    badge: String(localized: "ОРИГИНАЛ"),
                                    title: "Сверка аудио",
                                    description: "Слушайте исходный звук прямо в заметке, чтобы проверить соответствие с текстом"
                                )

                                CapabilityCard(
                                    icon: "doc.badge.gearshape.fill",
                                    badge: String(localized: "4 ФОРМАТА"),
                                    title: "Экспорт",
                                    description: "Авто-деление на абзацы и сохранение в Markdown, CSV, TXT или JSON"
                                )
                            }
                        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }.padding(20)
        }
        .onAppear { loadSelectedTimings() }
        .onChange(of: selectedItemId) { newId in
            audioCapture.stopSyncedPlayback()
            if let id = newId { selectedTimings = audioCapture.timings(for: id) } else { selectedTimings = nil }
        }
        .alert("Удалить запись?", isPresented: $showingDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                if let id = itemToDelete, let idx = audioCapture.history.firstIndex(where: { $0.id == id }) {
                    SoundEffect.playDelete()
                    withAnimation {
                        audioCapture.stopSyncedPlayback()
                        audioCapture.deleteItem(at: idx)
                        if selectedItemId == id { selectedItemId = nil }
                    }
                }
            }
        } message: { Text("Это действие нельзя отменить.") }
    }

    private func loadSelectedTimings() {
        if let id = selectedItemId { selectedTimings = audioCapture.timings(for: id) }
        else { selectedTimings = nil }
    }
}

// MARK: - ВСПОМОГАТЕЛЬНЫЕ КОМПОНЕНТЫ

struct CapabilityCard: View {
    let icon: String; let badge: String; let title: LocalizedStringKey; let description: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(.uiInk); Spacer(); UIBadge(text: badge) }
            VStack(alignment: .leading, spacing: 4) { Text(title).font(UIStyleFont.display(size: 14, weight: .semibold)).foregroundColor(.uiInk); Text(description).font(UIStyleFont.body(size: 12, weight: .regular)).foregroundColor(.uiMidGray).lineSpacing(2) }
        }.padding(16).background(Color.uiSidebar).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.uiHairline, lineWidth: 1))
    }
}

struct CopyFeedbackButton: View {
    let textToCopy: String
        @State private var isCopied = false
        var body: some View {
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(textToCopy, forType: .string)
                SoundEffect.playCopy()
                withAnimation(.spring()) { isCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation(.spring()) { isCopied = false } }
            }) {
                HStack(spacing: 6) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .medium))
                Text(isCopied ? LocalizedStringKey("Готово!") : LocalizedStringKey("Скопировать"))
            }
            .lineLimit(1)
            .font(UIStyleFont.body(size: 13, weight: .medium))
            .foregroundColor(isCopied ? Color(hex: "#10B981") : .uiInk)
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Color.uiPaper).cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isCopied ? Color(hex: "#10B981").opacity(0.5) : Color.uiHairline, lineWidth: 1))
        }
        .buttonStyle(TactileButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SidebarTabButton: View {
    let title: LocalizedStringKey
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: icon).font(.system(size: 13)); Text(title).font(UIStyleFont.body(size: 13, weight: .medium)); Spacer() }
            .foregroundColor(isActive ? .uiPaper : .uiInk).padding(.vertical, 8).padding(.horizontal, 12)
            .background(isActive ? Color.uiInk : Color.clear).cornerRadius(12).contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
    }
}
struct MetadataPill: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 4) { Image(systemName: icon).font(.system(size: 9, weight: .bold)); Text(text).font(.system(size: 10, weight: .bold, design: .rounded)) }
        .foregroundColor(color).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.12)).cornerRadius(6)
    }
}

// СИСТЕМНАЯ КАРТОЧКА С СИНЕЙ ТОЧКОЙ
struct HistoryCard: View {
    let item: TranscriptionItem
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // СИНЯЯ ТОЧКА НЕПРОЧИТАННОГО!
                if item.isUnread == true {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
                
                let formatted = DateFormattingHelper.formatRussianDate(item.date)
                Text(formatted.date).font(UIStyleFont.body(size: 12, weight: .semibold)).foregroundColor(isSelected ? .uiInk : .uiInkSoft)
                if !formatted.time.isEmpty { Text(formatted.time).font(UIStyleFont.body(size: 10, weight: .regular)).foregroundColor(isSelected ? .uiMidGray : .uiMidGray.opacity(0.8)) }
                Spacer()
                Text(item.duration).font(UIStyleFont.body(size: 10, weight: .regular)).foregroundColor(.uiMidGray)
            }
            Text(item.text).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(isSelected ? .uiInk : .uiInkSoft).lineLimit(2)
        }
        .padding(12).background(isSelected ? Color.uiPaper : Color.clear).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.uiHairline : Color.clear, lineWidth: 1))
        .shadow(color: isSelected ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 2)
    }
}
