import AppKit
import AgentBarCore
import CoreGraphics

@main
enum AgentBarMain {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        AgentBarAppIcon.install()
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum AgentBarAppIcon {
    @MainActor
    static func install() {
        guard let image = image() else { return }
        NSApp.applicationIconImage = image
        refreshDockTile(with: image)
    }

    @MainActor
    static func refreshDockTile() {
        guard let image = image() else { return }
        NSApp.applicationIconImage = image
        refreshDockTile(with: image)
    }

    @MainActor
    private static func refreshDockTile(with image: NSImage) {
        let tileSize = NSApp.dockTile.size
        let size = tileSize == .zero ? NSSize(width: 128, height: 128) : tileSize
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        NSApp.dockTile.contentView = imageView
        NSApp.dockTile.display()
    }

    private static func image() -> NSImage? {
        if let resourceURL = Bundle.main.resourceURL {
            let appIconURL = resourceURL.appendingPathComponent("AgentBar.icns")
            if let image = NSImage(contentsOf: appIconURL) {
                return image
            }

            if let packagedBundle = Bundle(url: resourceURL.appendingPathComponent("agent-bar_AgentBar.bundle")),
               let url = packagedBundle.url(forResource: "AgentBar", withExtension: "icns"),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }

        guard let url = Bundle.module.url(forResource: "AgentBar", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandWindowController?
    private let updater = AgentBarUpdater()

    func applicationDidFinishLaunching(_: Notification) {
        updater.start()

        let controller = IslandWindowController(updater: updater)
        self.controller = controller
        controller.show()
    }
}

@MainActor
final class IslandWindowController {
    private var overlays: [ScreenOverlay] = []
    private let snapshotService = CodexSnapshotService()
    private let preferences = AgentBarPreferences()
    private let updater: AgentBarUpdater
    private var settingsWindowController: AgentBarSettingsWindowController?
    private weak var settingsAnchor: NSView?
    private var refreshTask: Task<Void, Never>?
    private var hoverTimer: Timer?
    private var activeAccountOverrideID: String?
    private var currentCosts = CodexCostSnapshot(
        todayCostUSD: 0,
        todayTokens: 0,
        last30DaysCostUSD: 0,
        last30DaysTokens: 0)
    private var currentAccounts: [CodexAccountUsageSnapshot] = []
    private var currentText = "5h --%  7d --%  Today: $0.00 \u{00B7} --/~30 Days: $0.00 \u{00B7} -- Tokens"

    init(updater: AgentBarUpdater) {
        self.updater = updater

        if let cachedSnapshot = snapshotService.cachedSnapshot() {
            currentCosts = cachedSnapshot.costs
            currentAccounts = cachedSnapshot.accounts
            currentText = AgentBarDisplayFormatting.line(snapshot: cachedSnapshot)
        } else if let cachedCosts = snapshotService.cachedCosts() {
            currentCosts = cachedCosts
            currentText = AgentBarDisplayFormatting.line(snapshot: AgentBarSnapshot(
                rateLimits: CodexRateLimitSnapshot(fiveHourRemainingPercent: nil, weeklyRemainingPercent: nil),
                costs: cachedCosts))
        }
        if currentAccounts.isEmpty {
            currentAccounts = snapshotService.cachedAccounts()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    func show() {
        rebuildOverlays()
        startHoverTracking()

        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @objc private func screenParametersDidChange() {
        rebuildOverlays()
    }

    private func refresh() async {
        let quickRateLimits = await snapshotService.quickRateLimits()
        currentText = AgentBarDisplayFormatting.line(snapshot: AgentBarSnapshot(rateLimits: quickRateLimits, costs: currentCosts, accounts: currentAccounts))
        updateOverlays(animated: true)

        if currentAccounts.isEmpty || currentAccounts.allSatisfy({
            $0.rateLimits.fiveHourRemainingPercent == nil && $0.rateLimits.weeklyRemainingPercent == nil
        }) {
            let accounts = await snapshotService.accountRateLimits()
            if !accounts.isEmpty {
                currentAccounts = accountsApplyingActiveOverride(accounts)
                let visibleRateLimits = currentAccounts.first(where: \.isCurrent)?.rateLimits ?? quickRateLimits
                currentText = AgentBarDisplayFormatting.line(snapshot: AgentBarSnapshot(
                    rateLimits: visibleRateLimits,
                    costs: currentCosts,
                    accounts: currentAccounts))
                updateOverlays(animated: true)
            }
        }

        let snapshot = await snapshotService.snapshot()
        currentCosts = snapshot.costs
        currentAccounts = accountsApplyingActiveOverride(snapshot.accounts)
        let visibleRateLimits = currentAccounts.first(where: \.isCurrent)?.rateLimits ?? snapshot.rateLimits
        currentText = AgentBarDisplayFormatting.line(snapshot: AgentBarSnapshot(
            rateLimits: visibleRateLimits,
            costs: snapshot.costs,
            accounts: currentAccounts,
            isUsingRateLimitFallback: snapshot.isUsingRateLimitFallback))
        updateOverlays(animated: true)
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.panel.orderOut(nil) }
        let mouseLocation = NSEvent.mouseLocation
        overlays = NSScreen.screens.map { screen in
            let overlay = ScreenOverlay(
                screen: screen,
                autoHideEligible: screen.agentBarSupportsAutoHide)
            overlay.view.onPinToggle = { [weak self] in
                self?.togglePinned()
            }
            overlay.view.onSettingsOpen = { [weak self] anchor in
                self?.toggleSettings(relativeTo: anchor, page: .general)
            }
            overlay.view.onAccountsOpen = { [weak self] anchor in
                self?.toggleSettings(relativeTo: anchor, page: .accounts)
            }
            overlay.view.onExpansionToggle = { [weak self, weak overlay] in
                guard let self, let overlay else { return }
                self.setExpanded(!overlay.isExpanded, for: overlay, animated: true)
            }
            overlay.view.onAccountSwitch = { [weak self] accountID in
                self?.switchAccount(accountID)
            }
            overlay.view.update(text: currentText, animated: false)
            overlay.view.update(accounts: currentAccounts)
            overlay.view.setPinned(preferences.isPinned)
            overlay.view.setExpanded(overlay.isExpanded)
            resetExpansionAutoCollapse(for: overlay, at: mouseLocation)
            overlay.isHovered = isMouseHovering(overlay, at: mouseLocation)
            overlay.isCollapsed = shouldCollapse(overlay)
            overlay.view.setHovering(overlay.isHovered)
            overlay.panel.ignoresMouseEvents = overlay.autoHideEligible ? !overlay.isHovered : false
            position(overlay, animated: false)
            overlay.panel.orderFrontRegardless()
            return overlay
        }
        updateHoverState(animated: false)
    }

    private func updateOverlays(animated: Bool = false) {
        for overlay in overlays {
            let textChanged = overlay.view.update(text: currentText, animated: animated)
            overlay.view.update(accounts: currentAccounts)
            overlay.view.setPinned(preferences.isPinned)
            overlay.view.setExpanded(overlay.isExpanded)
            position(
                overlay,
                animated: animated && textChanged,
                duration: contentUpdateAnimationDuration)
        }
        updateHoverState(animated: false)
        settingsWindowController?.refreshAccounts()
    }

    private func position(_ overlay: ScreenOverlay, animated: Bool, duration: TimeInterval? = nil) {
        let targetFrame = targetFrame(for: overlay)
        guard overlay.lastTargetFrame != targetFrame else { return }
        overlay.lastTargetFrame = targetFrame

        let updates = {
            overlay.panel.setFrame(targetFrame, display: true)
        }
        let animationDuration = duration ?? autoHideAnimationDuration
        guard animated, animationDuration > 0 else {
            updates()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlay.panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func targetFrame(for overlay: ScreenOverlay) -> NSRect {
        let screen = overlay.screen
        let topBarHeight = screen.agentBarTopBarHeight
        if let notchFrame = screen.agentBarNotchFrame {
            overlay.panel.level = .screenSaver
            overlay.view.configure(.notch(
                height: max(topBarHeight, notchFrame.height),
                gapWidth: notchFrame.width,
                showsPin: false,
                showsSettings: true))

            let maxWidth = min(max(320, notchFrame.width + 240), screen.frame.width - 80)
            let targetSize = overlay.view.fittingSize(constrainedTo: maxWidth)
            let width = targetSize.width
            let height = targetSize.height
            let x = notchFrame.midX - overlay.view.notchGapWidth / 2 - overlay.view.notchLeftLaneWidth
            let y = screen.frame.maxY - height
            let frame = NSRect(x: x, y: y, width: width, height: height)
            overlay.visibleFrame = frame
            return frame
        }

        overlay.panel.level = overlay.autoHideEligible ? .screenSaver : .statusBar
        overlay.view.configure(.attachedBar(height: topBarHeight, showsPin: overlay.autoHideEligible))

        let maxWidth = max(260, screen.frame.width - 120)
        let targetSize = overlay.view.fittingSize(constrainedTo: maxWidth)
        let width = min(targetSize.width, maxWidth)
        let height = targetSize.height
        let centeredX = screen.frame.midX - width / 2
        let x: CGFloat
        if overlay.visibleFrame.isEmpty {
            x = centeredX
        } else {
            x = min(
                max(overlay.visibleFrame.minX, screen.frame.minX + 60),
                screen.frame.maxX - width - 60)
        }
        let y = screen.frame.maxY - height
        let visibleFrame = NSRect(x: x, y: y, width: width, height: height)
        overlay.visibleFrame = visibleFrame

        guard overlay.isCollapsed else { return visibleFrame }
        return NSRect(x: x, y: screen.frame.maxY, width: width, height: height)
    }

    private func startHoverTracking() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHoverState(animated: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func updateHoverState(animated: Bool) {
        let mouseLocation = NSEvent.mouseLocation
        for overlay in overlays {
            let isHovered = isMouseHovering(overlay, at: mouseLocation)
            let hoverChanged = overlay.isHovered != isHovered
            if overlay.isHovered != isHovered {
                overlay.isHovered = isHovered
                overlay.view.setHovering(isHovered)
                overlay.panel.ignoresMouseEvents = overlay.autoHideEligible ? !isHovered : false
            }

            if updateExpansionAutoCollapse(for: overlay, at: mouseLocation, animated: animated) {
                continue
            }

            let shouldCollapse = shouldCollapse(overlay)
            if overlay.isCollapsed != shouldCollapse {
                overlay.isCollapsed = shouldCollapse
                position(overlay, animated: animated)
                continue
            }

            if hoverChanged {
                position(overlay, animated: animated)
            }
        }
    }

    private func setExpanded(_ expanded: Bool, for overlay: ScreenOverlay, animated: Bool) {
        guard overlay.isExpanded != expanded else { return }
        overlay.isExpanded = expanded
        resetExpansionAutoCollapse(for: overlay, at: NSEvent.mouseLocation)
        overlay.view.setExpanded(expanded)
        position(
            overlay,
            animated: animated,
            duration: paperPullAnimationDuration)
    }

    private func resetExpansionAutoCollapse(for overlay: ScreenOverlay, at mouseLocation: NSPoint) {
        if overlay.isExpanded, !isMouseInsideExpandedOverlay(overlay, at: mouseLocation) {
            overlay.expandedMouseExitStartedAt = CACurrentMediaTime()
        } else {
            overlay.expandedMouseExitStartedAt = nil
        }
    }

    @discardableResult
    private func updateExpansionAutoCollapse(for overlay: ScreenOverlay, at mouseLocation: NSPoint, animated: Bool) -> Bool {
        guard overlay.isExpanded else {
            overlay.expandedMouseExitStartedAt = nil
            return false
        }

        if isMouseInsideExpandedOverlay(overlay, at: mouseLocation) {
            overlay.expandedMouseExitStartedAt = nil
            return false
        }

        let now = CACurrentMediaTime()
        if let exitStartedAt = overlay.expandedMouseExitStartedAt {
            guard now - exitStartedAt >= preferences.expansionAutoCollapseDelay else {
                return false
            }
            setExpanded(false, for: overlay, animated: animated)
            return true
        }

        overlay.expandedMouseExitStartedAt = now
        return false
    }

    private func isMouseInsideExpandedOverlay(_ overlay: ScreenOverlay, at point: NSPoint) -> Bool {
        overlay.panel.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    private func shouldCollapse(_ overlay: ScreenOverlay) -> Bool {
        overlay.autoHideEligible &&
            !preferences.isPinned &&
            !overlay.isHovered &&
            !isSettingsOpen(for: overlay)
    }

    private func isMouseHovering(_ overlay: ScreenOverlay, at point: NSPoint) -> Bool {
        if overlay.panel.frame.insetBy(dx: -8, dy: -8).contains(point) {
            return true
        }

        guard overlay.autoHideEligible else { return false }

        let visibleFrame = overlay.visibleFrame.isEmpty ? overlay.panel.frame : overlay.visibleFrame
        let revealWidth = max(visibleFrame.width + 32, 220)
        let revealZone = NSRect(
            x: visibleFrame.midX - revealWidth / 2,
            y: overlay.screen.frame.maxY - Self.revealZoneHeight,
            width: revealWidth,
            height: Self.revealZoneHeight + 2)
        return revealZone.contains(point)
    }

    private func togglePinned() {
        preferences.isPinned = !preferences.isPinned
        for overlay in overlays {
            overlay.view.setPinned(preferences.isPinned)
        }
        updateHoverState(animated: true)
    }

    private func switchAccount(_ accountID: String) {
        do {
            try CodexAccountSwitcher.switchToAccount(id: accountID)
            activeAccountOverrideID = accountID
            currentAccounts = locallyPromotedAccounts(accountID: accountID)
            updateOverlays(animated: true)
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                guard let self else { return }
                await self.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await self.refresh()
                }
            }
        } catch {
            NSSound.beep()
        }
    }

    private func locallyPromotedAccounts(accountID: String) -> [CodexAccountUsageSnapshot] {
        let existing = currentAccounts
        guard !existing.isEmpty else {
            return snapshotService.cachedAccounts()
        }

        return existing.map { account in
            CodexAccountUsageSnapshot(
                id: account.id,
                label: account.label,
                rateLimits: account.rateLimits,
                isCurrent: account.id == accountID,
                updatedAt: account.id == accountID ? Date() : account.updatedAt,
                plan: account.plan)
        }.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func accountsApplyingActiveOverride(_ accounts: [CodexAccountUsageSnapshot]) -> [CodexAccountUsageSnapshot] {
        guard let activeAccountOverrideID else {
            return accounts
        }

        return accounts.map { account in
            CodexAccountUsageSnapshot(
                id: account.id,
                label: account.label,
                rateLimits: account.rateLimits,
                isCurrent: account.id == activeAccountOverrideID,
                updatedAt: account.id == activeAccountOverrideID ? Date() : account.updatedAt,
                plan: account.plan)
        }.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func toggleSettings(relativeTo anchor: NSView, page: SettingsPage = .general) {
        let controller: AgentBarSettingsWindowController
        if let existingController = settingsWindowController {
            controller = existingController
        } else {
            let newController = AgentBarSettingsWindowController(
                updater: updater,
                preferences: preferences,
                accountsProvider: { [weak self] in
                    self?.accountsForSettings() ?? []
                },
                onAccountSwitch: { [weak self] accountID in
                    self?.switchAccount(accountID)
                })
            newController.onClose = { [weak self] in
                self?.settingsAnchor = nil
                NSApp.setActivationPolicy(.accessory)
                self?.updateHoverState(animated: true)
            }
            settingsWindowController = newController
            controller = newController
        }
        settingsAnchor = anchor
        NSApp.setActivationPolicy(.regular)
        AgentBarAppIcon.refreshDockTile()
        controller.showSettings(page: page)
        updateHoverState(animated: true)
    }

    private func accountsForSettings() -> [CodexAccountUsageSnapshot] {
        if !currentAccounts.isEmpty {
            return currentAccounts
        }
        if let cachedAccounts = snapshotService.cachedSnapshot()?.accounts, !cachedAccounts.isEmpty {
            return cachedAccounts
        }
        return snapshotService.cachedAccounts()
    }

    private func isSettingsOpen(for overlay: ScreenOverlay) -> Bool {
        guard settingsWindowController?.isShown == true, let settingsAnchor else { return false }
        return settingsAnchor.isDescendant(of: overlay.view)
    }

    private var autoHideAnimationDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.menuBarAutoHideAnimationDuration
    }

    private var contentUpdateAnimationDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.contentUpdateAnimationDuration
    }

    private var paperPullAnimationDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.paperPullAnimationDuration
    }

    private static let menuBarAutoHideAnimationDuration: TimeInterval = 0.26
    private static let contentUpdateAnimationDuration: TimeInterval = 0.44
    private static let paperPullAnimationDuration: TimeInterval = 0.32
    private static let revealZoneHeight: CGFloat = 10
}

@MainActor
final class ScreenOverlay {
    let screen: NSScreen
    let panel: NSPanel
    let view: IslandView
    let autoHideEligible: Bool
    var isHovered = false
    var isCollapsed = false
    var isExpanded = false
    var expandedMouseExitStartedAt: CFTimeInterval?
    var visibleFrame = NSRect.zero
    var lastTargetFrame = NSRect.zero

    init(screen: NSScreen, autoHideEligible: Bool) {
        self.screen = screen
        self.autoHideEligible = autoHideEligible
        self.view = IslandView(frame: NSRect(x: 0, y: 0, width: 760, height: 24))
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }
}

final class IslandView: NSView {
    enum Style {
        case attachedBar(height: CGFloat, showsPin: Bool)
        case notch(height: CGFloat, gapWidth: CGFloat, showsPin: Bool, showsSettings: Bool)
    }

    private let iconView = NSImageView()
    private let fullLabel = RollingTextLabel()
    private let quotaLabel = RollingTextLabel()
    private let usageLabel = RollingTextLabel()
    private let accountsView = AccountBlocksView()
    private let pinButton = PinButton()
    private let settingsButton = SettingsButton()
    private var horizontalPadding: CGFloat = 0
    private var notchInnerPadding: CGFloat = 0
    private var notchHeight: CGFloat = 24
    private(set) var notchGapWidth: CGFloat = 0
    private(set) var notchLeftLaneWidth: CGFloat = 0
    private var showsPin = false
    private var showsSettings = false
    private var isHovering = false
    private var controlsVisible = false
    private var isExpanded = false
    private var style: Style = .attachedBar(height: 32, showsPin: false)
    var onPinToggle: (() -> Void)?
    var onSettingsOpen: ((NSView) -> Void)?
    var onAccountsOpen: ((NSView) -> Void)?
    var onExpansionToggle: (() -> Void)?
    var onAccountSwitch: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        for label in [fullLabel, quotaLabel, usageLabel] {
            label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .white
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
        }

        iconView.image = Self.codexIcon()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white

        addSubview(iconView)
        addSubview(fullLabel)
        addSubview(quotaLabel)
        addSubview(usageLabel)
        addSubview(accountsView)
        addSubview(pinButton)
        addSubview(settingsButton)
        accountsView.onAccountSelected = { [weak self] accountID in
            self?.onAccountSwitch?(accountID)
        }
        accountsView.onMoreAccounts = { [weak self] in
            guard let self else { return }
            onAccountsOpen?(self)
        }
        pinButton.target = self
        pinButton.action = #selector(pinButtonPressed)
        settingsButton.target = self
        settingsButton.action = #selector(settingsButtonPressed)

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit AgentBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        self.menu = menu
    }

    override func layout() {
        super.layout()
        needsDisplay = true

        switch style {
        case .attachedBar:
            layoutAttachedBar()
        case .notch:
            layoutNotch()
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        switch style {
        case .attachedBar, .notch:
            context.saveGState()
            context.addPath(Self.paperPullIslandPath(in: bounds, topHeight: notchHeight, expanded: isExpanded))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            if isExpanded {
                Self.drawPaperPullDetails(in: bounds, topHeight: notchHeight, context: context)
            }
            context.restoreGState()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    @discardableResult
    func update(text: String, animated: Bool) -> Bool {
        let segments = Self.split(text)
        let fullText = Self.styledFullText(text)
        let quotaText = Self.styledPercentText(segments.sessionPercent)
        let usageText = Self.styledPercentText(segments.weeklyPercent)
        let textChanged = fullLabel.stringValue != fullText.string ||
            quotaLabel.stringValue != quotaText.string ||
            usageLabel.stringValue != usageText.string
        fullLabel.setAttributedStringValue(fullText, animated: animated)
        quotaLabel.setAttributedStringValue(quotaText, animated: animated)
        usageLabel.setAttributedStringValue(usageText, animated: animated)
        needsLayout = true
        return textChanged
    }

    func update(accounts: [CodexAccountUsageSnapshot]) {
        accountsView.accounts = accounts
        needsLayout = true
        needsDisplay = true
    }

    func setPinned(_ isPinned: Bool) {
        pinButton.setPinned(isPinned)
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        scheduleControlVisibility(forHovering: hovering)
        needsLayout = true
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if !expanded, isHovering {
            controlsVisible = true
        }
        updateControlVisibility()
        needsDisplay = true
        needsLayout = true
    }

    func configure(_ style: Style) {
        self.style = style
        switch style {
        case let .attachedBar(height, showsPin):
            horizontalPadding = 14
            notchInnerPadding = 0
            notchHeight = height
            notchGapWidth = 0
            notchLeftLaneWidth = 0
            accountsView.presentation = .ordinary
            self.showsPin = showsPin
            self.showsSettings = showsPin
            updateControlVisibility()
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            fullLabel.lineBreakMode = .byClipping
            fullLabel.isHidden = false
            quotaLabel.isHidden = true
            usageLabel.isHidden = true
            accountsView.isHidden = !isExpanded
        case let .notch(height, gapWidth, showsPin, showsSettings):
            horizontalPadding = 16
            notchInnerPadding = 2
            notchHeight = max(24, height)
            notchGapWidth = gapWidth
            accountsView.presentation = .notch
            self.showsPin = showsPin
            self.showsSettings = showsSettings
            updateControlVisibility()
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            quotaLabel.lineBreakMode = .byClipping
            usageLabel.lineBreakMode = .byClipping
            fullLabel.isHidden = true
            quotaLabel.isHidden = false
            usageLabel.isHidden = false
            accountsView.isHidden = !isExpanded
        }
        needsDisplay = true
        needsLayout = true
    }

    func fittingSize(constrainedTo maxWidth: CGFloat) -> NSSize {
        switch style {
        case let .attachedBar(height, _):
            let iconGap: CGFloat = 6
            let fixedWidth = horizontalPadding * 2 + iconViewSize.width + iconGap + activeActionSlotWidth
            let labelWidth = min(
                ceil(fullLabel.intrinsicContentSize.width),
                max(0, maxWidth - fixedWidth))
            return NSSize(width: fixedWidth + labelWidth, height: height + paperPullHeight)
        case .notch:
            let iconWidth = iconViewSize.width
            let iconGap: CGFloat = 8
            let labelSafety: CGFloat = 10
            let leftContentWidth = iconWidth + iconGap + ceil(quotaLabel.intrinsicContentSize.width)
            let rightLabelSafety = activeActionSlotWidth > 0 ? labelSafety : 0
            let rightContentWidth = ceil(usageLabel.intrinsicContentSize.width) + rightLabelSafety + activeActionSlotWidth
            let leftWidth = ceil(horizontalPadding + leftContentWidth + notchInnerPadding)
            let rightWidth = ceil(notchInnerPadding + rightContentWidth + horizontalPadding)
            notchLeftLaneWidth = leftWidth
            let width = min(maxWidth, leftWidth + notchGapWidth + rightWidth)
            return NSSize(width: width, height: notchHeight + paperPullHeight)
        }
    }

    private func layoutAttachedBar() {
        iconView.isHidden = false
        accountsView.isHidden = !isExpanded

        let textHeight = ceil(fullLabel.intrinsicContentSize.height)
        let centerY = topContentCenterY
        let labelY = floor(centerY - textHeight / 2)
        let iconY = floor(centerY - iconViewSize.height / 2)
        let iconGap: CGFloat = 6
        let availableLabelWidth = max(0, bounds.width - horizontalPadding * 2 - iconViewSize.width - iconGap)
        let labelWidth = min(
            ceil(fullLabel.intrinsicContentSize.width),
            availableLabelWidth)
        let startX = horizontalPadding

        iconView.frame = NSRect(x: startX, y: iconY, width: iconViewSize.width, height: iconViewSize.height)
        fullLabel.frame = NSRect(
            x: iconView.frame.maxX + iconGap,
            y: labelY,
            width: labelWidth,
            height: textHeight)
        layoutPinButton(after: fullLabel.frame.maxX, centerY: centerY)
        layoutAccountsLabel()
    }

    private func layoutNotch() {
        iconView.isHidden = false
        accountsView.isHidden = !isExpanded
        pinButton.frame = .zero
        settingsButton.frame = .zero

        let textHeight = ceil(max(quotaLabel.intrinsicContentSize.height, usageLabel.intrinsicContentSize.height))
        let centerY = topContentCenterY
        let labelY = floor(centerY - textHeight / 2)
        let iconY = floor(centerY - iconViewSize.height / 2)
        let gapStart = notchLeftLaneWidth
        let gapEnd = gapStart + notchGapWidth

        let iconWidth = iconViewSize.width
        let iconGap: CGFloat = 8
        let labelSafety: CGFloat = 10
        let quotaWidth = ceil(quotaLabel.intrinsicContentSize.width)
        let leftContentWidth = iconWidth + iconGap + quotaWidth
        let leftContentX = max(horizontalPadding, gapStart - notchInnerPadding - leftContentWidth)

        iconView.frame = NSRect(x: leftContentX, y: iconY, width: iconWidth, height: iconViewSize.height)
        let quotaX = iconView.frame.maxX + iconGap
        quotaLabel.frame = NSRect(
            x: quotaX,
            y: labelY,
            width: quotaWidth + labelSafety,
            height: textHeight)

        let usageWidth = ceil(usageLabel.intrinsicContentSize.width)
        let usageX = gapEnd + notchInnerPadding
        let usageFrameWidth = usageWidth + (activeActionSlotWidth > 0 ? labelSafety : 0)
        usageLabel.frame = NSRect(
            x: usageX,
            y: labelY,
            width: usageFrameWidth,
            height: textHeight)

        guard (controlsVisible || isExpanded) && (showsPin || showsSettings) else {
            return
        }

        let size = Self.pinButtonSize
        let buttonY = floor(centerY - size.height / 2)

        switch (showsPin, showsSettings) {
        case (true, true):
            pinButton.frame = NSRect(
                x: usageLabel.frame.maxX + Self.pinButtonGap,
                y: buttonY,
                width: size.width,
                height: size.height)
            settingsButton.frame = NSRect(
                x: pinButton.frame.maxX + Self.settingsButtonGap,
                y: buttonY,
                width: size.width,
                height: size.height)
        case (false, true):
            pinButton.frame = .zero
            settingsButton.frame = NSRect(
                x: usageLabel.frame.maxX + Self.pinButtonGap,
                y: buttonY,
                width: size.width,
                height: size.height)
        default:
            pinButton.frame = .zero
            settingsButton.frame = .zero
        }
        layoutAccountsLabel()
    }

    private func layoutAccountsLabel() {
        guard isExpanded else {
            accountsView.frame = .zero
            return
        }

        let x = max(8, horizontalPadding - 2)
        let topY = bounds.maxY - notchHeight - 8
        let height = max(0, topY - bounds.minY - 6)
        accountsView.frame = NSRect(
            x: x,
            y: bounds.minY + 8,
            width: max(0, bounds.width - x * 2),
            height: height)
    }

    private func layoutPinButton(after x: CGFloat, centerY: CGFloat) {
        guard (controlsVisible || isExpanded) && (showsPin || showsSettings) else {
            pinButton.frame = .zero
            settingsButton.frame = .zero
            return
        }

        let size = Self.pinButtonSize
        let buttonY = floor(centerY - size.height / 2)

        switch (showsPin, showsSettings) {
        case (true, true):
            pinButton.frame = NSRect(
                x: x + Self.pinButtonGap,
                y: buttonY,
                width: size.width,
                height: size.height)
            settingsButton.frame = NSRect(
                x: pinButton.frame.maxX + Self.settingsButtonGap,
                y: buttonY,
                width: size.width,
                height: size.height)
        case (false, true):
            pinButton.frame = .zero
            settingsButton.frame = NSRect(
                x: x + Self.pinButtonGap,
                y: buttonY,
                width: size.width,
                height: size.height)
        default:
            pinButton.frame = .zero
            settingsButton.frame = .zero
        }
    }

    private func updateControlVisibility() {
        let keepsControlsVisible = controlsVisible || isExpanded
        let showPinControl = showsPin && keepsControlsVisible
        let showSettingsControl = showsSettings && keepsControlsVisible
        pinButton.isHidden = !showPinControl
        pinButton.alphaValue = showPinControl ? 1 : 0
        settingsButton.isHidden = !showSettingsControl
        settingsButton.alphaValue = showSettingsControl ? 1 : 0
    }

    private func scheduleControlVisibility(forHovering hovering: Bool) {
        guard hovering else {
            controlsVisible = false
            updateControlVisibility()
            return
        }

        let delay = DispatchTime.now() + .milliseconds(150)
        DispatchQueue.main.asyncAfter(deadline: delay) { [weak self] in
            guard let self, self.isHovering else { return }
            self.controlsVisible = true
            self.updateControlVisibility()
            self.needsLayout = true
        }
    }

    @objc private func pinButtonPressed() {
        onPinToggle?()
    }

    @objc private func settingsButtonPressed() {
        onSettingsOpen?(settingsButton)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if pinButton.frame.contains(location) || settingsButton.frame.contains(location) {
            super.mouseDown(with: event)
            return
        }
        onExpansionToggle?()
    }

    private static func split(_ text: String) -> (sessionPercent: String, weeklyPercent: String) {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let session = quotaSegment(prefix: "5h", parts: parts)
        let weekly = quotaSegment(prefix: "7d", parts: parts)
        return (session, weekly)
    }

    private static func quotaSegment(prefix: String, parts: [String]) -> String {
        guard let index = parts.firstIndex(of: prefix),
              parts.indices.contains(index + 1)
        else {
            return "\(prefix) --%"
        }
        return parts[index + 1]
    }

    private static func styledFullText(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.white.withAlphaComponent(0.90),
            ])
        let nsText = text as NSString

        apply(pattern: #"(5h|7d|Today:|~30 Days:|Tokens)"#, in: text) { range, _ in
            attributed.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.58), range: range)
        }
        apply(pattern: #"(·|/)"#, in: text) { range, _ in
            attributed.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.42), range: range)
        }
        apply(pattern: #"\$[0-9,.]+"#, in: text) { range, _ in
            attributed.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.95), range: range)
        }
        apply(pattern: #"\b[0-9.]+[KMB]\b"#, in: text) { range, _ in
            attributed.addAttribute(.foregroundColor, value: NSColor.systemCyan.withAlphaComponent(0.92), range: range)
        }
        apply(pattern: #"\b(5h|7d)\s+(--%|\d+%)"#, in: text) { _, match in
            guard match.numberOfRanges >= 3 else { return }
            let percentRange = match.range(at: 2)
            let percent = nsText.substring(with: percentRange)
            attributed.addAttribute(.foregroundColor, value: percentColor(percent), range: percentRange)
        }
        return attributed
    }

