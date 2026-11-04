import SwiftUI
import AppKit

// MARK: - Состояние навигации палитры

final class AISelectionToolbarState: ObservableObject {
    @Published var selectedIndex: Int = 0
}

// MARK: - Контент мини-тулбара

struct AISelectionToolbarContent: View {
    let templates: [AIPromptTemplate]
    @ObservedObject var state: AISelectionToolbarState
    let onPick: (AIPromptTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.uiAccent)
                Text(LocalizedStringKey("AI-действия с выделением"))
                    .font(UIStyleFont.body(size: 11, weight: .semibold))
                    .foregroundColor(.uiInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.uiMidGray)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 5)
                    .background(Color.uiCanvas)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.uiHairline, lineWidth: 1))
                    .help(String(localized: "Только выделенный фрагмент"))
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 7)

            Divider().background(Color.uiHairline)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { idx, t in
                            AISelectionToolbarRow(
                                index: idx,
                                isSelected: state.selectedIndex == idx,
                                template: t
                            ) {
                                state.selectedIndex = idx
                                onPick(t)
                            }
                            .id(idx)
                            if idx < templates.count - 1 {
                                Divider().background(Color.uiHairline).padding(.horizontal, 10)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: state.selectedIndex) { newIdx in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.uiPaper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.uiHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
    }
}

private struct AISelectionToolbarRow: View {
    let index: Int
    let isSelected: Bool
    let template: AIPromptTemplate
    let onPick: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? Color.uiInk : Color.uiAccent.opacity(0.85))
                    .frame(width: 16)
                Text(LocalizedStringKey(template.title))
                    .font(UIStyleFont.body(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(.uiInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? Color.uiInk : .uiMidGray)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.uiPaper : Color.uiCanvas)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.uiHairline, lineWidth: 1))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.uiAccent.opacity(0.6))
                    .opacity(isSelected || hover ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isSelected ? Color.uiCanvas : (hover ? Color.uiCanvas.opacity(0.6) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.uiAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .onHover { hover = $0 }
    }
}

// MARK: - Presenter (плавающая NSPanel над выделением)

final class KeyableSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AISelectionToolbarPresenter {
    static let shared = AISelectionToolbarPresenter()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AISelectionToolbarContent>?
    private var state: AISelectionToolbarState?
    private var localClick: Any?
    private var globalClick: Any?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onClose: (() -> Void)?

    func present(anchorScreenRect: CGRect,
                 templates: [AIPromptTemplate],
                 onPick: @escaping (AIPromptTemplate) -> Void,
                 onClose: @escaping () -> Void) {
        close()
        self.onClose = onClose

        let toolbarState = AISelectionToolbarState()
        self.state = toolbarState

        let content = AISelectionToolbarContent(templates: templates, state: toolbarState) { tpl in
            onPick(tpl)
            AISelectionToolbarPresenter.shared.close()
        }

        let controller = NSHostingController(rootView: content)
        let width: CGFloat = 260
        let targetScreen = Self.screenContaining(anchorScreenRect)
        let screenHeight = targetScreen?.visibleFrame.height ?? 800
        let maxAllowedHeight = min(620, screenHeight * 0.75)
        let naturalHeight = CGFloat(46 + templates.count * 31)
        let height = min(maxAllowedHeight, max(140, naturalHeight))

        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController = controller

        let p = KeyableSelectionPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = NSColor.clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.level = .screenSaver
        p.isFloatingPanel = true
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = controller.view

        let origin = Self.computeOrigin(anchorScreenRect: anchorScreenRect,
                                        panelSize: NSSize(width: width, height: height))
        p.setFrameOrigin(origin)

        panel = p
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 1
        }

