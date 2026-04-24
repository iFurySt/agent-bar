import AppKit
import Sparkle

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
            if updater.automaticallyChecksForUpdates {
                updater.checkForUpdatesInBackground()
            }
        } catch {
            NSLog("AgentBar updater failed to start: \(error.localizedDescription)")
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
}

@MainActor
final class AgentBarUpdateUserDriver: NSObject, SPUUserDriver {
    static let errorDomain = "com.ifuryst.agentbar.updater"

    private let defaults: UserDefaults
    private let skippedVersionKey = "AgentBar.updater.skippedVersion"
    private var currentUpdate: SUAppcastItem?
    private var expectedContentLength: UInt64 = 0
    private var receivedContentLength: UInt64 = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldSkip(_ item: SUAppcastItem) -> Bool {
        defaults.string(forKey: skippedVersionKey) == item.versionString
    }

    func show(_: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: NSNumber(value: false),
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
        await confirmReadyToInstall()
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

        let shouldInstall = await showAlert(
            title: "Install AgentBar \(currentUpdate.displayVersionString)?",
            message: message,
            primaryButton: "Install and Relaunch",
            secondaryButton: "Skip This Version")

        if shouldInstall {
            return .install
        }

        rememberSkippedVersion(currentUpdate)
        return .skip
    }

    private func showAlert(
        title: String,
        message: String,
        primaryButton: String,
        secondaryButton: String?
    ) async -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton {
            alert.addButton(withTitle: secondaryButton)
        }

        return alert.runModal() == .alertFirstButtonReturn
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