    private static func styledPercentText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: labelFont,
                .foregroundColor: percentColor(text),
            ])
    }

    private static func apply(
        pattern: String,
        in text: String,
        _ body: (NSRange, NSTextCheckingResult) -> Void)
    {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        for match in regex.matches(in: text, range: range) {
            body(match.range, match)
        }
    }

    private static func percentColor(_ text: String) -> NSColor {
        guard let value = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) else {
            return NSColor.white.withAlphaComponent(0.48)
        }
        if value >= 50 {
            return .systemGreen
        }
        if value >= 20 {
            return .systemOrange
        }
        return .systemRed
    }

    private static func paperPullIslandPath(in rect: CGRect, topHeight: CGFloat, expanded: Bool) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }

        let topRadius = min(6, rect.width * 0.25, rect.height * 0.25)
        let bottomRadius = min(16, rect.height * 0.5, rect.width / 2)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        path.move(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: maxX - topRadius, y: maxY - topRadius),
            control: CGPoint(x: maxX - topRadius, y: maxY))
        path.addLine(to: CGPoint(x: maxX - topRadius, y: minY + bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: maxX - topRadius - bottomRadius, y: minY),
            control: CGPoint(x: maxX - topRadius, y: minY))
        path.addLine(to: CGPoint(x: minX + topRadius + bottomRadius, y: minY))
        path.addQuadCurve(
            to: CGPoint(x: minX + topRadius, y: minY + bottomRadius),
            control: CGPoint(x: minX + topRadius, y: minY))
        path.addLine(to: CGPoint(x: minX + topRadius, y: maxY - topRadius))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY),
            control: CGPoint(x: minX + topRadius, y: maxY))
        path.closeSubpath()
        return path
    }

    private static func drawPaperPullDetails(in rect: CGRect, topHeight: CGFloat, context: CGContext) {
        let topRadius = min(6, rect.width * 0.25, topHeight * 0.25)
        let bottomRadius = min(16, topHeight * 0.5, rect.width / 2)
        let sideXInset = topRadius + 0.5
        let seamTopY = max(rect.minY + bottomRadius, rect.maxY - topHeight + 3)
        let seamBottomY = rect.minY + bottomRadius + 2
        guard seamTopY > seamBottomY else { return }

        context.saveGState()
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.move(to: CGPoint(x: rect.minX + sideXInset, y: seamTopY))
        context.addLine(to: CGPoint(x: rect.minX + sideXInset, y: seamBottomY))
        context.move(to: CGPoint(x: rect.maxX - sideXInset, y: seamTopY))
        context.addLine(to: CGPoint(x: rect.maxX - sideXInset, y: seamBottomY))
        context.strokePath()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        context.move(to: CGPoint(x: rect.minX + topRadius + bottomRadius + 8, y: rect.minY + bottomRadius * 0.55))
        context.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius - 8, y: rect.minY + bottomRadius * 0.55))
        context.strokePath()
        context.restoreGState()
    }

    private static func codexIcon() -> NSImage? {
        guard let url = resourceURL(for: "ProviderIcon-codex", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        image.size = iconViewSize
        return image
    }

    private static func resourceURL(for name: String, withExtension fileExtension: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(url: resourceURL.appendingPathComponent("agent-bar_AgentBar.bundle")),
           let url = packagedBundle.url(forResource: name, withExtension: fileExtension)
        {
            return url
        }

        return Bundle.module.url(forResource: name, withExtension: fileExtension)
    }

    private var iconViewSize: NSSize {
        Self.iconViewSize
    }

    private var pinSlotWidth: CGFloat {
        showsPin ? Self.pinButtonSize.width * 2 + Self.pinButtonGap + Self.settingsButtonGap : 0
    }

    private var actionSlotWidth: CGFloat {
        guard showsSettings || showsPin else { return 0 }

        if !showsPin {
            return Self.pinButtonGap + Self.pinButtonSize.width
        }

        return pinSlotWidth
    }

    private var activeActionSlotWidth: CGFloat {
        (isHovering || isExpanded) ? actionSlotWidth : 0
    }

    private var paperPullHeight: CGFloat {
        isExpanded ? expandedPullHeight : 0
    }

    private var expandedPullHeight: CGFloat {
        16 + accountsView.expandedContentHeight
    }

    private var topContentCenterY: CGFloat {
        bounds.maxY - notchHeight / 2
    }

    private static let iconViewSize = NSSize(width: 16, height: 16)
    private static let pinButtonSize = NSSize(width: 18, height: 18)
    private static let pinButtonGap: CGFloat = 6
    private static let settingsButtonGap: CGFloat = 5
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
}

