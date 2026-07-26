import SwiftUI
import AppKit
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var escapeHotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = HotKey(key: .space, modifiers: [.option])
        hotKey?.keyDownHandler = {
            AudioCapture.shared.toggleRecording()
        }
        
        escapeHotKey = HotKey(key: .escape, modifiers: [])
        escapeHotKey?.keyDownHandler = {
            if AudioCapture.shared.isRecording {
                AudioCapture.shared.cancelRecording()
            }
        }
    }
}

@main
struct GolosokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var audioCapture = AudioCapture.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        // Иконка и меню в правой верхней строке macOS (Menu Bar)
        MenuBarExtra("Голосок", systemImage: "waveform") {
            Button("Скопировать последнюю запись") {
                if let lastText = audioCapture.history.first?.text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lastText, forType: .string)
                }
            }
            .disabled(audioCapture.history.isEmpty)
            
            Divider()
            
            Button("Открыть окно истории") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Divider()
            
            Text("Golosok v1.0.0 (GigaAM v3)")
            
            Button("Завершить") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
