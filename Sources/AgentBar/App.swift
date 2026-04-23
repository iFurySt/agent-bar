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

    func applicationDidFinishLaunching(_: Notification) {
        let controller = IslandWindowController()
        self.controller = controller
        controller.show()
    }
}

@MainActor
final class IslandWindowController {
    private var overlays: [ScreenOverlay] = []
    private let snapshotService = CodexSnapshotService()
    private var refreshTask: Task<Void, Never>?
    private var currentCosts = CodexCostSnapshot(
        todayCostUSD: 0,
        todayTokens: 0,
        last30DaysCostUSD: 0,
        last30DaysTokens: 0)
    private var currentText = "5h --%   7d --%      Today: $0.00 \u{00B7} -- / ~30 Days: $0.00 \u{00B7} -- Tokens"

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    func show() {
        rebuildOverlays()

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
        overlays = NSScreen.screens.map { screen in
            let overlay = ScreenOverlay(screen: screen)
            overlay.view.update(text: currentText)
            position(overlay)
            overlay.panel.orderFrontRegardless()
            return overlay
        }
    }

    private func updateOverlays() {
        for overlay in overlays {
            overlay.view.update(text: currentText)
            position(overlay)
        }
    }

    private func position(_ overlay: ScreenOverlay) {
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
            overlay.panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            return
        }

        overlay.panel.level = .statusBar
        overlay.view.configure(.attachedBar(height: topBarHeight))

        let maxWidth = max(260, screen.frame.width - 120)
        let targetSize = overlay.view.fittingSize(constrainedTo: maxWidth)
        let width = min(targetSize.width, maxWidth)
        let height = targetSize.height
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        overlay.panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

@MainActor
final class ScreenOverlay {
    let screen: NSScreen
    let panel: NSPanel
    let view: IslandView

    init(screen: NSScreen) {
        self.screen = screen
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
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }
}

final class IslandView: NSView {
    enum Style {
        case attachedBar(height: CGFloat)
        case notch(height: CGFloat, gapWidth: CGFloat)
    }

    private let iconView = NSImageView()
    private let fullLabel = NSTextField(labelWithString: "")
    private let quotaLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(labelWithString: "")
    private var horizontalPadding: CGFloat = 0
    private var notchInnerPadding: CGFloat = 0
    private var notchHeight: CGFloat = 24
    private(set) var notchGapWidth: CGFloat = 0
    private(set) var notchLeftLaneWidth: CGFloat = 0
    private var style: Style = .attachedBar(height: 32)

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
        fullLabel.stringValue = text
        quotaLabel.stringValue = segments.sessionPercent
        usageLabel.stringValue = segments.weeklyPercent
        needsLayout = true
    }

    func configure(_ style: Style) {
        self.style = style
        switch style {
        case let .attachedBar(height):
            horizontalPadding = 18
            notchInnerPadding = 0
            notchHeight = height
            notchGapWidth = 0
            notchLeftLaneWidth = 0
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
        case let .attachedBar(height):
            let iconGap: CGFloat = 8
            let labelSafety: CGFloat = 28
            let fixedWidth = horizontalPadding * 2 + iconViewSize.width + iconGap
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
        let labelWidth = min(
            fullLabel.intrinsicContentSize.width + labelSafety,
            max(0, bounds.width - horizontalPadding * 2 - iconViewSize.width - iconGap))
        let totalWidth = iconViewSize.width + iconGap + labelWidth
        let startX = max(horizontalPadding, floor((bounds.width - totalWidth) / 2))

        iconView.frame = NSRect(x: startX, y: iconY, width: iconViewSize.width, height: iconViewSize.height)
        fullLabel.frame = NSRect(
            x: iconView.frame.maxX + iconGap,
            y: labelY,
            width: labelWidth,
            height: textHeight)
    }

    private func layoutNotch() {
        iconView.isHidden = false

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
        guard let url = Bundle.module.url(forResource: "ProviderIcon-codex", withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        image.size = iconViewSize
        return image
    }

    private var iconViewSize: NSSize {
        Self.iconViewSize
    }

    private static let iconViewSize = NSSize(width: 16, height: 16)
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
}
