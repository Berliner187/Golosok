import SwiftUI
@preconcurrency import AppKit
import Carbon
import Observation

@MainActor
@Observable
final class HotKeySettings {
    static let shared = HotKeySettings()

    var mode: HotKeyMode {
        didSet { NativeHotKeyManager.shared.mode = mode }
    }
    var hotKeyName: String = ""
    var isCapturing = false
    var isTaken = false

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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = UInt32(event.keyCode)
            let modifiers = self.carbonModifiers(from: event.modifierFlags)
            // NSEvent local monitors fire on the main run loop, so only
            // Sendable primitives cross the isolation boundary.
            let consume = MainActor.assumeIsolated {
                self.handleCaptureEvent(keyCode: keyCode, modifiers: modifiers, isEscape: event.keyCode == 53)
            }
            return consume ? nil : event
        }
    }

    /// - Returns: `true` if the event was consumed as a new hotkey.
    private func handleCaptureEvent(keyCode: UInt32, modifiers: UInt32?, isEscape: Bool) -> Bool {
        if isEscape {
            endCapture()
            return false
        }
        guard let carbon = modifiers else { return false }
        let succeeded = sameAsCurrent(keyCode: keyCode, carbon: carbon)
            || NativeHotKeyManager.shared.setHotKey(keyCode: keyCode, modifiers: carbon)
        isTaken = !succeeded
        if succeeded { refreshName() }
        endCapture()
        return succeeded
    }

    private func sameAsCurrent(keyCode: UInt32, carbon: UInt32) -> Bool {
        NativeHotKeyManager.shared.keyCode == keyCode && NativeHotKeyManager.shared.modifierFlags == carbon
    }

    private nonisolated func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32? {
        let allowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let mods = flags.intersection(allowed)
        guard !mods.isEmpty else { return nil }
        var value: UInt32 = 0
        if mods.contains(.control) { value |= UInt32(controlKey) }
        if mods.contains(.option) { value |= UInt32(optionKey) }
        if mods.contains(.shift) { value |= UInt32(shiftKey) }
        if mods.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    func endCapture() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        isCapturing = false
    }
}
