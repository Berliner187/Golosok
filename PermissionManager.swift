//
//  PermissionManager.swift
//  Golosok
//
//  Created by kozak_dev on 26.07.2026.
//

import SwiftUI
import AVFoundation
import AppKit

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var isMicGranted: Bool = false
    @Published var isAccessibilityGranted: Bool = false
    
    var isAllGranted: Bool {
        return isMicGranted && isAccessibilityGranted
    }
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        // Проверка микрофона
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.isMicGranted = (micStatus == .authorized)
        
        // Проверка Универсального доступа (для Cmd+V)
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.isMicGranted = granted
            }
        }
    }
    
    func requestAccessibilityPermission() {
        // Запрашиваем окно системы
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Открываем прямой раздел настроек
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
