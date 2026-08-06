import Foundation
import Carbon
import AppKit

class NativeHotKeyManager {
    static let shared = NativeHotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onHotKeyPressed: (() -> Void)?

    private init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            NativeHotKeyManager.shared.onHotKeyPressed?()
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    func registerOptionSpace() {
        unregister()

        let hotKeyID = EventHotKeyID(signature: OSType(0x474C534B), id: 1)
        let spaceKeyCode: UInt32 = 49
        let optionModifier: UInt32 = UInt32(optionKey)

        let status = RegisterEventHotKey(spaceKeyCode, optionModifier, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("[HotKey] RegisterEventHotKey failed with status %d", status)
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }
}