final class AccountBlocksView: NSView {
    enum Presentation {
        case ordinary
        case notch

        var columnCount: Int {
            switch self {
            case .ordinary:
                return 2
            case .notch:
                return 1
            }
        }

        var visibleAccountLimit: Int {
            switch self {
            case .ordinary:
                return 8
            case .notch:
                return 4
            }
        }
    }

    static let blockHeight: CGFloat = 74
    static let blockGap: CGFloat = 8
    static let moreRowHeight: CGFloat = 28

    var presentation: Presentation = .ordinary {
        willSet {
            previousFrames = layoutFrames(for: accounts)
        }
        didSet {
            guard oldValue != presentation else { return }
            needsDisplay = true
            needsLayout = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var accounts: [CodexAccountUsageSnapshot] = [] {
        willSet {
            previousFrames = layoutFrames(for: accounts)
        }
        didSet {
            startReorderAnimationIfNeeded(from: oldValue, to: accounts)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onAccountSelected: ((String) -> Void)?
    var onMoreAccounts: (() -> Void)?
    var hasMoreAccounts: Bool {
        accounts.count > visibleAccountLimit
    }
    var expandedContentHeight: CGFloat {
        let rowCount = max(1, visibleRowCount)
        let rowsHeight = CGFloat(rowCount) * Self.blockHeight + CGFloat(max(0, rowCount - 1)) * Self.blockGap
        let footerHeight = hasMoreAccounts ? Self.blockGap + Self.moreRowHeight : 0
        return rowsHeight + footerHeight
    }
    private var previousFrames: [String: NSRect] = [:]
    private var animationStart: CFTimeInterval?
    private var animationTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var hoveredSwitchAccountID: String?

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !accounts.isEmpty else {
            drawEmptyState()
            return
        }

        let ordered = orderedAccounts(accounts)
        let targetFrames = layoutFramesForOrderedAccounts(ordered)
        let progress = animationProgress()

        for account in visibleAccounts(ordered) {
            let target = targetFrames[account.id] ?? .zero
            let frame: NSRect
            if progress < 1, let previous = previousFrames[account.id] {
                frame = interpolate(from: previous, to: target, progress: progress)
            } else {
                frame = target
            }
            drawBlock(account, in: frame)
        }
        if hasMoreAccounts {
            drawMoreRow(in: moreRowRect())
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let account = switchableAccount(at: location) else {
            if hasMoreAccounts, moreRowRect().contains(location) {
                onMoreAccounts?()
                return
            }
            super.mouseDown(with: event)
            return
        }
        onAccountSelected?(account.id)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let nextHoverID = switchableAccount(at: location)?.id
        updateHoveredSwitchAccount(nextHoverID)
        if nextHoverID != nil || (hasMoreAccounts && moreRowRect().contains(location)) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        updateHoveredSwitchAccount(nil)
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let frames = layoutFrames(for: accounts)
        for account in visibleAccounts(orderedAccounts(accounts)) where !account.isCurrent {
            guard let rect = frames[account.id] else { continue }
            addCursorRect(switchButtonRect(for: account, in: rect), cursor: .pointingHand)
        }
        if hasMoreAccounts {
            addCursorRect(moreRowRect(), cursor: .pointingHand)
        }
    }

    private func updateHoveredSwitchAccount(_ accountID: String?) {
        guard hoveredSwitchAccountID != accountID else { return }
        hoveredSwitchAccountID = accountID
        needsDisplay = true
    }

    private func switchableAccount(at point: NSPoint) -> CodexAccountUsageSnapshot? {
        let frames = layoutFrames(for: accounts)
        for account in visibleAccounts(orderedAccounts(accounts)) {
            guard let rect = frames[account.id] else { continue }
            if !account.isCurrent, switchButtonRect(for: account, in: rect).contains(point) {
                return account
            }
        }
        return nil
    }

    private func orderedAccounts(_ value: [CodexAccountUsageSnapshot]) -> [CodexAccountUsageSnapshot] {
        value.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func visibleAccounts(_ ordered: [CodexAccountUsageSnapshot]) -> ArraySlice<CodexAccountUsageSnapshot> {
        ordered.prefix(visibleAccountLimit)
    }

    private func layoutFrames(for value: [CodexAccountUsageSnapshot]) -> [String: NSRect] {
        layoutFramesForOrderedAccounts(orderedAccounts(value))
    }

    private func layoutFramesForOrderedAccounts(_ ordered: [CodexAccountUsageSnapshot]) -> [String: NSRect] {
        var frames: [String: NSRect] = [:]
        let columns = max(1, presentation.columnCount)
        let columnWidth = max(0, (bounds.width - CGFloat(columns - 1) * Self.blockGap) / CGFloat(columns))
        var y = bounds.maxY - Self.blockHeight
        for (index, account) in visibleAccounts(ordered).enumerated() {
            let column = index % columns
            if index > 0, column == 0 {
                y -= Self.blockHeight + Self.blockGap
            }
            let x = CGFloat(column) * (columnWidth + Self.blockGap)
            frames[account.id] = NSRect(x: x, y: y, width: columnWidth, height: Self.blockHeight)
        }
        return frames
    }

    private func startReorderAnimationIfNeeded(
        from oldAccounts: [CodexAccountUsageSnapshot],
        to newAccounts: [CodexAccountUsageSnapshot])
    {
        let oldOrder = visibleAccounts(orderedAccounts(oldAccounts)).map(\.id)
        let newOrder = visibleAccounts(orderedAccounts(newAccounts)).map(\.id)
        guard oldOrder != newOrder, !oldOrder.isEmpty else {
            stopAnimationTimer()
            animationStart = nil
            return
        }

        animationStart = CACurrentMediaTime()
        startAnimationTimer()
    }

    private func animationProgress() -> CGFloat {
        guard let animationStart else { return 1 }
        let raw = min(1, max(0, (CACurrentMediaTime() - animationStart) / Self.reorderAnimationDuration))
        let eased = raw * raw * (3 - 2 * raw)
        if raw >= 1 {
            self.animationStart = nil
            stopAnimationTimer()
        }
        return CGFloat(eased)
    }

    private func interpolate(from: NSRect, to: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress)
    }

    private func startAnimationTimer() {
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func drawEmptyState() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSAttributedString(
            string: "No saved Codex accounts yet",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.48),
                .paragraphStyle: paragraph,
            ])
        text.draw(in: bounds.insetBy(dx: 10, dy: max(0, bounds.height / 2 - 8)))
    }

    private func drawMoreRow(in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor.white.withAlphaComponent(0.055).setFill()
        path.fill()

        let hiddenCount = max(0, accounts.count - visibleAccountLimit)
        let countText = hiddenCount == 1 ? "1 more" : "\(hiddenCount) more"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.8, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72),
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.2, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.38),
        ]
        let title = NSAttributedString(string: "All Accounts", attributes: titleAttributes)
        let detail = NSAttributedString(string: countText, attributes: detailAttributes)
        let titleSize = title.size()
        let detailSize = detail.size()

