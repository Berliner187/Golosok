import Foundation
import Carbon
import AppKit

class NativeHotKeyManager {
    static let shared = NativeHotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    var onHotKeyPressed: (() -> Void)?
    
    func registerOptionSpace() {
        unregister()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(32)
        hotKeyID.id = UInt32(1)
        
        let spaceKeyCode: UInt32 = 49
        let optionModifier: UInt32 = UInt32(optionKey)
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            NativeHotKeyManager.shared.onHotKeyPressed?()
            return noErr
        }, 1, &eventType, nil, nil)
        
        RegisterEventHotKey(spaceKeyCode, optionModifier, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
