import AppKit
import Sparkle
import UserNotifications

@MainActor
final class AgentBarUpdater: NSObject, SPUUpdaterDelegate {
    private let userDriver = AgentBarUpdateUserDriver()
    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: userDriver,
        delegate: self)

    func start() {
        do {
            try updater.start()
            updater.clearFeedURLFromUserDefaults()
            updater.automaticallyChecksForUpdates = true
            syncAutomaticUpdateMode()
            updater.checkForUpdatesInBackground()
        } catch {
            NSLog("AgentBar updater failed to start: \(error.localizedDescription)")
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updater.automaticallyDownloadsUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = newValue
            syncAutomaticUpdateMode()
            if newValue {
                updater.checkForUpdatesInBackground()
            }
        }
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        false
    }

    func updater(_: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck _: SPUUpdateCheck) throws {
        if userDriver.shouldSkip(updateItem) {
            throw NSError(
                domain: AgentBarUpdateUserDriver.errorDomain,
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "AgentBar update \(updateItem.displayVersionString) was skipped by the user.",
                ])
        }
    }

    func updater(_: SPUUpdater, shouldDownloadReleaseNotesForUpdate _: SUAppcastItem) -> Bool {
        false
    }

    func updater(_: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        AgentBarUpdateCompletionNotifier.rememberPendingUpdate(to: item)
    }

    private func syncAutomaticUpdateMode() {
        userDriver.automaticallyInstallsUpdates = updater.automaticallyDownloadsUpdates
        userDriver.enableAutomaticUpdates = { [weak self] in
            guard let self else { return }
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
            syncAutomaticUpdateMode()
        }
    }
}

@MainActor
final class AgentBarUpdateUserDriver: NSObject, SPUUserDriver {
    static let errorDomain = "com.ifuryst.agentbar.updater"

    private let defaults: UserDefaults
    private let skippedVersionKey = "AgentBar.updater.skippedVersion"
    private var currentUpdate: SUAppcastItem?
    private var expectedContentLength: UInt64 = 0
    private var receivedContentLength: UInt64 = 0
    var automaticallyInstallsUpdates = false
    var enableAutomaticUpdates: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldSkip(_ item: SUAppcastItem) -> Bool {
        defaults.string(forKey: skippedVersionKey) == item.versionString
    }

    func show(_: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: NSNumber(value: automaticallyInstallsUpdates),
            sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation _: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        currentUpdate = appcastItem
        expectedContentLength = appcastItem.contentLength
        receivedContentLength = 0

        guard !appcastItem.isInformationOnlyUpdate else {
            if let infoURL = appcastItem.infoURL {
                NSWorkspace.shared.open(infoURL)
            }
            rememberSkippedVersion(appcastItem)
            return .skip
        }

        if automaticallyInstallsUpdates {
            return .install
        }

        if state.stage == .downloaded || state.stage == .installing {
            return await confirmReadyToInstall()
        }

        return .install
    }

    func showUpdateReleaseNotes(with _: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_: any Error) {}

    func showUpdateNotFoundWithError(_: any Error) async {}

    func showUpdaterError(_ error: any Error) async {
        guard (error as NSError).domain != Self.errorDomain else { return }
        _ = await showAlert(
            title: "AgentBar update failed",
            message: error.localizedDescription,
            primaryButton: "OK",
            secondaryButton: nil)
    }