        let iconRect = NSRect(x: rect.minX + 12, y: rect.midY - 5.5, width: 11, height: 11)
        let chevronRect = NSRect(x: rect.maxX - 22, y: rect.midY - 4.5, width: 9, height: 9)
        drawSymbol("person.2", color: NSColor.white.withAlphaComponent(0.56), in: iconRect)
        title.draw(at: NSPoint(x: iconRect.maxX + 8, y: rect.midY - titleSize.height / 2))
        detail.draw(at: NSPoint(x: chevronRect.minX - detailSize.width - 8, y: rect.midY - detailSize.height / 2))
        drawSymbol("chevron.right", color: NSColor.white.withAlphaComponent(0.34), in: chevronRect)
    }

    private func moreRowRect() -> NSRect {
        let rowCount = max(1, visibleRowCount)
        let y = bounds.maxY
            - CGFloat(rowCount) * Self.blockHeight
            - CGFloat(max(0, rowCount - 1)) * Self.blockGap
            - Self.blockGap
            - Self.moreRowHeight
        return NSRect(x: 0, y: y, width: bounds.width, height: Self.moreRowHeight)
    }

    private func drawBlock(_ account: CodexAccountUsageSnapshot, in rect: NSRect) {
        let block = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        NSColor.white.withAlphaComponent(account.isCurrent ? 0.105 : 0.075).setFill()
        block.fill()

        NSColor.white.withAlphaComponent(account.isCurrent ? 0.18 : 0.10).setStroke()
        block.lineWidth = 1
        block.stroke()

        drawTitle(
            account.label,
            plan: account.plan,
            isCurrent: account.isCurrent,
            isSwitchHovered: hoveredSwitchAccountID == account.id,
            in: rect)
        drawMetric(
            title: "5h",
            percent: account.rateLimits.fiveHourRemainingPercent,
            resetAt: account.rateLimits.fiveHourResetAt,
            in: NSRect(x: rect.minX + 12, y: rect.minY + 28, width: rect.width - 24, height: 14))
        drawMetric(
            title: "7d",
            percent: account.rateLimits.weeklyRemainingPercent,
            resetAt: account.rateLimits.weeklyResetAt,
            in: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 14))
    }

    private func drawTitle(
        _ title: String,
        plan: String?,
        isCurrent: Bool,
        isSwitchHovered: Bool,
        in rect: NSRect)
    {
        let layout = titleLayout(title, plan: plan, in: rect)
        layout.attributed.draw(in: layout.titleRect)

        if let chipRect = layout.chipRect, let plan {
            drawChip(plan, size: chipRect.size, in: chipRect)
        }

        drawSwitchButton(isCurrent: isCurrent, isHovered: isSwitchHovered, in: layout.switchRect)
    }

    private func titleLayout(_ title: String, plan: String?, in rect: NSRect) -> TitleLayout {
        let resolvedChipSize = plan.map { chipSize(for: $0) } ?? NSSize.zero
        let chipGap: CGFloat = plan == nil ? 0 : 7
        let actionGap: CGFloat = 7
        let reservedAccessoryWidth = resolvedChipSize.width + chipGap + actionGap + Self.switchButtonWidth
        let value = truncated(title, maxLength: 38)
        let attributed = NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88),
            ])
        let titleOrigin = NSPoint(x: rect.minX + 12, y: rect.maxY - 23)
        let rightLimit = rect.maxX - 12
        let titleWidth = min(
            ceil(attributed.size().width),
            max(40, rightLimit - titleOrigin.x - reservedAccessoryWidth))
        let titleRect = NSRect(
            x: titleOrigin.x,
            y: titleOrigin.y,
            width: titleWidth,
            height: 14)

        let chipRect: NSRect?
        let switchX: CGFloat
        if plan != nil {
            let rect = NSRect(
                x: titleRect.maxX + chipGap,
                y: rect.maxY - 24,
                width: resolvedChipSize.width,
                height: resolvedChipSize.height)
            chipRect = rect
            switchX = rect.maxX + actionGap
        } else {
            chipRect = nil
            switchX = titleRect.maxX + actionGap
        }

        let switchRect = NSRect(
            x: min(switchX, rightLimit - Self.switchButtonWidth),
            y: rect.maxY - 24,
            width: Self.switchButtonWidth,
            height: Self.switchButtonHeight)
        return TitleLayout(
            attributed: attributed,
            titleRect: titleRect,
            chipRect: chipRect,
            switchRect: switchRect)
    }

    private func drawSwitchButton(isCurrent: Bool, isHovered: Bool, in buttonRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: buttonRect,
            xRadius: buttonRect.height / 2,
            yRadius: buttonRect.height / 2)
        if isCurrent {
            NSColor.systemGreen.withAlphaComponent(0.20).setFill()
            NSColor.systemGreen.withAlphaComponent(0.34).setStroke()
        } else if isHovered {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSColor.systemBlue.withAlphaComponent(0.58).setStroke()
        } else {
            NSColor.white.withAlphaComponent(0.105).setFill()
            NSColor.white.withAlphaComponent(0.18).setStroke()
        }
        path.fill()
        path.lineWidth = 0.8
        path.stroke()

        let symbolName = isCurrent ? "checkmark" : "arrow.left.arrow.right"
        let symbolColor: NSColor
        if isCurrent {
            symbolColor = NSColor.systemGreen.withAlphaComponent(0.95)
        } else if isHovered {
            symbolColor = NSColor.systemBlue.withAlphaComponent(0.98)
        } else {
            symbolColor = NSColor.white.withAlphaComponent(0.76)
        }
        drawSymbol(symbolName, color: symbolColor, in: buttonRect.insetBy(dx: 6.5, dy: 3))
    }

    private func switchButtonRect(for account: CodexAccountUsageSnapshot, in rect: NSRect) -> NSRect {
        titleLayout(account.label, plan: account.plan, in: rect).switchRect
    }

    private func drawSymbol(_ symbolName: String, color: NSColor, in rect: NSRect) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return
        }

        let fallback = symbolName == "checkmark" ? "OK" : "><"
        let attributed = NSAttributedString(
            string: fallback,
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: color,
            ])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    private func chipSize(for text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .bold)])
        return NSSize(width: ceil(size.width) + 12, height: 15)
    }

    private func drawChip(_ text: String, size: NSSize, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.systemBlue.withAlphaComponent(0.24).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82),
            ])
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2))
    }

    private func drawMetric(title: String, percent: Int?, resetAt: Date?, in rect: NSRect) {
        let percentText = percent.map { "\(min(100, max(0, $0)))%" } ?? "--%"
        let resetText = resetAt.map { "resets \(Self.countdown(to: $0))" } ?? "reset --"
        let label = NSAttributedString(
            string: "\(title) \(percentText)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.78),
            ])
        let reset = NSAttributedString(
            string: resetText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.42),
            ])

        label.draw(in: NSRect(x: rect.minX, y: rect.minY + 1, width: 50, height: rect.height))
        reset.draw(in: NSRect(x: rect.maxX - 86, y: rect.minY + 2, width: 86, height: rect.height))

        let trackRect = NSRect(x: rect.minX + 54, y: rect.minY + 4, width: max(0, rect.width - 146), height: 6)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.10).setFill()
        track.fill()

        guard let percent else { return }
        let ratio = CGFloat(min(100, max(0, percent))) / 100
        guard ratio > 0 else { return }
        let fillRect = NSRect(x: trackRect.minX, y: trackRect.minY, width: max(5, trackRect.width * ratio), height: trackRect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
        Self.percentColor(percent).withAlphaComponent(0.88).setFill()
        fill.fill()
    }

    private static func percentColor(_ percent: Int) -> NSColor {
        if percent >= 60 {
            return .systemGreen
        }
        if percent >= 20 {
            return .systemOrange
        }
        return .systemRed
    }

    private static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func truncated(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        let head = value.prefix(maxLength - 8)
        let tail = value.suffix(5)
        return "\(head)...\(tail)"
    }

    private static let reorderAnimationDuration: TimeInterval = 0.28
    private static let switchButtonWidth: CGFloat = 24
    private static let switchButtonHeight: CGFloat = 15

    private var visibleAccountLimit: Int {
        presentation.visibleAccountLimit
    }

    private var visibleRowCount: Int {
        let visibleCount = max(1, min(accounts.count, visibleAccountLimit))
        return Int(ceil(Double(visibleCount) / Double(max(1, presentation.columnCount))))
    }

    private struct TitleLayout {
        let attributed: NSAttributedString
        let titleRect: NSRect
        let chipRect: NSRect?
        let switchRect: NSRect
    }
}

