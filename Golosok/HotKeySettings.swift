import SwiftUI
import AppKit
import Carbon

final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()

    // MARK: - Диктовка
    @Published var mode: HotKeyMode {
        didSet { NativeHotKeyManager.shared.mode = mode }
    }
    @Published var hotKeyName: String = ""
    @Published var isCapturing = false
    @Published var isTaken = false

    // MARK: - ИИ-обработка выделения
    @Published var selectionHotKeyName: String = ""
    @Published var isCapturingSelection = false
    @Published var isSelectionTaken = false

    private var monitor: Any?
    private var selectionMonitor: Any?

    private init() {
        mode = NativeHotKeyManager.shared.mode
        hotKeyName = NativeHotKeyManager.shared.displayName()
        selectionHotKeyName = NativeHotKeyManager.shared.selectionDisplayName()
    }

    func refreshName() {
        hotKeyName = NativeHotKeyManager.shared.displayName()
        selectionHotKeyName = NativeHotKeyManager.shared.selectionDisplayName()
    }

    func reset() {
        _ = NativeHotKeyManager.shared.setHotKey(keyCode: 49, modifiers: UInt32(optionKey))
        refreshName()
    }

    func resetSelection() {
        _ = NativeHotKeyManager.shared.setSelectionHotKey(keyCode: 49, modifiers: UInt32(optionKey | shiftKey))
        refreshName()
    }

    // MARK: - Захват клавиш диктовки
    func beginCapture() {
        guard !isCapturing else { return }
        if isCapturingSelection { endCaptureSelection() }
        isCapturing = true
        isTaken = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                self.endCapture()
                return event
            }
            let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            let mods = event.modifierFlags.intersection(allowed)
            guard !mods.isEmpty, let carbon = self.carbonModifiers(from: mods) else {
                return event
            }
            let keyCode = UInt32(event.keyCode)
            let succeeded = self.sameAsCurrent(keyCode: keyCode, carbon: carbon)
                || NativeHotKeyManager.shared.setHotKey(keyCode: keyCode, modifiers: carbon)
            self.isTaken = !succeeded
            if succeeded { self.refreshName() }
            self.endCapture()
            return nil
        }
    }

    func endCapture() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        isCapturing = false
    }

    // MARK: - Захват клавиш ИИ-обработки выделения
    func beginCaptureSelection() {
        guard !isCapturingSelection else { return }
        if isCapturing { endCapture() }
        isCapturingSelection = true
        isSelectionTaken = false
        selectionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                self.endCaptureSelection()
                return event
            }
            let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            let mods = event.modifierFlags.intersection(allowed)
            guard !mods.isEmpty, let carbon = self.carbonModifiers(from: mods) else {
                return event
            }
            let keyCode = UInt32(event.keyCode)
            let succeeded = self.sameAsCurrentSelection(keyCode: keyCode, carbon: carbon)
                || NativeHotKeyManager.shared.setSelectionHotKey(keyCode: keyCode, modifiers: carbon)
            self.isSelectionTaken = !succeeded
            if succeeded { self.refreshName() }
            self.endCaptureSelection()
            return nil
        }
    }

    func endCaptureSelection() {
        if let m = selectionMonitor { NSEvent.removeMonitor(m); selectionMonitor = nil }
        isCapturingSelection = false
    }

    private func sameAsCurrent(keyCode: UInt32, carbon: UInt32) -> Bool {
        NativeHotKeyManager.shared.keyCode == keyCode && NativeHotKeyManager.shared.modifierFlags == carbon
    }

    private func sameAsCurrentSelection(keyCode: UInt32, carbon: UInt32) -> Bool {
        NativeHotKeyManager.shared.selectionKeyCode == keyCode && NativeHotKeyManager.shared.selectionModifierFlags == carbon
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32? {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }
}