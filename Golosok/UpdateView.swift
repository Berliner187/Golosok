import SwiftUI

struct UpdateView: View {
    @ObservedObject var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // 1. ИКОНКА И ЗАГОЛОВОК
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

                Text("Обновление Голосок")
                    .font(UIStyleFont.display(size: 20, weight: .bold))
                    .foregroundColor(.uiInk)

                UIBadge(text: updater.currentVersionStr)
            }

            Divider().background(Color.uiHairline)

            // 2. СОСТОЯНИЕ
            statusContent

            Divider().background(Color.uiHairline)

            // 3. ДЕЙСТВИЯ
            HStack {
                Text("Автообновление • Sparkle")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.uiMidGray)

                Spacer()

                UIOutlineButton(title: "Закрыть") {
                    if case .readyToInstall = updater.state {
                        updater.dismissInstall()
                    }
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.uiPaper)
    }

    // MARK: - Состояния

    @ViewBuilder
    private var statusContent: some View {
        switch updater.state {
        case .idle:
            VStack(spacing: 10) {
                statusText("Проверьте наличие новой версии Голосок.")
                HStack(spacing: 8) {
                    UIPrimaryButton(title: "Проверить обновления") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }

        case .found(let version, let notes):
            VStack(spacing: 12) {
                versionBlock(version: version, notes: notes, message: "Найдена новая версия:")
                HStack(spacing: 8) {
                    UIPrimaryButton(title: "Загрузить") {
                        updater.proceedDownload()
                    }
                    UIOutlineButton(title: "Позже") {
                        updater.cancelDownload()
                        dismiss()
                    }
                }
            }

        case .checking:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                statusText("Проверяем обновления…")
                UIOutlineButton(title: "Отмена") {
                    updater.cancelCheck()
                }
            }

        case .downloading(let progress, let version, let notes):
            VStack(spacing: 12) {
                versionBlock(version: version, notes: notes, message: "Загружается версия")

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                Text("\(Int(progress * 100))%")
                    .font(UIStyleFont.body(size: 11, weight: .medium))
                    .foregroundColor(.uiMidGray)
            }

        case .extracting(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                statusText(progress > 0 ? "Распаковка обновления… \(Int(progress * 100))%" : "Распаковка обновления…")
            }

        case .readyToInstall(let version, let notes):
            VStack(spacing: 12) {
                versionBlock(version: version, notes: notes, message: "Готово к установке:")
                HStack(spacing: 8) {
                    UIPrimaryButton(title: "Установить и перезапустить") {
                        updater.installAndRelaunch()
                    }
                    UIOutlineButton(title: "Позже") {
                        updater.dismissInstall()
                        dismiss()
                    }
                }
            }

        case .installing:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                statusText("Устанавливаем обновление…")
            }

        case .upToDate:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.uiInk)
                statusText("У вас последняя версия Голосок.")
                UIOutlineButton(title: "Проверить снова") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }

        case .error(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.uiMidGray)
                statusText("Не удалось проверить обновления.")
                Text(message)
                    .font(UIStyleFont.body(size: 11, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.uiMidGray)
                    .fixedSize(horizontal: false, vertical: true)
                UIOutlineButton(title: "Проверить снова") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    // MARK: - Блок версии с заметками

    private func versionBlock(version: String, notes: NSAttributedString?, message: String) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(message)
                    .font(UIStyleFont.body(size: 12, weight: .regular))
                    .foregroundColor(.uiMidGray)
                UIBadge(text: version)
            }
            if let notes {
                ReleaseNotesText(attributed: notes)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180)
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(UIStyleFont.body(size: 12, weight: .regular))
            .multilineTextAlignment(.center)
            .foregroundColor(.uiMidGray)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Текстовое поле заметок о выпуске

private struct ReleaseNotesText: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.textStorage?.string != attributed.string {
            textView.textStorage?.setAttributedString(attributed)
        }
    }
}
