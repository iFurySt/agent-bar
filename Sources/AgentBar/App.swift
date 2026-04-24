import AppKit
import AgentBarCore

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
    private var currentCosts = CodexCostSnapshot(
        todayCostUSD: 0,
        todayTokens: 0,
        last30DaysCostUSD: 0,
        last30DaysTokens: 0)
    private var currentText = "5h --%   7d --%      Today: $0.00 \u{00B7} -- / ~30 Days: $0.00 \u{00B7} -- Tokens"

    init(updater: AgentBarUpdater) {
        self.updater = updater

        if let cachedSnapshot = snapshotService.cachedSnapshot() {
            currentCosts = cachedSnapshot.costs
            currentText = AgentBarDisplayFormatting.line(snapshot: cachedSnapshot)
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
        currentText = AgentBarDisplayFormatting.line(snapshot: AgentBarSnapshot(rateLimits: quickRateLimits, costs: currentCosts))
        updateOverlays(animated: true)

        let snapshot = await snapshotService.snapshot()
        currentCosts = snapshot.costs
        currentText = AgentBarDisplayFormatting.line(snapshot: snapshot)
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
                self?.toggleSettings(relativeTo: anchor)
            }
            overlay.view.update(text: currentText, animated: false)
            overlay.view.setPinned(preferences.isPinned)
            overlay.isHovered = isMouseHovering(overlay, at: mouseLocation)
            overlay.isCollapsed = shouldCollapse(overlay)
            overlay.view.setHovering(overlay.isHovered)
            overlay.panel.ignoresMouseEvents = !overlay.isHovered
            position(overlay, animated: false)
            overlay.panel.orderFrontRegardless()
            return overlay
        }
        updateHoverState(animated: false)
    }

    private func updateOverlays(animated: Bool = false) {
        for overlay in overlays {
            let textChanged = overlay.view.update(text: currentText, animated: animated)
            overlay.view.setPinned(preferences.isPinned)
            position(
                overlay,
                animated: animated && textChanged,
                duration: contentUpdateAnimationDuration)
        }
        updateHoverState(animated: false)
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
            overlay.view.configure(.notch(height: max(topBarHeight, notchFrame.height), gapWidth: notchFrame.width))

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
        let x = screen.frame.midX - width / 2
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
            if overlay.isHovered != isHovered {
                overlay.isHovered = isHovered
                overlay.view.setHovering(isHovered)
                overlay.panel.ignoresMouseEvents = !isHovered
            }

            let shouldCollapse = shouldCollapse(overlay)
            guard overlay.isCollapsed != shouldCollapse else { continue }
            overlay.isCollapsed = shouldCollapse
            position(overlay, animated: animated)
        }
    }

    private func shouldCollapse(_ overlay: ScreenOverlay) -> Bool {
        overlay.autoHideEligible &&
            !preferences.isPinned &&
            !overlay.isHovered &&
            !isSettingsOpen(for: overlay)
    }

    private func isMouseHovering(_ overlay: ScreenOverlay, at point: NSPoint) -> Bool {
        guard overlay.autoHideEligible else { return false }
        if overlay.panel.frame.insetBy(dx: -8, dy: -8).contains(point) {
            return true
        }

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

    private func toggleSettings(relativeTo anchor: NSView) {
        let controller: AgentBarSettingsWindowController
        if let existingController = settingsWindowController {
            controller = existingController
        } else {
            let newController = AgentBarSettingsWindowController(updater: updater)
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
        controller.showSettings()
        updateHoverState(animated: true)
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

    private static let menuBarAutoHideAnimationDuration: TimeInterval = 0.26
    private static let contentUpdateAnimationDuration: TimeInterval = 0.44
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
        case notch(height: CGFloat, gapWidth: CGFloat)
    }

    private let iconView = NSImageView()
    private let fullLabel = RollingTextLabel()
    private let quotaLabel = RollingTextLabel()
    private let usageLabel = RollingTextLabel()
    private let pinButton = PinButton()
    private let settingsButton = SettingsButton()
    private var horizontalPadding: CGFloat = 0
    private var notchInnerPadding: CGFloat = 0
    private var notchHeight: CGFloat = 24
    private(set) var notchGapWidth: CGFloat = 0
    private(set) var notchLeftLaneWidth: CGFloat = 0
    private var showsPin = false
    private var isHovering = false
    private var style: Style = .attachedBar(height: 32, showsPin: false)
    var onPinToggle: (() -> Void)?
    var onSettingsOpen: ((NSView) -> Void)?

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
        addSubview(pinButton)
        addSubview(settingsButton)
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
            context.addPath(Self.topAttachedIslandPath(in: bounds))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
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

    func setPinned(_ isPinned: Bool) {
        pinButton.setPinned(isPinned)
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
    }

    func configure(_ style: Style) {
        self.style = style
        switch style {
        case let .attachedBar(height, showsPin):
            horizontalPadding = 18
            notchInnerPadding = 0
            notchHeight = height
            notchGapWidth = 0
            notchLeftLaneWidth = 0
            self.showsPin = showsPin
            pinButton.isHidden = !showsPin
            pinButton.alphaValue = showsPin ? 1 : 0
            settingsButton.isHidden = !showsPin
            settingsButton.alphaValue = showsPin ? 1 : 0
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            fullLabel.lineBreakMode = .byClipping
            fullLabel.isHidden = false
            quotaLabel.isHidden = true
            usageLabel.isHidden = true
        case let .notch(height, gapWidth):
            horizontalPadding = 16
            notchInnerPadding = 2
            notchHeight = max(24, height)
            notchGapWidth = gapWidth
            showsPin = false
            pinButton.isHidden = true
            pinButton.alphaValue = 0
            settingsButton.isHidden = true
            settingsButton.alphaValue = 0
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            quotaLabel.lineBreakMode = .byClipping
            usageLabel.lineBreakMode = .byClipping
            fullLabel.isHidden = true
            quotaLabel.isHidden = false
            usageLabel.isHidden = false
        }
        needsDisplay = true
        needsLayout = true
    }

    func fittingSize(constrainedTo maxWidth: CGFloat) -> NSSize {
        switch style {
        case let .attachedBar(height, _):
            let iconGap: CGFloat = 8
            let labelSafety: CGFloat = 28
            let fixedWidth = horizontalPadding * 2 + iconViewSize.width + iconGap + pinSlotWidth
            let labelWidth = min(
                fullLabel.intrinsicContentSize.width + labelSafety,
                max(0, maxWidth - fixedWidth))
            return NSSize(width: fixedWidth + labelWidth, height: height)
        case .notch:
            let iconWidth = iconViewSize.width
            let iconGap: CGFloat = 8
            let labelSafety: CGFloat = 10
            let leftContentWidth = iconWidth + iconGap + ceil(quotaLabel.intrinsicContentSize.width)
            let rightContentWidth = ceil(usageLabel.intrinsicContentSize.width)
            let leftWidth = ceil(horizontalPadding + leftContentWidth + notchInnerPadding)
            let rightWidth = ceil(notchInnerPadding + rightContentWidth + labelSafety + horizontalPadding)
            notchLeftLaneWidth = leftWidth
            let width = min(maxWidth, leftWidth + notchGapWidth + rightWidth)
            return NSSize(width: width, height: notchHeight)
        }
    }

    private func layoutAttachedBar() {
        iconView.isHidden = false

        let textHeight = ceil(fullLabel.intrinsicContentSize.height)
        let centerY = bounds.midY
        let labelY = floor(centerY - textHeight / 2)
        let iconY = floor(centerY - iconViewSize.height / 2)
        let iconGap: CGFloat = 8
        let labelSafety: CGFloat = 28
        let pinWidth = pinSlotWidth
        let labelWidth = min(
            fullLabel.intrinsicContentSize.width + labelSafety,
            max(0, bounds.width - horizontalPadding * 2 - iconViewSize.width - iconGap - pinWidth))
        let totalWidth = iconViewSize.width + iconGap + labelWidth + pinWidth
        let startX = max(horizontalPadding, floor((bounds.width - totalWidth) / 2))

        iconView.frame = NSRect(x: startX, y: iconY, width: iconViewSize.width, height: iconViewSize.height)
        fullLabel.frame = NSRect(
            x: iconView.frame.maxX + iconGap,
            y: labelY,
            width: labelWidth,
            height: textHeight)
        layoutPinButton(after: fullLabel.frame.maxX, centerY: centerY)
    }

    private func layoutNotch() {
        iconView.isHidden = false
        pinButton.frame = .zero
        settingsButton.frame = .zero

        let textHeight = ceil(max(quotaLabel.intrinsicContentSize.height, usageLabel.intrinsicContentSize.height))
        let centerY = bounds.midY
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
        usageLabel.frame = NSRect(
            x: usageX,
            y: labelY,
            width: min(usageWidth + labelSafety, max(0, bounds.width - usageX - horizontalPadding)),
            height: textHeight)
    }

    private func layoutPinButton(after x: CGFloat, centerY: CGFloat) {
        guard showsPin else {
            pinButton.frame = .zero
            return
        }

        let size = Self.pinButtonSize
        pinButton.frame = NSRect(
            x: x + Self.pinButtonGap,
            y: floor(centerY - size.height / 2),
            width: size.width,
            height: size.height)
        settingsButton.frame = NSRect(
            x: pinButton.frame.maxX + Self.settingsButtonGap,
            y: pinButton.frame.minY,
            width: size.width,
            height: size.height)
    }

    @objc private func pinButtonPressed() {
        onPinToggle?()
    }

    @objc private func settingsButtonPressed() {
        onSettingsOpen?(settingsButton)
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

    private static func topAttachedIslandPath(in rect: CGRect) -> CGPath {
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

    private static let iconViewSize = NSSize(width: 16, height: 16)
    private static let pinButtonSize = NSSize(width: 18, height: 18)
    private static let pinButtonGap: CGFloat = 8
    private static let settingsButtonGap: CGFloat = 6
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
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
}

private extension NSScreen {
    var agentBarTopBarHeight: CGFloat {
        let visibleTopInset = max(0, frame.maxY - visibleFrame.maxY)
        var height = visibleTopInset

        if #available(macOS 12.0, *) {
            height = max(height, safeAreaInsets.top)
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