final class RollingTextLabel: NSView {
    var font = NSFont.systemFont(ofSize: NSFont.systemFontSize) {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var textColor = NSColor.labelColor {
        didSet {
            needsDisplay = true
        }
    }

    var lineBreakMode: NSLineBreakMode = .byClipping
    var maximumNumberOfLines = 1

    private var currentValue = NSAttributedString(string: "")
    private var textAnimation: TextAnimation?
    private var animationTimer: Timer?

    override var isFlipped: Bool {
        true
    }

    var stringValue: String {
        currentValue.string
    }

    var attributedStringValue: NSAttributedString {
        get { currentValue }
        set { setAttributedStringValue(newValue, animated: false) }
    }

    override var intrinsicContentSize: NSSize {
        let size = currentValue.size()
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    func setAttributedStringValue(_ value: NSAttributedString, animated: Bool) {
        let previousValue = currentValue
        let previousString = previousValue.string
        currentValue = value
        invalidateIntrinsicContentSize()

        let shouldAnimate = animated &&
            !previousString.isEmpty &&
            previousString != value.string &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            textAnimation = nil
            stopAnimationTimer()
            needsDisplay = true
            return
        }

        textAnimation = TextAnimation(
            previousValue: previousValue,
            currentValue: value,
            startTime: CACurrentMediaTime(),
            duration: Self.animationDuration)
        startAnimationTimer()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !currentValue.string.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        if let textAnimation, textAnimation.isActive {
            drawAnimated(textAnimation)
        } else {
            textAnimation = nil
            draw(currentValue, at: CGPoint(x: 0, y: baselineY(for: currentValue)))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawAnimated(_ animation: TextAnimation) {
        let rawProgress = min(1, max(0, (CACurrentMediaTime() - animation.startTime) / animation.duration))
        let progress = Self.easeInOut(rawProgress)
        let previousGlyphs = Self.glyphs(from: animation.previousValue)
        let currentGlyphs = Self.glyphs(from: animation.currentValue)
        let textHeight = ceil(max(animation.previousValue.size().height, animation.currentValue.size().height))
        let baseY = floor(max(0, (bounds.height - textHeight) / 2))
        var x: CGFloat = 0

        for (index, glyph) in currentGlyphs.enumerated() {
            let previousGlyph = previousGlyphs.indices.contains(index) ? previousGlyphs[index] : nil
            let rollsDigit = glyph.isDigit && previousGlyph?.text != glyph.text
            guard rollsDigit else {
                draw(glyph.attributedValue, at: CGPoint(x: x, y: baseY))
                x += glyph.width
                continue
            }

            let cellWidth = max(glyph.width, previousGlyph?.width ?? glyph.width)
            let clipRect = NSRect(x: x, y: baseY, width: cellWidth, height: textHeight)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clipRect).addClip()

            if let previousGlyph, previousGlyph.isDigit {
                draw(
                    previousGlyph.attributedValue,
                    at: CGPoint(x: x, y: baseY - progress * textHeight),
                    alpha: 1 - progress)
            }
            draw(
                glyph.attributedValue,
                at: CGPoint(x: x, y: baseY + (1 - progress) * textHeight),
                alpha: max(0.2, progress))

            NSGraphicsContext.restoreGraphicsState()
            x += glyph.width
        }
    }

    private func baselineY(for value: NSAttributedString) -> CGFloat {
        let height = ceil(value.size().height)
        return floor(max(0, (bounds.height - height) / 2))
    }

    private func draw(_ value: NSAttributedString, at point: CGPoint, alpha: CGFloat = 1) {
        guard alpha < 1 else {
            value.draw(at: point)
            return
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            value.draw(at: point)
            return
        }
        context.saveGState()
        context.setAlpha(alpha)
        value.draw(at: point)
        context.restoreGState()
    }

    private func startAnimationTimer() {
        animationTimer?.invalidate()
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(animationTimerDidFire(_:)),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func animationTimerDidFire(_: Timer) {
        if let textAnimation, !textAnimation.isActive {
            self.textAnimation = nil
            stopAnimationTimer()
        }
        needsDisplay = true
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private static func glyphs(from value: NSAttributedString) -> [Glyph] {
        let string = value.string as NSString
        var glyphs: [Glyph] = []
        var location = 0
        while location < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: location)
            let attributedValue = value.attributedSubstring(from: range)
            let text = string.substring(with: range)
            glyphs.append(Glyph(
                text: text,
                attributedValue: attributedValue,
                width: ceil(attributedValue.size().width)))
            location = range.location + range.length
        }
        return glyphs
    }

    private static func easeInOut(_ progress: Double) -> CGFloat {
        let clamped = min(1, max(0, progress))
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    private struct TextAnimation {
        let previousValue: NSAttributedString
        let currentValue: NSAttributedString
        let startTime: CFTimeInterval
        let duration: TimeInterval

        var isActive: Bool {
            CACurrentMediaTime() - startTime < duration
        }
    }

    private struct Glyph {
        let text: String
        let attributedValue: NSAttributedString
        let width: CGFloat

        var isDigit: Bool {
            text.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }
    }

    private static let animationDuration: TimeInterval = 0.46
}

final class PinButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setPinned(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    func setPinned(_ pinned: Bool) {
        state = pinned ? .on : .off
        toolTip = pinned ? "Pinned open" : "Auto hide"
        contentTintColor = pinned ? NSColor.white : NSColor.white.withAlphaComponent(0.72)
        layer?.backgroundColor = NSColor.clear.cgColor

        let symbolName = pinned ? "pin.fill" : "pin"
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: pinned ? "Pinned open" : "Auto hide")
        symbol?.isTemplate = true
        image = symbol?.withSymbolConfiguration(configuration)
    }
}

final class SettingsButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = "Settings"
        contentTintColor = NSColor.white.withAlphaComponent(0.72)

        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let symbol = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings")
        symbol?.isTemplate = true
        image = symbol?.withSymbolConfiguration(configuration)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

final class AgentBarPreferences {
    private let defaults: UserDefaults
    private let pinnedKey = "AgentBar.pinnedOpen"
    private let expansionAutoCollapseDelayMillisecondsKey = "AgentBar.expansionAutoCollapseDelayMilliseconds"
    static let defaultExpansionAutoCollapseDelayMilliseconds = 200
    static let minExpansionAutoCollapseDelayMilliseconds = 100
    static let maxExpansionAutoCollapseDelayMilliseconds = 5_000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPinned: Bool {
        get {
            defaults.bool(forKey: pinnedKey)
        }
        set {
            defaults.set(newValue, forKey: pinnedKey)
        }
    }

    var expansionAutoCollapseDelay: TimeInterval {
        TimeInterval(expansionAutoCollapseDelayMilliseconds) / 1_000
    }

    var expansionAutoCollapseDelayMilliseconds: Int {
        get {
            guard defaults.object(forKey: expansionAutoCollapseDelayMillisecondsKey) != nil else {
                return Self.defaultExpansionAutoCollapseDelayMilliseconds
            }
            return Self.clampedExpansionAutoCollapseDelayMilliseconds(defaults.integer(forKey: expansionAutoCollapseDelayMillisecondsKey))
        }
        set {
            defaults.set(Self.clampedExpansionAutoCollapseDelayMilliseconds(newValue), forKey: expansionAutoCollapseDelayMillisecondsKey)
        }
    }

    private static func clampedExpansionAutoCollapseDelayMilliseconds(_ value: Int) -> Int {
        min(max(value, minExpansionAutoCollapseDelayMilliseconds), maxExpansionAutoCollapseDelayMilliseconds)
    }
}

private extension NSScreen {
    var agentBarTopBarHeight: CGFloat {
        let visibleTopInset = max(0, frame.maxY - visibleFrame.maxY)
        let safeTopInset: CGFloat
        if #available(macOS 12.0, *) {
            safeTopInset = safeAreaInsets.top
        } else {
            safeTopInset = 0
        }

        var height = max(visibleTopInset, safeTopInset)
        if let liveMenuBarHeight = AgentBarMenuBarWindowProbe.height(for: self) {
            let visualMenuBarHeight = AgentBarMenuBarWindowProbe.visualHeight(from: liveMenuBarHeight)
            height = height > 0 ? min(height, visualMenuBarHeight) : visualMenuBarHeight
        }

        return max(24, height.rounded(.up))
    }

    var agentBarNotchFrame: NSRect? {
        guard #available(macOS 12.0, *),
              safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea
        else {
            return nil
        }

        let rawWidth = right.minX - left.maxX
        let height = frame.maxY - min(left.minY, right.minY)
        let width = rawWidth + 4
        guard width > 0, height > 0 else { return nil }
        return NSRect(x: left.maxX - 2, y: frame.maxY - height, width: width, height: height)
    }

    var agentBarSupportsAutoHide: Bool {
        agentBarNotchFrame == nil
    }
}

private enum AgentBarMenuBarWindowProbe {
    static func visualHeight(from windowHeight: CGFloat) -> CGFloat {
        windowHeight >= 30 ? windowHeight - 5 : windowHeight
    }