        installMonitors(templates: templates, onPick: onPick)
    }

    /// Универсальный апдейт: либо открывает панель при первом выделении,
    /// либо мягко смещает её при изменении прямоугольника выделения,
    /// либо закрывает, если `anchorScreenRect == nil`.
    func update(anchorScreenRect: CGRect?,
                templates: [AIPromptTemplate],
                onPick: @escaping (AIPromptTemplate) -> Void,
                onClose: @escaping () -> Void) {
        guard let rect = anchorScreenRect else {
            close()
            return
        }
        if panel != nil {
            reposition(to: rect)
            return
        }
        present(anchorScreenRect: rect, templates: templates, onPick: onPick, onClose: onClose)
    }

    func reposition(to anchorScreenRect: CGRect) {
        guard let panel, let view = panel.contentView else { return }
        let size = view.bounds.size
        let origin = Self.computeOrigin(anchorScreenRect: anchorScreenRect, panelSize: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(origin)
        }
    }

    func close() {
        guard let panel else { return }
        removeMonitors()
        let p = panel
        let closure = onClose
        self.panel = nil
        self.hostingController = nil
        self.state = nil
        self.onClose = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            p.animator().alphaValue = 0
        }) {
            p.orderOut(nil)
        }
        closure?()
    }

    var isPresented: Bool { panel != nil }

    private static func computeOrigin(anchorScreenRect: CGRect, panelSize: NSSize) -> NSPoint {
        let visible: CGRect
        if let screen = screenContaining(anchorScreenRect) {
            visible = screen.visibleFrame
        } else {
            visible = NSScreen.main?.visibleFrame ?? .zero
        }
        let pw = panelSize.width
        let ph = panelSize.height

        // Сначала пробуем расположить toolbar над выделением с 6pt просветом.
        var ox = anchorScreenRect.midX - pw / 2
        var oy = anchorScreenRect.maxY + 6
        if oy + ph > visible.maxY {
            // Не помещается вверху — опускаем под выделение.
            oy = anchorScreenRect.minY - ph - 6
        }
        if oy < visible.minY {
            // Никак не помещается ни сверху, ни снизу — прижимаем к доступной области.
            oy = max(visible.minY, min(anchorScreenRect.maxY + 6, visible.maxY - ph))
        }
        if ox < visible.minX { ox = visible.minX }
        if ox + pw > visible.maxX { ox = visible.maxX - pw }
        return NSPoint(x: ox, y: oy)
    }

    private static func screenContaining(_ rect: CGRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        for screen in NSScreen.screens {
            if screen.frame.contains(center) { return screen }
        }
        for screen in NSScreen.screens {
            if screen.frame.intersects(rect) { return screen }
        }
        return NSScreen.main
    }

    private func installMonitors(templates: [AIPromptTemplate], onPick: @escaping (AIPromptTemplate) -> Void) {
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel { return event }
            self.close()
            return event
        }
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state else { return event }

            switch event.keyCode {
            case 53: // Esc
                self.close()
                return nil

            case 126: // Up Arrow
                guard !templates.isEmpty else { return nil }
                state.selectedIndex = (state.selectedIndex - 1 + templates.count) % templates.count
                return nil

            case 125: // Down Arrow
                guard !templates.isEmpty else { return nil }
                state.selectedIndex = (state.selectedIndex + 1) % templates.count
                return nil

            case 36, 76: // Enter / Return
                if state.selectedIndex >= 0 && state.selectedIndex < templates.count {
                    let selected = templates[state.selectedIndex]
                    DispatchQueue.main.async {
                        self.close()
                        onPick(selected)
                    }
                }
                return nil

            default:
                if let char = event.characters?.first, let digit = char.wholeNumberValue {
                    let targetIndex: Int? = (digit >= 1 && digit <= 9) ? (digit - 1) : (digit == 0 ? 9 : nil)
                    if let idx = targetIndex, idx < templates.count {
                        let t = templates[idx]
                        DispatchQueue.main.async {
                            self.close()
                            onPick(t)
                        }
                        return nil
                    }
                }
                return event
            }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state, !templates.isEmpty else { return }

            switch event.keyCode {
            case 53: // Esc
                self.close()

            case 126: // Up Arrow
                DispatchQueue.main.async {
                    state.selectedIndex = (state.selectedIndex - 1 + templates.count) % templates.count
                }

            case 125: // Down Arrow
                DispatchQueue.main.async {
                    state.selectedIndex = (state.selectedIndex + 1) % templates.count
                }

            case 36, 76: // Enter / Return
                if state.selectedIndex >= 0 && state.selectedIndex < templates.count {
                    let selected = templates[state.selectedIndex]
                    DispatchQueue.main.async {
                        self.close()
                        onPick(selected)
                    }
                }

            default:
                if let char = event.characters?.first, let digit = char.wholeNumberValue {
                    let targetIndex: Int? = (digit >= 1 && digit <= 9) ? (digit - 1) : (digit == 0 ? 9 : nil)
                    if let idx = targetIndex, idx < templates.count {
                        let t = templates[idx]
                        DispatchQueue.main.async {
                            self.close()
                            onPick(t)
                        }
                    }
                }
            }
        }
    }

    private func removeMonitors() {
        [localClick, globalClick, keyMonitor, globalKeyMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        localClick = nil; globalClick = nil; keyMonitor = nil; globalKeyMonitor = nil
    }
}