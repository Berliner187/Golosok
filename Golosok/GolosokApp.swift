import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Один экземпляр на пользователя: два процесса дублируют горячую клавишу
        // и каждый рисует свой островок, из-за чего панель «пропадает».
        let pid = ProcessInfo.processInfo.processIdentifier
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != pid
        }) {
            AppLogger.shared.warn("App", "Уже запущен другой экземпляр — активирую его и завершаюсь",
                                  details: "pid \(running.processIdentifier)")
            running.activate(from: .current, options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        let mic = PermissionManager.shared.isMicGranted
        let ax = PermissionManager.shared.isAccessibilityGranted
        AppLogger.shared.info("App", "Запуск Golosok",
                              details: "версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"), микрофон: \(mic), доступ AX: \(ax)")

        // Прогрев на запуске (пока идёт сплэш): первый клик по «Борду» и «Настройкам» не тормозит.
        DashboardStatsStore.shared.refresh(history: AudioCapture.shared.history)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = MicrophoneStore.shared
            _ = ModelStore.shared
        }

        let hotKey = NativeHotKeyManager.shared
        hotKey.onHotKeyPressed = {
            if hotKey.mode == .pushToTalk {
                if !AudioCapture.shared.isRecording {
                    AudioCapture.shared.startRecording()
                }
            } else {
                AudioCapture.shared.toggleRecording()
            }
        }
        hotKey.onHotKeyReleased = {
            if hotKey.mode == .pushToTalk, AudioCapture.shared.isRecording {
                AudioCapture.shared.stopRecording()
            }
        }
        hotKey.register()

        // Закреплённый Space для островка создаём заранее, а не в момент первой записи.
        OverlayPanelManager.shared.warmUp()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioCapture.shared.flushHistorySave()
    }
}

@main
struct GolosokApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var audioCapture = AudioCapture.shared
    @ObservedObject var theme = ThemeSettings.shared
    @StateObject private var updater = AppUpdater()

    init() {
        LanguageSettings.shared.apply()
        SoundEngine.shared.warmUp()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 990, minHeight: 710)
                .environmentObject(updater)
                .preferredColorScheme(theme.current.colorScheme)
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

            CommandGroup(after: .textEditing) {
                Button("Найти в стенограмме…") {
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleTranscriptSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Найти далее") {
                    NotificationCenter.default.post(name: NSNotification.Name("FindNextInTranscript"), object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Найти ранее") {
                    NotificationCenter.default.post(name: NSNotification.Name("FindPreviousInTranscript"), object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        .defaultSize(width: 990, height: 710)
        
        MenuBarExtra(content: {
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
        }, label: {
            Image(nsImage: Self.menuBarIcon)
        })
    }

    /// MenuBarExtra draws a bare SF Symbol at a legacy fixed size, which reads
    /// too small on the taller Tahoe status bar. Draw the app logo — a filled
    /// dot — into a fixed canvas at a controlled size instead.
    private static let menuBarIcon: NSImage = {
        let canvas = NSSize(width: 22, height: 22)
        let diameter: CGFloat = 18
        let image = NSImage(size: canvas, flipped: false) { rect in
            let circle = NSRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            NSColor.black.setFill()
            NSBezierPath(ovalIn: circle).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
