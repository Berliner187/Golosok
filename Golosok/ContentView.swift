import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        textView.unregisterDraggedTypes()
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
        return lo > 0 ? lo - 1 : nil
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

                UISeekSlider(value: Binding(
                    get: { playhead },
                    set: { audioCapture.seekSynced(to: $0, for: itemID) }
                ), range: 0...max(audioDuration, 0.01))

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
        textView.unregisterDraggedTypes()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.onSeek = onSeek

        if coordinator.cachedText != text || coordinator.cachedWords != words {
            coordinator.cachedText = text
            coordinator.cachedWords = words
            coordinator.cachedRanges = coordinator.wordRanges(text: text, words: words)
            coordinator.highlightedIndex = nil

            let attributed = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: NSColor(Color.uiInk)
            ])
            for (i, range) in coordinator.cachedRanges.enumerated() where i < words.count && range.location != NSNotFound {
                let url = URL(string: "golosok://seek/\(words[i].start)")
                attributed.addAttribute(.link, value: url as Any, range: range)
                attributed.addAttribute(.underlineStyle, value: 0, range: range)
            }
            textView.textStorage?.setAttributedString(attributed)
        }
        coordinator.applyHighlight(in: textView, currentWordIndex: currentWordIndex)

        if let index = currentWordIndex, index != coordinator.lastScrolledIndex, index < coordinator.cachedRanges.count {
            let range = coordinator.cachedRanges[index]
            if range.location != NSNotFound {
                textView.scrollRangeToVisible(range)
                coordinator.lastScrolledIndex = index
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSeek: (Double) -> Void
        var cachedText: String?
        var cachedWords: [TimedWord]?
        var cachedRanges: [NSRange] = []
        var highlightedIndex: Int?
        var lastScrolledIndex: Int?

        init(onSeek: @escaping (Double) -> Void) { self.onSeek = onSeek }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "golosok",
                  let time = Double(url.lastPathComponent) else { return false }
            onSeek(time)
            return true
        }

        func applyHighlight(in textView: NSTextView, currentWordIndex: Int?) {
            if let prev = highlightedIndex, prev != currentWordIndex, prev < cachedRanges.count {
                let range = cachedRanges[prev]
                if range.location != NSNotFound {
                    textView.textStorage?.removeAttribute(.backgroundColor, range: range)
                }
            }
            highlightedIndex = currentWordIndex
            if let index = currentWordIndex, index < cachedRanges.count {
                let range = cachedRanges[index]
                if range.location != NSNotFound {
                    textView.textStorage?.addAttribute(.backgroundColor, value: NSColor.transcriptHighlight, range: range)
                }
            }
        }

        func wordRanges(text: String, words: [TimedWord]) -> [NSRange] {
            guard !words.isEmpty, !text.isEmpty else { return [] }
            let nsText = text as NSString
            let length = nsText.length

            func isWhitespace(_ c: unichar) -> Bool {
                CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(c) ?? " ")
            }
            func normalized(_ s: String) -> String {
                s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
                    .filter { $0.isLetter || $0.isNumber }
                    .lowercased()
            }

            var tokens: [NSRange] = []
            var scan = 0
            while scan < length {
                if isWhitespace(nsText.character(at: scan)) { scan += 1; continue }
                let start = scan
                while scan < length && !isWhitespace(nsText.character(at: scan)) { scan += 1 }
                tokens.append(NSRange(location: start, length: scan - start))
            }
            guard !tokens.isEmpty else { return [] }

            let n = words.count
            let m = tokens.count

            // Fast path: exact positional alignment.
            var pos = 0
            var strict = true
            for w in words {
                let word = w.text
                while pos < length && isWhitespace(nsText.character(at: pos)) { pos += 1 }
                guard pos < length else { strict = false; break }
                let found = nsText.range(of: word, options: [], range: NSRange(location: pos, length: length - pos))
                if found.location != pos { strict = false; break }
                pos += found.length
            }
            if strict {
                var ranges: [NSRange] = []
                pos = 0
                for w in words {
                    while pos < length && isWhitespace(nsText.character(at: pos)) { pos += 1 }
                    let word = w.text as NSString
                    ranges.append(NSRange(location: pos, length: word.length))
                    pos += word.length
                }
                return ranges
            }

            // Robust path: longest-common-subsequence alignment on normalized tokens.
            let textNorm = tokens.map { normalized(nsText.substring(with: $0)) }
            let wordNorm = words.map { normalized($0.text) }
            let maxCells = 5_000_000
            if n * m <= maxCells {
                var dp = [[Int16]](repeating: [Int16](repeating: 0, count: m + 1), count: n + 1)
                var back = [[Int8]](repeating: [Int8](repeating: 0, count: m + 1), count: n + 1)
                for a in stride(from: n - 1, through: 0, by: -1) {
                    for b in stride(from: m - 1, through: 0, by: -1) {
                        let wn = wordNorm[a]
                        if !wn.isEmpty && wn == textNorm[b] {
                            dp[a][b] = dp[a + 1][b + 1] + 1
                            back[a][b] = 1
                        } else if dp[a + 1][b] >= dp[a][b + 1] {
                            dp[a][b] = dp[a + 1][b]
                            back[a][b] = 2
                        } else {
                            dp[a][b] = dp[a][b + 1]
                            back[a][b] = 3
                        }
                    }
                }
                var ranges = [NSRange](repeating: NSRange(location: NSNotFound, length: 0), count: n)
                var a = 0, b = 0
                while a < n && b < m {
                    if back[a][b] == 1 { ranges[a] = tokens[b]; a += 1; b += 1 }
                    else if back[a][b] == 2 { a += 1 }
                    else { b += 1 }
                }
                return ranges
            }

            // Greedy fallback for very large texts.
            var ranges = [NSRange](repeating: NSRange(location: NSNotFound, length: 0), count: n)
            pos = 0
            for (k, w) in words.enumerated() {
                let word = w.text
                guard !word.isEmpty else { continue }
                while pos < length && isWhitespace(nsText.character(at: pos)) { pos += 1 }
                guard pos < length else { break }
                let rest = NSRange(location: pos, length: length - pos)
                if nsText.range(of: word, options: [], range: rest).location == pos {
                    ranges[k] = NSRange(location: pos, length: (word as NSString).length)
                    pos += (word as NSString).length
                } else if nsText.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: rest).location == pos {
                    ranges[k] = NSRange(location: pos, length: (word as NSString).length)
                    pos += (word as NSString).length
                }
            }
            return ranges
        }
    }
}

