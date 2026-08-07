import SwiftUI
import AppKit
import Carbon

final class HotKeySettings: ObservableObject {
    static let shared = HotKeySettings()

    @Published var mode: HotKeyMode {
        didSet { NativeHotKeyManager.shared.mode = mode }
    }
    @Published var hotKeyName: String = ""
    @Published var isCapturing = false
    @Published var isTaken = false

    private var monitor: Any?

    private init() {
        mode = NativeHotKeyManager.shared.mode
        hotKeyName = NativeHotKeyManager.shared.displayName()
    }

    func refreshName() {
        hotKeyName = NativeHotKeyManager.shared.displayName()
    }

    func reset() {
        _ = NativeHotKeyManager.shared.setHotKey(keyCode: 49, modifiers: UInt32(optionKey))
        refreshName()
    }

    func beginCapture() {
        guard !isCapturing else { return }
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

    private func sameAsCurrent(keyCode: UInt32, carbon: UInt32) -> Bool {
        NativeHotKeyManager.shared.keyCode == keyCode && NativeHotKeyManager.shared.modifierFlags == carbon
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32? {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    func endCapture() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        isCapturing = false
    }
}