    func showDownloadInitiated(cancellation _: @escaping () -> Void) {
        receivedContentLength = 0
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedContentLength += length
    }

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_: Double) {}

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        if automaticallyInstallsUpdates {
            return .install
        }

        return await confirmReadyToInstall()
    }

    func showInstallingUpdate(withApplicationTerminated _: Bool, retryTerminatingApplication _: @escaping () -> Void) {}

    func showUpdateInstalledAndRelaunched(_: Bool) async {}

    func dismissUpdateInstallation() {
        currentUpdate = nil
        expectedContentLength = 0
        receivedContentLength = 0
    }

    func showUpdateInFocus() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func confirmReadyToInstall() async -> SPUUserUpdateChoice {
        guard let currentUpdate else { return .dismiss }

        let downloadText = formattedDownloadText()
        let message = [
            "AgentBar \(currentUpdate.displayVersionString) has been downloaded and is ready to install.",
            downloadText,
            "Installing now will quit and relaunch AgentBar.",
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        let response = await showAlert(
            title: "Install AgentBar \(currentUpdate.displayVersionString)?",
            message: message,
            primaryButton: "Install and Relaunch",
            secondaryButton: "Skip This Version",
            tertiaryButton: "Turn On Automatic Updates")

        if response == .alertFirstButtonReturn {
            return .install
        }

        if response == .alertThirdButtonReturn {
            enableAutomaticUpdates?()
            return .install
        }

        rememberSkippedVersion(currentUpdate)
        return .skip
    }

    private func showAlert(
        title: String,
        message: String,
        primaryButton: String,
        secondaryButton: String?,
        tertiaryButton: String? = nil
    ) async -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }
        if let tertiaryButton {
            alert.addButton(withTitle: tertiaryButton)
        }

        return alert.runModal()
    }

    private func rememberSkippedVersion(_ item: SUAppcastItem) {
        defaults.set(item.versionString, forKey: skippedVersionKey)
    }

    private func formattedDownloadText() -> String? {
        let bytes = max(expectedContentLength, receivedContentLength)
        guard bytes > 0 else { return nil }
        return "Downloaded \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))."
    }
}

@MainActor
enum AgentBarUpdateCompletionNotifier {
    private static let pendingFromVersionKey = "AgentBar.updater.pendingFromVersion"
    private static let pendingToVersionKey = "AgentBar.updater.pendingToVersion"
    private static let deliveredVersionKey = "AgentBar.updater.deliveredCompletionVersion"

    static func rememberPendingUpdate(to item: SUAppcastItem, defaults: UserDefaults = .standard) {
        defaults.set(currentDisplayVersion, forKey: pendingFromVersionKey)
        defaults.set(displayVersion(for: item), forKey: pendingToVersionKey)
    }

    static func deliverPendingNotificationIfNeeded(defaults: UserDefaults = .standard) {
        guard let fromVersion = defaults.string(forKey: pendingFromVersionKey),
              let toVersion = defaults.string(forKey: pendingToVersionKey),
              toVersion == currentDisplayVersion,
              defaults.string(forKey: deliveredVersionKey) != toVersion
        else {
            clearPendingUpdate(defaults: defaults)
            return
        }

        defaults.set(toVersion, forKey: deliveredVersionKey)
        clearPendingUpdate(defaults: defaults)

        Task {
            await deliverNotification(fromVersion: fromVersion, toVersion: toVersion)
        }
    }

    private static func deliverNotification(fromVersion: String, toVersion: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert])
                guard granted else { return }
            case .denied:
                return
            @unknown default:
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "AgentBar Updated"
            content.body = "Updated from \(fromVersion) to \(toVersion)."
            let request = UNNotificationRequest(
                identifier: "agentbar.update-completed.\(toVersion)",
                content: content,
                trigger: nil)
            try await center.add(request)
        } catch {
            NSLog("AgentBar update notification failed: \(error.localizedDescription)")
        }
    }

    private static func clearPendingUpdate(defaults: UserDefaults) {
        defaults.removeObject(forKey: pendingFromVersionKey)
        defaults.removeObject(forKey: pendingToVersionKey)
    }

    private static func displayVersion(for item: SUAppcastItem) -> String {
        item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
    }

    private static var currentDisplayVersion: String {
        let info = Bundle.main.infoDictionary
        if let shortVersion = info?["CFBundleShortVersionString"] as? String, !shortVersion.isEmpty {
            return shortVersion
        }
        if let bundleVersion = info?["CFBundleVersion"] as? String, !bundleVersion.isEmpty {
            return bundleVersion
        }
        return "unknown"
    }
}
