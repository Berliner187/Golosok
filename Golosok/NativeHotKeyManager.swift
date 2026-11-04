import Foundation
import Carbon
import AppKit

enum HotKeyKey: String {
    case space = "space"
    case command = "command"
}

enum HotKeyMode: String, CaseIterable, Identifiable {
    case toggle = "toggle"
    case pushToTalk = "pushToTalk"
    var id: String { rawValue }
}

class NativeHotKeyManager {
    static let shared = NativeHotKeyManager()

    // MARK: - Хоткей диктовки (id: 1)
    private var hotKeyRef: EventHotKeyRef?
    var onHotKeyPressed: (() -> Void)?
    var onHotKeyReleased: (() -> Void)?

    // MARK: - Хоткей ИИ-обработки выделенного текста (id: 2)
    private var selectionHotKeyRef: EventHotKeyRef?
    var onSelectionHotKeyPressed: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?

    private init() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, _) -> OSStatus in
            guard let eventRef else { return noErr }

            // Извлекаем идентификатор зарегистрированного хоткея
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }

            switch hotKeyID.id {
            case 1:
                // События диктовки (нажатие / отпускание для push-to-talk)
                switch GetEventKind(eventRef) {
                case UInt32(kEventHotKeyPressed): NativeHotKeyManager.shared.onHotKeyPressed?()
                case UInt32(kEventHotKeyReleased): NativeHotKeyManager.shared.onHotKeyReleased?()
                default: break
                }
            case 2:
                // Событие трансформации выделения ИИ (срабатывает по нажатию)
                if GetEventKind(eventRef) == UInt32(kEventHotKeyPressed) {
                    NativeHotKeyManager.shared.onSelectionHotKeyPressed?()
                }
            default:
                break
            }
            return noErr
        }, 2, &eventTypes, nil, &eventHandlerRef)
    }

    // MARK: - Настройки клавиш диктовки
    var keyCode: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "hotkey.keyCode")) == 0 ? 49 : UInt32(UserDefaults.standard.integer(forKey: "hotkey.keyCode")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "hotkey.keyCode") }
    }

    var modifierFlags: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "hotkey.modifiers")) == 0 ? UInt32(optionKey) : UInt32(UserDefaults.standard.integer(forKey: "hotkey.modifiers")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "hotkey.modifiers") }
    }

    var mode: HotKeyMode {
        get { HotKeyMode(rawValue: UserDefaults.standard.string(forKey: "hotkey.mode") ?? "") ?? .toggle }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hotkey.mode") }
    }

    // MARK: - Настройки клавиш ИИ-обработки выделения (по умолчанию ⌥ + ⇧ + Space)
    var selectionKeyCode: UInt32 {
        get {
            let val = UInt32(UserDefaults.standard.integer(forKey: "hotkey.selection.keyCode"))
            return val == 0 ? 49 : val
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "hotkey.selection.keyCode") }
    }

    var selectionModifierFlags: UInt32 {
        get {
            let val = UInt32(UserDefaults.standard.integer(forKey: "hotkey.selection.modifiers"))
            return val == 0 ? UInt32(optionKey | shiftKey) : val
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "hotkey.selection.modifiers") }
    }

    func register() {
        unregister()

        // 1. Регистрация хоткея диктовки
        let dictationID = EventHotKeyID(signature: OSType(0x474C534B), id: 1)
        let status1 = RegisterEventHotKey(keyCode, modifierFlags, dictationID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status1 != noErr {
            AppLogger.shared.error("HotKey", "Не удалось зарегистрировать горячую клавишу диктовки", details: "status \(status1), комбинация \(displayName())")
            Telemetry.shared.event("hotkey_register_failed", ["error_detail": "dictation_status_\(status1)"])
        } else {
            AppLogger.shared.info("HotKey", "Горячая клавиша диктовки зарегистрирована", details: displayName())
        }

        // 2. Регистрация хоткея ИИ-обработки выделения
        let selectionID = EventHotKeyID(signature: OSType(0x474C534B), id: 2)
        let status2 = RegisterEventHotKey(selectionKeyCode, selectionModifierFlags, selectionID, GetApplicationEventTarget(), 0, &selectionHotKeyRef)
        if status2 != noErr {
            AppLogger.shared.error("HotKey", "Не удалось зарегистрировать горячую клавишу ИИ-обработки", details: "status \(status2), комбинация \(selectionDisplayName())")
            Telemetry.shared.event("hotkey_register_failed", ["error_detail": "selection_status_\(status2)"])
        } else {
            AppLogger.shared.info("HotKey", "Горячая клавиша ИИ-обработки зарегистрирована", details: selectionDisplayName())
        }
    }

    func setHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C534B), id: 1)
        var testRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &testRef)
        if status != noErr { return false }
        UnregisterEventHotKey(testRef!)
        self.keyCode = keyCode
        self.modifierFlags = modifiers
        register()
        return true
    }

    func setSelectionHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x474C534B), id: 2)
        var testRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &testRef)
        if status != noErr { return false }
        UnregisterEventHotKey(testRef!)
        self.selectionKeyCode = keyCode
        self.selectionModifierFlags = modifiers
        register()
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = selectionHotKeyRef {
            UnregisterEventHotKey(ref)
            selectionHotKeyRef = nil
        }
    }

    func displayName() -> String {
        formatName(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    func selectionDisplayName() -> String {
        formatName(keyCode: selectionKeyCode, modifierFlags: selectionModifierFlags)
    }

    private func formatName(keyCode: UInt32, modifierFlags: UInt32) -> String {
        let mods = modifierFlags
        var prefix = ""
        if mods & UInt32(controlKey) != 0 { prefix += "⌃" }
        if mods & UInt32(optionKey) != 0 { prefix += "⌥" }
        if mods & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if mods & UInt32(cmdKey) != 0 { prefix += "⌘" }
        return prefix.isEmpty ? keyName(keyCode) : "\(prefix) + \(keyName(keyCode))"
    }

    private func keyName(_ keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            49: "Space", 48: "Tab", 51: "⌫", 53: "⎋", 36: "↩", 76: "⏎",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: "."
        ]
        return special[keyCode] ?? String(format: "K%u", keyCode)
    }

    deinit {
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }
}