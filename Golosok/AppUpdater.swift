import Foundation
import Sparkle

// MARK: - Модель состояния обновления

enum UpdateState {
    case idle
    case checking
    case found(version: String, notes: NSAttributedString?)
    case downloading(progress: Double, version: String, notes: NSAttributedString?)
    case extracting(progress: Double)
    case readyToInstall(version: String, notes: NSAttributedString?)
    case installing
    case upToDate
    case error(String)
}

// MARK: - Кастомный драйвер Sparkle

@MainActor
final class SparkleUserDriver: NSObject, SPUUserDriver {
    var onState: ((UpdateState) -> Void)?

    private var currentState: UpdateState = .idle
    private var notes: NSAttributedString?
    private var pendingVersion = ""
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var downloadReply: ((SPUUserUpdateChoice) -> Void)?
    private var checkCancellation: (() -> Void)?

    private func emit(_ state: UpdateState) {
        currentState = state
        onState?(state)
    }

    func installAndRelaunch() {
        let reply = installReply
        installReply = nil
        reply?(.install)
    }

    func dismissInstall() {
        let reply = installReply
        installReply = nil
        reply?(.dismiss)
    }

    func proceedDownload() {
        let reply = downloadReply
        downloadReply = nil
        reply?(.install)
    }

    func cancelDownload() {
        let reply = downloadReply
        downloadReply = nil
        reply?(.dismiss)
        emit(.idle)
    }

    func cancelCheck() {
        let cancellation = checkCancellation
        checkCancellation = nil
        cancellation?()
        emit(.idle)
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Автопроверка уже разрешена через SUEnableAutomaticChecks в Info.plist.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkCancellation = cancellation
        expectedLength = 0
        receivedLength = 0
        notes = nil
        pendingVersion = ""
        emit(.checking)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingVersion = appcastItem.displayVersionString
        emit(.found(version: pendingVersion, notes: notes))
        if state.userInitiated {
            // Пользователь сам запустил проверку — сразу соглашаемся на загрузку.
            DispatchQueue.main.async {
                reply(.install)
            }
        } else {
            // Фоновая проверка: ждём решения пользователя в UI.
            downloadReply = reply
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if let attributed = Self.makeAttributedNotes(from: downloadData.data) {
            notes = attributed
        }
        switch currentState {
        case .found(let version, _):
            emit(.found(version: version, notes: notes))
        case .downloading(let progress, let version, _):
            emit(.downloading(progress: progress, version: version, notes: notes))
        case .readyToInstall(let version, _):
            emit(.readyToInstall(version: version, notes: notes))
        default:
            break
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // Примечания к выпуску недоступны — не блокируем процесс обновления.
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        // Наличие SPUNoUpdateFoundReasonKey означает штатное «обновлений нет»;
        // его отсутствие — реальную ошибку (например, битый appcast).
        let nsError = error as NSError
        if nsError.userInfo[SPUNoUpdateFoundReasonKey] != nil {
            emit(.upToDate)
        } else {
            emit(.error(error.localizedDescription))
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        emit(.error(error.localizedDescription))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        receivedLength = 0
        emit(.downloading(progress: 0, version: pendingVersion, notes: notes))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        let progress = expectedLength > 0 ? min(1.0, Double(receivedLength) / Double(expectedLength)) : 0
        emit(.downloading(progress: progress, version: pendingVersion, notes: notes))
    }

    func showDownloadDidStartExtractingUpdate() {
        emit(.extracting(progress: 0))
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        emit(.extracting(progress: progress))
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        emit(.readyToInstall(version: pendingVersion, notes: notes))
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        emit(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        emit(.idle)
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        installReply = nil
        if case .installing = currentState { return }
        emit(.idle)
    }

    // MARK: Разбор release notes

    private static func makeAttributedNotes(from data: Data) -> NSAttributedString? {
        if let html = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil
        ), html.length > 0 {
            return html
        }
        if let rtf = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ), rtf.length > 0 {
            return rtf
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return NSAttributedString(string: text)
        }
        return nil
    }
}

// MARK: - Фасад обновления для UI

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var canCheckForUpdates = true

    private let driver = SparkleUserDriver()
    private let updater: SPUUpdater?
    private let startupError: String?

    override init() {
        var startedUpdater: SPUUpdater?
        var startupError: String?
        do {
            let updater = SPUUpdater(hostBundle: .main,
                                     applicationBundle: .main,
                                     userDriver: driver,
                                     delegate: nil)
            try updater.start()
            startedUpdater = updater
        } catch {
            startupError = error.localizedDescription
        }
        self.updater = startedUpdater
        self.startupError = startupError
        super.init()
        driver.onState = { [weak self] newState in
            guard let self else { return }
            self.state = newState
            if let updater = self.updater {
                self.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    var currentVersionStr: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return "v\(ver)"
    }

    /// Проверка обновлений по инициативе пользователя.
    func checkForUpdates() {
        guard let updater else {
            state = .error(startupError ?? "Модуль обновлений недоступен")
            return
        }
        updater.checkForUpdates()
    }

    /// Установить скачанное обновление и перезапустить приложение.
    func installAndRelaunch() {
        driver.installAndRelaunch()
    }

    /// Отложить установку (ответ Sparkle `.dismiss`).
    func dismissInstall() {
        driver.dismissInstall()
    }

    /// Начать загрузку найденного обновления (фоновая проверка).
    func proceedDownload() {
        driver.proceedDownload()
    }

    /// Отказаться от загрузки найденного обновления.
    func cancelDownload() {
        driver.cancelDownload()
    }

    /// Отменить пользовательскую проверку обновлений.
    func cancelCheck() {
        driver.cancelCheck()
    }
}
