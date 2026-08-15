import SwiftUI
import AppKit

// MARK: - Акцент

private extension Color {
    static let uiAccent = dynamic(light: "#6366F1", dark: "#818CF8")
}

// MARK: - Слайдер (seek-bar плеера)

struct UISeekSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    @State private var isHover = false

    private var fraction: CGFloat {
        let span = max(1e-6, range.upperBound - range.lowerBound)
        let f = (value - range.lowerBound) / span
        return CGFloat(min(1.0, max(0.0, f)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knobD: CGFloat = 12
            let knobX = max(0, min(w - knobD, (w - knobD) * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.uiHairline).frame(height: 4)
                Capsule().fill(Color.uiAccent).frame(width: max(0, w * fraction), height: 4)
                Circle()
                    .fill(Color.uiPaper)
                    .overlay(Circle().stroke(Color.uiAccent.opacity(0.35), lineWidth: 1))
                    .frame(width: knobD, height: knobD)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .scaleEffect(isHover ? 1.15 : 1.0)
                    .offset(x: knobX)
                    .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isHover)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .onHover { isHover = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let span = max(1e-6, range.upperBound - range.lowerBound)
                        let f = min(1.0, max(0.0, Double(g.location.x / w)))
                        value = range.lowerBound + f * span
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - Сегмент-контрол

struct UISegment<Value: Hashable> {
    let text: Text
    let value: Value
}

struct UISegmented<Value: Hashable>: View {
    let segments: [UISegment<Value>]
    @Binding var selection: Value
    @Namespace private var ns

    init(selection: Binding<Value>, segments: [UISegment<Value>]) {
        self._selection = selection
        self.segments = segments
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments.indices, id: \.self) { i in
                let s = segments[i]
                let active = s.value == selection
                Button {
                    selection = s.value
                } label: {
                    s.text
                        .font(UIStyleFont.body(size: 12, weight: active ? .semibold : .medium))
                        .foregroundColor(active ? .uiInk : .uiMidGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                if active {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.uiPaper)
                                        .matchedGeometryEffect(id: "uiseg", in: ns)
                                        .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: active)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.uiCanvas))
        .overlay(Capsule().stroke(Color.uiHairline, lineWidth: 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}

// MARK: - Опции дропдауна

struct UIDropdownOption<Value: Hashable> {
    let text: Text
    var icon: String? = nil
    let value: Value

    init(_ key: LocalizedStringKey, icon: String? = nil, value: Value) {
        self.text = Text(key); self.icon = icon; self.value = value
    }
    init<S: StringProtocol>(_ title: S, icon: String? = nil, value: Value) {
        self.text = Text(title); self.icon = icon; self.value = value
    }
}

enum UIDropdownItem {
    case action(text: Text, icon: String?, handler: () -> Void)
    case divider

    static func action(_ key: LocalizedStringKey, icon: String? = nil, handler: @escaping () -> Void) -> UIDropdownItem {
        .action(text: Text(key), icon: icon, handler: handler)
    }
    static func action<S: StringProtocol>(_ title: S, icon: String? = nil, handler: @escaping () -> Void) -> UIDropdownItem {
        .action(text: Text(title), icon: icon, handler: handler)
    }
}

// MARK: - Внутреннее представление строк поповера

private struct DropdownRow {
    let text: Text
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void
    let isDivider: Bool
}

private struct DropdownList: View {
    let width: CGFloat
    let rows: [DropdownRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                if r.isDivider {
                    Divider().padding(.horizontal, 10).padding(.vertical, 4)
                } else {
                    DropdownRowView(row: r)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.uiPaper))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.uiHairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DropdownRowView: View {
    let row: DropdownRow
    @State private var hover = false

    var body: some View {
        Button {
            row.onTap()
        } label: {
            HStack(spacing: 10) {
                if let icon = row.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.uiMidGray)
                        .frame(width: 16)
                }
                row.text
                    .font(UIStyleFont.body(size: 13, weight: .medium))
                    .foregroundColor(.uiInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if row.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.uiAccent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(hover ? Color.uiCanvas : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Presenter (borderless NSPanel)

private final class DropdownPresenter {
    static let shared = DropdownPresenter()
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var localClick: Any?
    private var globalClick: Any?
    private var keyMonitor: Any?
    private var onClose: (() -> Void)?

    func present(anchorView: NSView?, content: AnyView, contentWidth: CGFloat, onClose: @escaping () -> Void) {
        close()
        self.onClose = onClose

        let pw = max(160, contentWidth)
        let controller = NSHostingController(rootView: content)
        let measured = controller.sizeThatFits(in: NSSize(width: pw, height: .greatestFiniteMagnitude))
        let ph = max(measured.height, 8)
        controller.view.frame = NSRect(x: 0, y: 0, width: pw, height: ph)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingController = controller

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: pw, height: ph),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = controller.view

        var origin = NSPoint(x: 0, y: 0)
        if let a = anchorView, let win = a.window {
            let wb = a.convert(a.bounds, to: nil)
            let sr = win.convertToScreen(wb)
            let visible = (win.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            var oy = sr.minY - ph - 4
            if oy < visible.minY { oy = sr.maxY + 4 }
            var ox = sr.minX
            if ox + pw > visible.maxX { ox = visible.maxX - pw }
            if ox < visible.minX { ox = visible.minX }
            origin = NSPoint(x: ox, y: oy)
        }
        panel.setFrameOrigin(origin)

        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    private func installMonitors() {
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel { return event }
            self.close()
            return event
        }
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close() }
            return event
        }
    }

    private func removeMonitors() {
        [localClick, globalClick, keyMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        localClick = nil; globalClick = nil; keyMonitor = nil
    }

    func close() {
        guard let panel else { return }
        removeMonitors()
        let p = panel
        let closure = onClose
        self.panel = nil
        self.hostingController = nil
        self.onClose = nil
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.1
            p.animator().alphaValue = 0
        }) {
            p.orderOut(nil)
        }
        closure?()
    }
}

// MARK: - Якорь (захват NSView триггера для позиционирования панели)

private struct AnchorRepresentable: NSViewRepresentable {
    @Binding var view: NSView?
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}

// MARK: - Дропдаун-пикер (замена Picker(.menu))

struct UIDropdownPicker<Value: Hashable>: View {
    let options: [UIDropdownOption<Value>]
    @Binding var selection: Value
    var width: CGFloat? = nil
    var fullWidth: Bool = false
    var minWidth: CGFloat = 180

    init(selection: Binding<Value>, options: [UIDropdownOption<Value>], width: CGFloat? = nil, fullWidth: Bool = false, minWidth: CGFloat = 180) {
        self._selection = selection
        self.options = options
        self.width = width
        self.fullWidth = fullWidth
        self.minWidth = minWidth
    }

    @State private var anchorView: NSView?
    @State private var isOpen = false
    @State private var suppressOpen = false

    private var expands: Bool { width != nil || fullWidth }
    private var selected: UIDropdownOption<Value>? { options.first(where: { $0.value == selection }) }

    var body: some View {
        Button {
            if isOpen { closeAction() } else { openAction() }
        } label: { triggerLabel }
        .buttonStyle(TactileButtonStyle())
        .disabled(options.isEmpty)
        .background(AnchorRepresentable(view: $anchorView))
        .frame(width: width)
        .frame(maxWidth: fullWidth ? .greatestFiniteMagnitude : nil)
    }

    private var triggerLabel: some View {
        Group {
            if expands {
                HStack(spacing: 6) {
                    selectedText.foregroundColor(.uiInk)
                    Spacer(minLength: 6)
                    chevron
                }
            } else {
                HStack(spacing: 6) {
                    selectedText.foregroundColor(.uiInk)
                    chevron
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(UIStyleFont.body(size: 13, weight: .medium))
        .foregroundColor(.uiInk)
        .lineLimit(1)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Color.uiPaper).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.uiHairline, lineWidth: 1))
    }

    private var selectedText: Text { selected?.text ?? Text("") }
    private var chevron: some View {
        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.uiMidGray)
    }

    private func openAction() {
        guard !suppressOpen else { suppressOpen = false; return }
        guard let anchorView else { return }
        isOpen = true
        let pw = max(minWidth, anchorView.bounds.width)
        let rows = options.map { o in
            DropdownRow(text: o.text, icon: o.icon, isSelected: o.value == selection,
                        onTap: { selection = o.value; closeAction() }, isDivider: false)
        }
        let content = AnyView(DropdownList(width: pw, rows: rows))
        DropdownPresenter.shared.present(anchorView: anchorView, content: content, contentWidth: pw) { [self] in
            isOpen = false
            suppressOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { suppressOpen = false }
        }
    }

    private func closeAction() { DropdownPresenter.shared.close() }
}

// MARK: - Дропдаун-меню действий (замена Menu)

struct UIDropdownMenu<Trigger: View>: View {
    let trigger: Trigger
    let items: [UIDropdownItem]
    var minWidth: CGFloat = 220

    @State private var anchorView: NSView?
    @State private var isOpen = false
    @State private var suppressOpen = false

    init(items: [UIDropdownItem], minWidth: CGFloat = 220, @ViewBuilder trigger: () -> Trigger) {
        self.items = items
        self.minWidth = minWidth
        self.trigger = trigger()
    }

    var body: some View {
        Button {
            if isOpen { closeAction() } else { openAction() }
        } label: { trigger }
        .buttonStyle(TactileButtonStyle())
        .background(AnchorRepresentable(view: $anchorView))
    }

    private func openAction() {
        guard !suppressOpen else { suppressOpen = false; return }
        guard let anchorView else { return }
        isOpen = true
        let pw = max(minWidth, anchorView.bounds.width)
        var rows: [DropdownRow] = []
        for item in items {
            switch item {
            case .divider:
                rows.append(DropdownRow(text: Text(""), icon: nil, isSelected: false, onTap: {}, isDivider: true))
            case let .action(text, icon, handler):
                rows.append(DropdownRow(text: text, icon: icon, isSelected: false,
                                        onTap: { handler(); closeAction() }, isDivider: false))
            }
        }
        let content = AnyView(DropdownList(width: pw, rows: rows))
        DropdownPresenter.shared.present(anchorView: anchorView, content: content, contentWidth: pw) { [self] in
            isOpen = false
            suppressOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { suppressOpen = false }
        }
    }

    private func closeAction() { DropdownPresenter.shared.close() }
}