import SwiftUI
import AVFoundation
import AppKit

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var isMicGranted: Bool = false
    @Published var isAccessibilityGranted: Bool = false
    
    @Published var onboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "onboardingCompleted") {
        didSet {
            UserDefaults.standard.set(onboardingCompleted, forKey: "onboardingCompleted")
        }
    }
    
    var canContinue: Bool {
        return isMicGranted
    }
    
    init() {
        checkPermissions()
        if !isMicGranted {
            onboardingCompleted = false
        }
    }
    
    func checkPermissions() {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.isMicGranted = (micStatus == .authorized)
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func completeOnboarding() {
        DispatchQueue.main.async {
            self.onboardingCompleted = true
        }
    }
}