    static func height(for screen: NSScreen) -> CGFloat? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let screenBounds = screen.agentBarMenuBarProbeBounds
        let candidates = windows.compactMap { info -> CGFloat? in
            guard isMenuBarWindow(info),
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            guard bounds.height >= 20,
                  bounds.height <= 80,
                  horizontallyMatches(bounds, screenBounds: screenBounds),
                  verticallyMatches(bounds, screenBounds: screenBounds)
            else {
                return nil
            }

            return bounds.height
        }

        return candidates.max()
    }

    private static func isMenuBarWindow(_ info: [String: Any]) -> Bool {
        let owner = info[kCGWindowOwnerName as String] as? String
        let name = info[kCGWindowName as String] as? String
        return owner == "Window Server" && name == "Menubar"
    }

    private static func horizontallyMatches(_ windowBounds: CGRect, screenBounds: CGRect) -> Bool {
        let overlap = min(windowBounds.maxX, screenBounds.maxX) - max(windowBounds.minX, screenBounds.minX)
        return overlap >= screenBounds.width * 0.8
    }

    private static func verticallyMatches(_ windowBounds: CGRect, screenBounds: CGRect) -> Bool {
        let expectedTop = screenBounds.minY
        return abs(windowBounds.minY - expectedTop) <= 4
    }
}

private extension NSScreen {
    var agentBarMenuBarProbeBounds: CGRect {
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? frame.maxY
        return CGRect(
            x: frame.minX,
            y: desktopTop - frame.maxY,
            width: frame.width,
            height: frame.height)
    }
}
