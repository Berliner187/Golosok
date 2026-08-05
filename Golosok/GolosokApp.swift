import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeHotKeyManager.shared.onHotKeyPressed = {
            AudioCapture.shared.toggleRecording()
        }
        NativeHotKeyManager.shared.registerOptionSpace()
    }
}

@main
struct GolosokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var audioCapture = AudioCapture.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 920, minHeight: 640)
        }
        
        .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("О программе") {
                        NSApp.activate(ignoringOtherApps: true)
                        NotificationCenter.default.post(name: NSNotification.Name("OpenAboutModal"), object: nil)
                    }
                }
                
                CommandGroup(replacing: .newItem) {
                    Button("Открыть аудиофайл...") {
                        AudioCapture.shared.importAndTranscribeFile()
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
            }
    
        .defaultSize(width: 920, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть аудиофайл...") {
                    AudioCapture.shared.importAndTranscribeFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        
        MenuBarExtra("Голосок", systemImage: "waveform") {
            Button("Скопировать последнюю запись") {
                if let last = audioCapture.history.first?.text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(last, forType: .string)
                }
            }
            .disabled(audioCapture.history.isEmpty)
            
            Divider()
            
            Button("Транскрибировать аудиофайл...") {
                AudioCapture.shared.importAndTranscribeFile()
            }
            
            Button("Развернуть Голосок") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Divider()
            
            Button("Завершить") { NSApplication.shared.terminate(nil) }
        }
    }
}
