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
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandWindowController?
    private let updater = AgentBarUpdater()

    func applicationDidFinishLaunching(_: Notification) {
        updater.start()

        let controller = IslandWindowController()
        self.controller = controller
        controller.show()
    }
}

@MainActor
final class IslandWindowController {
    private var overlays: [ScreenOverlay] = []
    private let snapshotService = CodexSnapshotService()
    private let preferences = AgentBarPreferences()
    private var refreshTask: Task<Void, Never>?
    private var hoverTimer: Timer?
    private var currentCosts = CodexCostSnapshot(
        todayCostUSD: 0,
        todayTokens: 0,
        last30DaysCostUSD: 0,
        last30DaysTokens: 0)
    private var currentText = "5h --%   7d --%      Today: $0.00 \u{00B7} -- / ~30 Days: $0.00 \u{00B7} -- Tokens"

    init() {
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
        updateOverlays()

        let snapshot = await snapshotService.snapshot()
        currentCosts = snapshot.costs
        currentText = AgentBarDisplayFormatting.line(snapshot: snapshot)
        updateOverlays()
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
            overlay.view.update(text: currentText)
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

    private func updateOverlays() {
        for overlay in overlays {
            overlay.view.update(text: currentText)
            overlay.view.setPinned(preferences.isPinned)
            position(overlay, animated: false)
        }
        updateHoverState(animated: false)
    }

    private func position(_ overlay: ScreenOverlay, animated: Bool) {
        let targetFrame = targetFrame(for: overlay)
        guard overlay.lastTargetFrame != targetFrame else { return }
        overlay.lastTargetFrame = targetFrame

        let updates = {
            overlay.panel.setFrame(targetFrame, display: true)
        }
        guard animated, autoHideAnimationDuration > 0 else {
            updates()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = autoHideAnimationDuration
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
        overlay.autoHideEligible && !preferences.isPinned && !overlay.isHovered
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

    private var autoHideAnimationDuration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.menuBarAutoHideAnimationDuration
    }

    private static let menuBarAutoHideAnimationDuration: TimeInterval = 0.26
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
    private let fullLabel = NSTextField(labelWithString: "")
    private let quotaLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "")
    private let pinButton = PinButton()
    private var horizontalPadding: CGFloat = 0
    private var notchInnerPadding: CGFloat = 0
    private var notchHeight: CGFloat = 24
    private(set) var notchGapWidth: CGFloat = 0
    private(set) var notchLeftLaneWidth: CGFloat = 0
    private var showsPin = false
    private var isHovering = false
    private var style: Style = .attachedBar(height: 32, showsPin: false)
    var onPinToggle: (() -> Void)?

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
        pinButton.target = self
        pinButton.action = #selector(pinButtonPressed)

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

    func update(text: String) {
        let segments = Self.split(text)
        fullLabel.attributedStringValue = Self.styledFullText(text)
        quotaLabel.attributedStringValue = Self.styledPercentText(segments.sessionPercent)
        usageLabel.attributedStringValue = Self.styledPercentText(segments.weeklyPercent)
        needsLayout = true
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
    }

    @objc private func pinButtonPressed() {
        onPinToggle?()
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
        showsPin ? Self.pinButtonSize.width + Self.pinButtonGap : 0
    }

    private static let iconViewSize = NSSize(width: 16, height: 16)
    private static let pinButtonSize = NSSize(width: 18, height: 18)
    private static let pinButtonGap: CGFloat = 8
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
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
