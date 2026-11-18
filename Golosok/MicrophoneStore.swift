import Foundation
import AVFoundation
import CoreAudio

// MARK: - Режим выбора микрофона

enum MicrophoneMode: String, CaseIterable {
    case systemDefault
    case macBuiltInNoBluetooth
    case specific
}

// MARK: - Хранилище микрофонов

final class MicrophoneStore: ObservableObject {
    static let shared = MicrophoneStore()

    @Published var mode: MicrophoneMode = MicrophoneMode(rawValue: UserDefaults.standard.string(forKey: "micMode") ?? "") ?? .systemDefault {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "micMode") }
    }

    @Published var specificDeviceUID: String = UserDefaults.standard.string(forKey: "micSpecificDeviceUID") ?? "" {
        didSet { UserDefaults.standard.set(specificDeviceUID, forKey: "micSpecificDeviceUID") }
    }

    @Published private(set) var devices: [AVCaptureDevice] = []

    private init() {
        refreshDevices()
        NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDevices()
        }
        NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    func refreshDevices() {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .externalUnknown], mediaType: .audio, position: .unspecified)
        devices = session.devices
    }

    // MARK: CoreAudio: transport type и UID (совпадает с AVCaptureDevice.uniqueID)

    static func transportType(forDeviceUID uid: String) -> UInt32? {
        guard let deviceID = coreAudioDeviceID(forUID: uid) else { return nil }
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &prop, 0, nil, &size, &transport) == noErr else { return nil }
        return transport
    }

    static func isBluetoothDevice(uid: String) -> Bool {
        guard let transport = transportType(forDeviceUID: uid) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func isBuiltInDevice(uid: String) -> Bool {
        transportType(forDeviceUID: uid) == kAudioDeviceTransportTypeBuiltIn
    }

    static func defaultInputDeviceUID() -> String? {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size, &deviceID) == noErr else { return nil }
        return coreAudioDeviceUID(forID: deviceID)
    }

    // MARK: Умный режим (чистая функция — пригодна для юнит-тестов)

    static func smartModeDeviceUID(defaultUID: String, defaultIsBluetooth: Bool, builtInUID: String?) -> String {
        if defaultIsBluetooth, let builtInUID, !builtInUID.isEmpty { return builtInUID }
        return defaultUID
    }

    // MARK: Разрешение устройства для записи

    func resolveDevice() -> AVCaptureDevice? {
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        switch mode {
        case .systemDefault:
            return defaultDevice
        case .macBuiltInNoBluetooth:
            guard let defaultDevice else { return nil }
            if Self.isBluetoothDevice(uid: defaultDevice.uniqueID) {
                let uid = Self.smartModeDeviceUID(
                    defaultUID: defaultDevice.uniqueID,
                    defaultIsBluetooth: true,
                    builtInUID: devices.first { Self.isBuiltInDevice(uid: $0.uniqueID) }?.uniqueID
                )
                return devices.first { $0.uniqueID == uid } ?? defaultDevice
            }
            return defaultDevice
        case .specific:
            guard !specificDeviceUID.isEmpty else { return defaultDevice }
            guard let device = devices.first(where: { $0.uniqueID == specificDeviceUID }) else {
                AppLogger.shared.warn("Microphone", "Выбранное устройство недоступно — фолбэк на системное", details: specificDeviceUID)
                return defaultDevice
            }
            return device
        }
    }

    // MARK: CoreAudio helpers

    private static func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        for id in coreAudioDeviceList() where coreAudioDeviceUID(forID: id) == uid {
            return id
        }
        return nil
    }

    private static func coreAudioDeviceList() -> [AudioDeviceID] {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &prop, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &prop, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func coreAudioDeviceUID(forID id: AudioDeviceID) -> String? {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &prop, 0, nil, &size, &cfUID) == noErr,
              let cfUID else { return nil }
        return cfUID.takeRetainedValue() as String
    }
}
