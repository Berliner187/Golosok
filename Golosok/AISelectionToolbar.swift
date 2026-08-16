import SwiftUI
import AppKit

// MARK: - Контент мини-тулбара

struct AISelectionToolbarContent: View {
    let templates: [AIPromptTemplate]
    let onPick: (AIPromptTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.uiAccent)
                Text("AI-действия с выделением")
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

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(templates.enumerated()), id: \.element.id) { idx, t in
                        AISelectionToolbarRow(template: t) { onPick(t) }
                        if idx < templates.count - 1 {
                            Divider().background(Color.uiHairline).padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.vertical, 6)
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
    let template: AIPromptTemplate
    let onPick: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.uiAccent.opacity(0.85))
                    .frame(width: 16)
                Text(LocalizedStringKey(template.title))
                    .font(UIStyleFont.body(size: 12, weight: .medium))
                    .foregroundColor(.uiInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.uiAccent.opacity(0.6))
                    .opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hover ? Color.uiCanvas : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .onHover { hover = $0 }
    }
}

// MARK: - Presenter (плавающая NSPanel над выделением)

final class AISelectionToolbarPresenter {
    static let shared = AISelectionToolbarPresenter()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AISelectionToolbarContent>?
    private var localClick: Any?
    private var globalClick: Any?
    private var keyMonitor: Any?
    private var onClose: (() -> Void)?

    func present(anchorScreenRect: CGRect,
                 templates: [AIPromptTemplate],
                 onPick: @escaping (AIPromptTemplate) -> Void,
                 onClose: @escaping () -> Void) {
        close()
        self.onClose = onClose

        let content = AISelectionToolbarContent(templates: templates) { tpl in
            onPick(tpl)
            AISelectionToolbarPresenter.shared.close()
        }

        let controller = NSHostingController(rootView: content)
        let measured = controller.sizeThatFits(in: NSSize(width: 260, height: CGFloat.greatestFiniteMagnitude))
        let width: CGFloat = max(220, min(320, measured.width))
        let height: CGFloat = min(360, max(140, measured.height))

        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController = controller

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = NSColor.clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.isFloatingPanel = true
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = controller.view

        let origin = Self.computeOrigin(anchorScreenRect: anchorScreenRect,
                                        panelSize: NSSize(width: width, height: height))
        p.setFrameOrigin(origin)

        panel = p
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 1
        }

        installMonitors()
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

        // Сначала пробуем расположить-toolbar над выделением с 6pt просветом.
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

    private func installMonitors() {
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
            if event.keyCode == 53 { self?.close() }
            return event
        }
    }

    private func removeMonitors() {
        [localClick, globalClick, keyMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        localClick = nil; globalClick = nil; keyMonitor = nil
    }
}