struct ContentView: View {
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var permissions = PermissionManager.shared
    @ObservedObject var promptStore = PromptStore.shared
    
    @State private var isSplashFinished = false
    @State private var currentTab: MainTab = .history
    @State private var selectedItemId: UUID?
    @State private var showOnboarding = false
    
    @State private var searchText = ""
    @State private var filteredResults: [TranscriptionItem] = []
    @State private var searchDebounce: DispatchWorkItem?
    @State private var isSearching = false
    @State private var itemToDelete: UUID?
    @State private var showingDeleteAlert = false
    @State private var selectedTimings: (words: [TimedWord], duration: Double)?
    
    @State private var showAboutSheet = false
    @State private var isFileDropTargeted = false
    @State private var aiRequest: AIActionRequest?
    @State private var showPromptManager = false
    @State private var showCreatePrompt = false

    @State private var isEditing: Bool = false
    @State private var editableText: String = ""
    @State private var editingItemID: UUID?
    @State private var editSaveWorkItem: DispatchWorkItem?
    
    private var displayedHistory: [TranscriptionItem] {
        searchText.isEmpty ? audioCapture.history : filteredResults
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            audioCapture.checkUpdates()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isFileDropTargeted) { providers in
            handleDroppedProviders(providers)
        }
        .onChange(of: searchText) { newValue in
            scheduleSearch(newValue)
        }
        .overlay {
            if isFileDropTargeted {
                FileDropOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isFileDropTargeted)
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileType = UTType.fileURL.identifier
        let loaders = providers.filter { $0.hasItemConformingToTypeIdentifier(fileType) }
        guard !loaders.isEmpty else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in loaders {
            group.enter()
            provider.loadItem(forTypeIdentifier: fileType, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let str = item as? String, let url = URL(string: str) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { audioCapture.importFiles(urls) }
        }
        return true
    }

    private func scheduleSearch(_ query: String) {
        searchDebounce?.cancel()
        if query.isEmpty {
            withAnimation(.easeOut(duration: 0.16)) {
                isSearching = false
                filteredResults = []
            }
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            isSearching = true
        }
        let item = DispatchWorkItem {
            self.performSearch(query)
        }
        searchDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    private func performSearch(_ query: String) {
        let history = audioCapture.history
        DispatchQueue.global(qos: .userInitiated).async {
            let results = history.filter {
                $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            DispatchQueue.main.async {
                guard self.searchText == query else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    self.filteredResults = results
                    self.isSearching = false
                }
            }
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
            HStack(spacing: 8) {
                HStack {
                    if isSearching {
                        ProgressView().controlSize(.small)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    } else {
                        Image(systemName: "magnifyingglass").foregroundColor(.uiMidGray)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                    TextField("Поиск...", text: $searchText).textFieldStyle(PlainTextFieldStyle()).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiInk)
                    if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.uiMidGray) }.buttonStyle(.plain) }
                }
                .padding(8).background(Color.uiPaper).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
                Button(action: createNote) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.uiInk)
                        .frame(width: 30, height: 30)
                        .background(Color.uiPaper)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.uiHairline, lineWidth: 1))
                }
                .buttonStyle(TactileButtonStyle())
                .help(String(localized: "Новая заметка"))
            }.padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if isSearching {
                        ForEach(0..<4, id: \.self) { _ in
                            HistorySkeletonCard()
                        }
                    } else if displayedHistory.isEmpty {
                        Text(searchText.isEmpty ? LocalizedStringKey("История пуста") : LocalizedStringKey("Ничего не найдено")).font(UIStyleFont.body(size: 13, weight: .regular)).foregroundColor(.uiMidGray).padding(.vertical, 20)
                    } else {
                        ForEach(displayedHistory) { item in
                            Button {
                                selectedItemId = item.id
                                audioCapture.markAsRead(id: item.id) // Гасим точку при клике руками
                            } label: {
                                HistoryCard(item: item, isSelected: selectedItemId == item.id)
                            }
                            .buttonStyle(TactileButtonStyle())
                        }
                    }
                }.padding(.horizontal, 8)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isSearching)
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
                            let formattedDate = DateFormattingHelper.formatRussianDate(selected.date)
                            let dateHeader: () -> AnyView = {
                                AnyView(
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(formattedDate.date).font(UIStyleFont.display(size: 16, weight: .bold)).foregroundColor(.uiInk).lineLimit(1)
                                        if !formattedDate.time.isEmpty { Text(formattedDate.time).font(UIStyleFont.body(size: 11, weight: .medium)).foregroundColor(.uiMidGray).padding(.horizontal, 6).padding(.vertical, 2).background(Color.uiCanvas).cornerRadius(6) }
                                    }
                                )
                            }
                            let buttonsRow: () -> AnyView = {
                                AnyView(
                                    HStack(spacing: 8) {
                                        CopyFeedbackButton(textToCopy: selected.text)
                                        EditToggleButton(isEditing: isEditing) {
                                            if isEditing { commitEditing(for: selected) } else { beginEditing(selected) }
                                        }
                                        UIDropdownMenu(items: {
                                            var arr: [UIDropdownItem] = promptStore.templates.map { t in
                                                let label: Text = t.isCustom ? Text(t.title) : Text(LocalizedStringKey(t.title))
                                                return .action(text: label, icon: t.icon) {
                                                    aiRequest = AIActionRequest(template: t, noteID: selected.id, noteText: selected.text)
                                                }
                                            }
                                            arr.append(.divider)
                                            arr.append(.action("Новый промпт…", icon: "plus") { showCreatePrompt = true })
                                            arr.append(.action("Управлять промптами…", icon: "slider.horizontal.3") { showPromptManager = true })
                                            return arr
                                        }()) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "sparkles").font(.system(size: 11, weight: .medium))
                                                Text("ИИ").font(UIStyleFont.body(size: 13, weight: .medium))
                                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.uiMidGray)
                                            }
                                            .lineLimit(1).foregroundColor(.uiInk).padding(.vertical, 8).padding(.horizontal, 14).background(Color.uiPaper).cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
                                        }.fixedSize(horizontal: true, vertical: false)
                                        UIDropdownMenu(items: [
                                            .action("Markdown (.md)") { audioCapture.exportTranscription(selected, format: "md") },
                                            .action("Текст (.txt)") { audioCapture.exportTranscription(selected, format: "txt") },
                                            .action("Excel (.csv)") { audioCapture.exportTranscription(selected, format: "csv") },
                                            .action("JSON (.json)") { audioCapture.exportTranscription(selected, format: "json") },
                                            .divider,
                                            .action("Субтитры (.srt)") { audioCapture.exportTranscription(selected, format: "srt") },
                                            .action("Субтитры (.vtt)") { audioCapture.exportTranscription(selected, format: "vtt") }
                                        ]) {
                                            HStack(spacing: 4) { Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .medium)); Text("Экспорт").font(UIStyleFont.body(size: 13, weight: .medium)); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.uiMidGray) }
                                            .lineLimit(1).foregroundColor(.uiInk).padding(.vertical, 8).padding(.horizontal, 14).background(Color.uiPaper).cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
                                        }.fixedSize(horizontal: true, vertical: false)
                                        UIDestructiveButton(title: "Удалить") { itemToDelete = selected.id; showingDeleteAlert = true }
                                    }.fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                                )
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .center) {
                                    dateHeader()
                                    Spacer(minLength: 12)
                                    buttonsRow()
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    dateHeader()
                                    HStack {
                                        Spacer(minLength: 0)
                                        buttonsRow()
                                    }
                                }
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
                            if isEditing {
                                ZStack(alignment: .topLeading) {
                                    EditableTextView(text: $editableText) { _ in
                                        if let id = selectedItemId { scheduleEditSave(for: id) }
                                    }
                                    if editableText.isEmpty {
                                        Text("Начните вводить текст…")
                                            .font(UIStyleFont.body(size: 15, weight: .regular))
                                            .foregroundColor(.uiMidGray.opacity(0.55))
                                            .padding(.top, 10)
                                            .padding(.leading, 5)
                                            .allowsHitTesting(false)
                                    }
                                }
                            } else if let timings = selectedTimings {
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

                                CapabilityCard(
                                    icon: "arrow.down.doc.fill",
                                    badge: String(localized: "ЛЮБОЙ ФОРМАТ"),
                                    title: "Drag & drop",
                                    description: "Перетащите медиафайл в окно — расшифровка начнётся автоматически"
                                )

                                CapabilityCard(
                                    icon: "wand.and.stars",
                                    badge: String(localized: "СВОИ ШАБЛОНЫ"),
                                    title: "Кастомные промпты",
                                    description: "Создавайте, редактируйте и удаляйте ИИ-промпты под свои задачи"
                                )

                                CapabilityCard(
                                    icon: "icloud.fill",
                                    badge: String(localized: "ОБЛАКО"),
                                    title: "Голосок+",
                                    description: "Облачные модели и расшифровка на сервере — по подписке"
                                )

                                CapabilityCard(
                                    icon: "chart.bar.fill",
                                    badge: String(localized: "СТАТИСТИКА"),
                                    title: "Дашборд",
                                    description: "Сводка по расшифровкам, активности и темпу работы за период"
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
            if isEditing, let prev = editingItemID, prev != newId {
                flushPendingEdits()
                isEditing = false
                editingItemID = nil
            }
            if let id = newId { selectedTimings = audioCapture.timings(for: id) } else { selectedTimings = nil }
        }
        .onChange(of: currentTab) { _ in
            if isEditing { flushPendingEdits(); isEditing = false; editingItemID = nil }
        }
        .sheet(item: $aiRequest) { request in
            AIResultSheet(request: request) { newID in
                withAnimation {
                    self.selectedItemId = newID
                    self.searchText = ""
                    self.selectedTimings = nil
                }
                audioCapture.markAsRead(id: newID)
            }
        }
        .sheet(isPresented: $showPromptManager) {
            PromptManagerView()
        }
        .sheet(isPresented: $showCreatePrompt) {
            PromptEditorView(prompt: nil)
        }
        .alert("Удалить запись?", isPresented: $showingDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                if let id = itemToDelete, let idx = audioCapture.history.firstIndex(where: { $0.id == id }) {
                    SoundEffect.playDelete()
                    audioCapture.stopSyncedPlayback()
                    audioCapture.deleteItem(at: idx)
                    if selectedItemId == id { selectedItemId = nil; selectedTimings = nil }
                }
            }
        } message: { Text("Это действие нельзя отменить.") }
    }

    private func loadSelectedTimings() {
        if let id = selectedItemId { selectedTimings = audioCapture.timings(for: id) }
        else { selectedTimings = nil }
    }

    // MARK: - Редактор заметок

    private func beginEditing(_ item: TranscriptionItem) {
        audioCapture.stopSyncedPlayback()
        editSaveWorkItem?.cancel()
        editSaveWorkItem = nil
        editableText = item.text
        editingItemID = item.id
        isEditing = true
    }

    private func commitEditing(for item: TranscriptionItem) {
        editSaveWorkItem?.cancel()
        editSaveWorkItem = nil
        if editableText != item.text {
            audioCapture.replaceNoteText(id: item.id, text: editableText)
        }
        editingItemID = nil
        isEditing = false
    }

    private func scheduleEditSave(for id: UUID) {
        editSaveWorkItem?.cancel()
        let snapshot = editableText
        let work = DispatchWorkItem { [weak audioCapture] in
            audioCapture?.replaceNoteText(id: id, text: snapshot)
        }
        editSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func flushPendingEdits() {
        guard isEditing, let id = editingItemID else { return }
        editSaveWorkItem?.cancel()
        editSaveWorkItem = nil
        audioCapture.replaceNoteText(id: id, text: editableText)
    }

    private func createNote() {
        if isEditing { flushPendingEdits(); isEditing = false; editingItemID = nil }
        let id = audioCapture.addNote(text: "")
        editSaveWorkItem?.cancel()
        editSaveWorkItem = nil
        withAnimation {
            searchText = ""
            selectedItemId = id
            selectedTimings = nil
        }
        audioCapture.markAsRead(id: id)
        editableText = ""
        editingItemID = id
        isEditing = true
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

struct EditToggleButton: View {
    let isEditing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isEditing ? "checkmark" : "square.and.pencil")
                    .font(.system(size: 11, weight: .medium))
                Text(isEditing ? LocalizedStringKey("Готово") : LocalizedStringKey("Редактировать"))
            }
            .lineLimit(1)
            .font(UIStyleFont.body(size: 13, weight: .medium))
            .foregroundColor(isEditing ? Color(hex: "#10B981") : .uiInk)
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Color.uiPaper).cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isEditing ? Color(hex: "#10B981").opacity(0.5) : Color.uiHairline, lineWidth: 1))
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
// СКЕЛЕТОН КАРТОЧКИ ПРИ ПОИСКЕ
struct HistorySkeletonCard: View {
    private var bar: Color { Color.uiMidGray.opacity(0.16) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(Color.blue.opacity(0.4)).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(bar).frame(width: 56, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(bar).frame(width: 30, height: 8)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3).fill(bar).frame(width: 40, height: 8)
                }
                RoundedRectangle(cornerRadius: 3).fill(bar).frame(height: 9)
                RoundedRectangle(cornerRadius: 3).fill(bar).frame(width: 180, height: 9)
            }
            .shimmer()
        }
        .padding(12)
    }
}

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
        .contentShape(Rectangle())
    }
}

struct FileDropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            LinearGradient(
                colors: [Color.blue.opacity(0.10), Color.blue.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 76, height: 76)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.blue)
                }

                VStack(spacing: 6) {
                    Text(LocalizedStringKey("Перетащите файл — начнётся расшифровка"))
                        .font(UIStyleFont.display(size: 17, weight: .bold))
                        .foregroundColor(.uiInk)
                        .multilineTextAlignment(.center)
                    Text(LocalizedStringKey("MP3, MP4, WebM, MKV, WAV и другие"))
                        .font(UIStyleFont.body(size: 12, weight: .regular))
                        .foregroundColor(.uiMidGray)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.uiPaper)
                    .shadow(color: .black.opacity(0.14), radius: 28, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundColor(Color.blue.opacity(0.55))
            )
        }
        .ignoresSafeArea()
    }
}
