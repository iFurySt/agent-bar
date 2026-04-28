import AppKit
import AgentBarCore
import ServiceManagement

enum SettingsPage {
    case general
    case accounts
    case usage
    case about
}

private enum UsageViewMode: Int {
    case day = 0
    case year = 1
}

@MainActor
final class AgentBarSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let settingsViewController: AgentBarSettingsViewController
    private static let defaultWindowSize = NSSize(width: 640, height: 420)
    private static let minimumWindowSize = NSSize(width: 480, height: 380)

    init(
        updater: AgentBarUpdater,
        preferences: AgentBarPreferences,
        accountsProvider: @escaping () -> [CodexAccountUsageSnapshot],
        onAccountSwitch: @escaping (String) -> Void)
    {
        let contentViewController = AgentBarSettingsViewController(
            updater: updater,
            preferences: preferences,
            accountsProvider: accountsProvider)
        contentViewController.onAccountSwitch = onAccountSwitch
        settingsViewController = contentViewController
        let window = AgentBarSettingsWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "AgentBar Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = contentViewController
        window.minSize = Self.minimumWindowSize

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var isShown: Bool {
        window?.isVisible == true
    }

    func showSettings(page: SettingsPage = .general) {
        guard let window else { return }
        settingsViewController.showPage(page)
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func refreshAccounts() {
        settingsViewController.refreshAccounts()
    }

    func windowWillClose(_: Notification) {
        onClose?()
    }
}

final class AgentBarSettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w"
        {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AgentBarSettingsViewController: NSViewController {
    var onAccountSwitch: ((String) -> Void)?

    private let updater: AgentBarUpdater
    private let preferences: AgentBarPreferences
    private let accountsProvider: () -> [CodexAccountUsageSnapshot]
    private let launchAtLogin = AgentBarLaunchAtLoginController()
    private let launchAtLoginSwitch = SettingsSwitch()
    private let automaticUpdatesSwitch = SettingsSwitch()
    private let autoCollapseStepper = NSStepper()
    private let autoCollapseValueLabel = NSTextField(labelWithString: "")
    private let sidebar = SettingsSidebarView()
    private let contentScrollView = NSScrollView()
    private let contentView = SettingsBackgroundView(color: AgentBarSettingsPalette.contentBackground)
    private let titleLabel = NSTextField(labelWithString: "General")
    private let generalCard = SettingsCardView()
    private let accountsCard = SettingsCardView()
    private let accountsListView = SettingsAccountsListView()
    private let accountsSummaryLabel = NSTextField(labelWithString: "Saved Codex accounts")
    private var accountsListHeightConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private let usageCard = SettingsCardView()
    private let usageVibeCard = SettingsCardView()
    private let usageModeControl = NSSegmentedControl(labels: ["Day", "Year"], trackingMode: .selectOne, target: nil, action: nil)
    private let usageDayChartView = TokenUsageHourlyChartView()
    private let usageVibeChartView = VibeCodingTimeChartView()
    private let usageHeatmapScrollView = NSScrollView()
    private let usageHeatmapView = TokenUsageHeatmapView()
    private let usageTooltipOverlayView = UsageTooltipOverlayView()
    private let usageSummaryLabel = NSTextField(labelWithString: "Scanning local Codex sessions...")
    private var usageHeaderContainer: NSView?
    private var usageDayControl: NSView?
    private let usagePreviousDayButton = SettingsIconButton(symbolName: "chevron.left", accessibilityDescription: "Previous day")
    private let usageNextDayButton = SettingsIconButton(symbolName: "chevron.right", accessibilityDescription: "Next day")
    private let usageDayLabel = NSTextField(labelWithString: "")
    private var usageYearControl: NSView?
    private let usagePreviousYearButton = SettingsIconButton(symbolName: "chevron.left", accessibilityDescription: "Previous year")
    private let usageNextYearButton = SettingsIconButton(symbolName: "chevron.right", accessibilityDescription: "Next year")
    private let usageYearLabel = NSTextField(labelWithString: "")
    private var usageViewMode: UsageViewMode = .year
    private static var usageCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
    private var selectedUsageDay = usageCalendar.startOfDay(for: Date())
    private var selectedUsageYear = usageCalendar.component(.year, from: Date())
    private var usageYearRange = usageCalendar.component(.year, from: Date())...usageCalendar.component(.year, from: Date())
    private let usageDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
    private let aboutCard = SettingsCardView()
    private let updateRow = SettingsUpdateRowView()
    private var selectedPage: SettingsPage = .general

    init(
        updater: AgentBarUpdater,
        preferences: AgentBarPreferences,
        accountsProvider: @escaping () -> [CodexAccountUsageSnapshot])
    {
        self.updater = updater
        self.preferences = preferences
        self.accountsProvider = accountsProvider
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = SettingsBackgroundView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 420),
            color: AgentBarSettingsPalette.contentBackground)

        let sidebarDivider = SeparatorView(color: AgentBarSettingsPalette.sidebarDivider)
        configureScrollView(contentScrollView, vertical: true, horizontal: false)
        contentScrollView.documentView = contentView

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor

        let launchRow = settingsRow(title: "Launch at Login", control: launchAtLoginSwitch)
        let separator = InsetSeparatorView(inset: 14)
        let updatesRow = settingsRow(title: "Automatic Updates", control: automaticUpdatesSwitch)
        let separator2 = InsetSeparatorView(inset: 14)
        let autoCollapseRow = autoCollapseDelayRow()
        let accountsHeader = accountsHeaderView()
        let usageHeader = usageHeaderView()
        let githubRow = SettingsLinkRowView(
            title: "GitHub Repository",
            detail: "github.com/iFurySt/agent-bar")
        githubRow.target = self
        githubRow.action = #selector(openGitHub)
        updateRow.target = self
        updateRow.action = #selector(checkForUpdatesFromAbout)

        configureSwitch(launchAtLoginSwitch, action: #selector(launchAtLoginChanged(_:)))
        configureSwitch(automaticUpdatesSwitch, action: #selector(automaticUpdatesChanged(_:)))
        configureAutoCollapseStepper()

        let cardStack = NSStackView(views: [launchRow, separator, updatesRow, separator2, autoCollapseRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        generalCard.addSubview(cardStack)

        accountsListView.onAccountSelected = { [weak self] accountID in
            self?.switchAccount(accountID)
        }
        accountsListView.translatesAutoresizingMaskIntoConstraints = false
        accountsCard.addSubview(accountsListView)

        usageHeaderContainer = usageHeader
        usageHeatmapView.onHoverChanged = { [weak self] rect, entry in
            guard let self, let rect, let entry else {
                self?.usageTooltipOverlayView.hoveredItem = nil
                return
            }
            usageTooltipOverlayView.hoveredHourItem = nil
            usageTooltipOverlayView.hoveredActivityItem = nil
            usageTooltipOverlayView.hoveredItem = (
                rect: usageHeatmapView.convert(rect, to: usageTooltipOverlayView),
                entry: entry)
        }
        usageDayChartView.onHoverChanged = { [weak self] point, hour, buckets in
            guard let self, let point, let hour else {
                self?.usageTooltipOverlayView.hoveredHourItem = nil
                return
            }
            usageTooltipOverlayView.hoveredItem = nil
            usageTooltipOverlayView.hoveredActivityItem = nil
            usageTooltipOverlayView.hoveredHourItem = UsageHourlyTooltipItem(
                point: usageDayChartView.convert(point, to: usageTooltipOverlayView),
                hour: hour,
                buckets: buckets)
        }
        usageVibeChartView.onHoverChanged = { [weak self] point, hour in
            guard let self, let point, let hour else {
                self?.usageTooltipOverlayView.hoveredActivityItem = nil
                return
            }
            usageTooltipOverlayView.hoveredItem = nil
            usageTooltipOverlayView.hoveredHourItem = nil
            usageTooltipOverlayView.hoveredActivityItem = UsageActivityTooltipItem(
                point: usageVibeChartView.convert(point, to: usageTooltipOverlayView),
                hour: hour)
        }
        configureScrollView(usageHeatmapScrollView, vertical: false, horizontal: true)
        usageDayChartView.isHidden = true
        usageVibeCard.isHidden = true
        usageDayChartView.translatesAutoresizingMaskIntoConstraints = false
        usageVibeChartView.translatesAutoresizingMaskIntoConstraints = false
        usageHeatmapView.frame = NSRect(
            x: 0,
            y: 0,
            width: TokenUsageHeatmapView.contentWidth,
            height: TokenUsageHeatmapView.contentHeight)
        usageHeatmapScrollView.documentView = usageHeatmapView
        usageCard.addSubview(usageDayChartView)
        usageCard.addSubview(usageHeatmapScrollView)
        usageVibeCard.addSubview(usageVibeChartView)

        let aboutSeparator = InsetSeparatorView(inset: 20)
        let aboutStack = NSStackView(views: [updateRow, aboutSeparator, githubRow])
        aboutStack.orientation = .vertical
        aboutStack.alignment = .leading
        aboutStack.spacing = 0
        aboutStack.translatesAutoresizingMaskIntoConstraints = false
        aboutCard.addSubview(aboutStack)

        rootView.addSubview(sidebar)
        rootView.addSubview(sidebarDivider)
        rootView.addSubview(contentScrollView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(generalCard)
        contentView.addSubview(accountsHeader)
        contentView.addSubview(accountsCard)
        contentView.addSubview(usageHeader)
        contentView.addSubview(usageCard)
        contentView.addSubview(usageVibeCard)
        contentView.addSubview(aboutCard)
        contentView.addSubview(usageTooltipOverlayView)

        for view in [
            sidebar,
            sidebarDivider,
            contentScrollView,
            contentView,
            titleLabel,
            generalCard,
            accountsHeader,
            accountsCard,
            usageHeader,
            usageCard,
            usageVibeCard,
            usageDayChartView,
            usageVibeChartView,
            usageHeatmapScrollView,
            aboutCard,
            usageTooltipOverlayView,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 150),

            sidebarDivider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarDivider.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebarDivider.widthAnchor.constraint(equalToConstant: 1),

            contentScrollView.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentScrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: contentScrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentScrollView.contentView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: contentScrollView.contentView.topAnchor),
            contentView.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: contentScrollView.contentView.heightAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),

            generalCard.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: 10),
            generalCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            generalCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),

            usageCard.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            usageCard.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            usageCard.topAnchor.constraint(equalTo: usageHeader.bottomAnchor, constant: 10),

            usageVibeCard.leadingAnchor.constraint(equalTo: usageCard.leadingAnchor),
            usageVibeCard.trailingAnchor.constraint(equalTo: usageCard.trailingAnchor),
            usageVibeCard.topAnchor.constraint(equalTo: usageCard.bottomAnchor, constant: 10),

            usageHeader.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor, constant: 8),
            usageHeader.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor, constant: -8),
            usageHeader.topAnchor.constraint(equalTo: generalCard.topAnchor),

            accountsHeader.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor, constant: 8),
            accountsHeader.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor, constant: -8),
            accountsHeader.topAnchor.constraint(equalTo: generalCard.topAnchor),

            accountsCard.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            accountsCard.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            accountsCard.topAnchor.constraint(equalTo: accountsHeader.bottomAnchor, constant: 10),

            aboutCard.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            aboutCard.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            aboutCard.topAnchor.constraint(equalTo: generalCard.topAnchor),

            cardStack.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: generalCard.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: generalCard.bottomAnchor),

            accountsListView.leadingAnchor.constraint(equalTo: accountsCard.leadingAnchor),
            accountsListView.trailingAnchor.constraint(equalTo: accountsCard.trailingAnchor),
            accountsListView.topAnchor.constraint(equalTo: accountsCard.topAnchor),
            accountsListView.bottomAnchor.constraint(equalTo: accountsCard.bottomAnchor),

            aboutStack.leadingAnchor.constraint(equalTo: aboutCard.leadingAnchor),
            aboutStack.trailingAnchor.constraint(equalTo: aboutCard.trailingAnchor),
            aboutStack.topAnchor.constraint(equalTo: aboutCard.topAnchor),
            aboutStack.bottomAnchor.constraint(equalTo: aboutCard.bottomAnchor),

            launchRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            updatesRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            separator2.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            autoCollapseRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            launchRow.heightAnchor.constraint(equalToConstant: 40),
            updatesRow.heightAnchor.constraint(equalToConstant: 40),
            autoCollapseRow.heightAnchor.constraint(equalToConstant: 40),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator2.heightAnchor.constraint(equalToConstant: 0.5),

            usageHeatmapScrollView.leadingAnchor.constraint(equalTo: usageCard.leadingAnchor, constant: 16),
            usageHeatmapScrollView.trailingAnchor.constraint(equalTo: usageCard.trailingAnchor, constant: -16),
            usageHeatmapScrollView.topAnchor.constraint(equalTo: usageCard.topAnchor, constant: 16),
            usageHeatmapScrollView.bottomAnchor.constraint(equalTo: usageCard.bottomAnchor, constant: -16),
            usageHeatmapScrollView.heightAnchor.constraint(equalToConstant: TokenUsageHeatmapView.contentHeight),

            usageDayChartView.leadingAnchor.constraint(equalTo: usageCard.leadingAnchor, constant: 16),
            usageDayChartView.trailingAnchor.constraint(equalTo: usageCard.trailingAnchor, constant: -16),
            usageDayChartView.topAnchor.constraint(equalTo: usageCard.topAnchor, constant: 16),
            usageDayChartView.bottomAnchor.constraint(equalTo: usageCard.bottomAnchor, constant: -16),
            usageDayChartView.heightAnchor.constraint(equalToConstant: TokenUsageHourlyChartView.contentHeight),

            usageVibeChartView.leadingAnchor.constraint(equalTo: usageVibeCard.leadingAnchor, constant: 16),
            usageVibeChartView.trailingAnchor.constraint(equalTo: usageVibeCard.trailingAnchor, constant: -16),
            usageVibeChartView.topAnchor.constraint(equalTo: usageVibeCard.topAnchor, constant: 16),
            usageVibeChartView.bottomAnchor.constraint(equalTo: usageVibeCard.bottomAnchor, constant: -16),
            usageVibeChartView.heightAnchor.constraint(equalToConstant: VibeCodingTimeChartView.contentHeight),

            githubRow.widthAnchor.constraint(equalTo: aboutStack.widthAnchor),
            updateRow.widthAnchor.constraint(equalTo: aboutStack.widthAnchor),
            aboutSeparator.widthAnchor.constraint(equalTo: aboutStack.widthAnchor),
            updateRow.heightAnchor.constraint(equalToConstant: 58),
            aboutSeparator.heightAnchor.constraint(equalToConstant: 0.5),
            githubRow.heightAnchor.constraint(equalToConstant: 48),

            usageTooltipOverlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            usageTooltipOverlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            usageTooltipOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            usageTooltipOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        accountsListHeightConstraint = accountsListView.heightAnchor.constraint(equalToConstant: accountsListView.preferredHeight)
        accountsListHeightConstraint?.isActive = true
        updateContentBottomConstraint(for: selectedPage)

        sidebar.onGeneral = { [weak self] in
            self?.showPage(.general)
        }
        sidebar.onAccounts = { [weak self] in
            self?.showPage(.accounts)
        }
        sidebar.onUsage = { [weak self] in
            self?.showPage(.usage)
        }
        sidebar.onAbout = { [weak self] in
            self?.showPage(.about)
        }

        view = rootView
        updater.onStatusChanged = { [weak self] status in
            self?.applyUpdateStatus(status)
        }
        showPage(selectedPage)
        refreshControls()
        refreshAccounts()
        refreshUsage()
        applyUpdateStatus(updater.status)
    }

    private func configureScrollView(_ scrollView: NSScrollView, vertical: Bool, horizontal: Bool) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = vertical ? .allowed : .none
        scrollView.horizontalScrollElasticity = horizontal ? .allowed : .none
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshControls()
        refreshAccounts()
        applyUpdateStatus(updater.status)
    }

    private func settingsRow(title: String, control: SettingsSwitch) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11.8, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        rowView.addSubview(titleLabel)
        rowView.addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -18),

            control.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -18),
            control.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
        ])

        return rowView
    }

    private func autoCollapseDelayRow() -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Auto Collapse Delay")
        titleLabel.font = .systemFont(ofSize: 11.8, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        autoCollapseValueLabel.font = .monospacedDigitSystemFont(ofSize: 11.8, weight: .medium)
        autoCollapseValueLabel.textColor = .secondaryLabelColor
        autoCollapseValueLabel.alignment = .right
        autoCollapseValueLabel.translatesAutoresizingMaskIntoConstraints = false
        autoCollapseStepper.translatesAutoresizingMaskIntoConstraints = false

        rowView.addSubview(titleLabel)
        rowView.addSubview(autoCollapseValueLabel)
        rowView.addSubview(autoCollapseStepper)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: autoCollapseValueLabel.leadingAnchor, constant: -18),

            autoCollapseStepper.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -18),
            autoCollapseStepper.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),

            autoCollapseValueLabel.trailingAnchor.constraint(equalTo: autoCollapseStepper.leadingAnchor, constant: -8),
            autoCollapseValueLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            autoCollapseValueLabel.widthAnchor.constraint(equalToConstant: 58),
        ])

        return rowView
    }

    private func usageHeaderView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Daily Tokens")
        titleLabel.font = .systemFont(ofSize: 12.8, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        usageSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 11.4, weight: .medium)
        usageSummaryLabel.textColor = .secondaryLabelColor
        usageSummaryLabel.alignment = .right
        usageSummaryLabel.lineBreakMode = .byTruncatingMiddle
        usageSummaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        usageSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        usageSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

        usageModeControl.segmentStyle = .rounded
        usageModeControl.controlSize = .small
        usageModeControl.selectedSegment = usageViewMode.rawValue
        usageModeControl.target = self
        usageModeControl.action = #selector(usageModeChanged(_:))
        usageModeControl.translatesAutoresizingMaskIntoConstraints = false

        usageDayLabel.font = .systemFont(ofSize: 12.4, weight: .semibold)
        usageDayLabel.textColor = .labelColor
        usageDayLabel.alignment = .center
        usageDayLabel.lineBreakMode = .byTruncatingMiddle
        usageDayLabel.translatesAutoresizingMaskIntoConstraints = false
        usagePreviousDayButton.target = self
        usagePreviousDayButton.action = #selector(previousUsageDay)
        usageNextDayButton.target = self
        usageNextDayButton.action = #selector(nextUsageDay)

        let dayControl = NSStackView(views: [usagePreviousDayButton, usageDayLabel, usageNextDayButton])
        dayControl.orientation = .horizontal
        dayControl.alignment = .centerY
        dayControl.spacing = 4
        dayControl.translatesAutoresizingMaskIntoConstraints = false
        usageDayControl = dayControl

        usageYearLabel.font = .monospacedDigitSystemFont(ofSize: 12.4, weight: .semibold)
        usageYearLabel.textColor = .labelColor
        usageYearLabel.alignment = .center
        usageYearLabel.translatesAutoresizingMaskIntoConstraints = false
        usagePreviousYearButton.target = self
        usagePreviousYearButton.action = #selector(previousUsageYear)
        usageNextYearButton.target = self
        usageNextYearButton.action = #selector(nextUsageYear)

        let yearControl = NSStackView(views: [usagePreviousYearButton, usageYearLabel, usageNextYearButton])
        yearControl.orientation = .horizontal
        yearControl.alignment = .centerY
        yearControl.spacing = 4
        yearControl.translatesAutoresizingMaskIntoConstraints = false
        usageYearControl = yearControl

        container.addSubview(titleLabel)
        container.addSubview(usageModeControl)
        container.addSubview(dayControl)
        container.addSubview(yearControl)
        container.addSubview(usageSummaryLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 54),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),

            usageModeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            usageModeControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            usageModeControl.widthAnchor.constraint(equalToConstant: 84),
            usageModeControl.heightAnchor.constraint(equalToConstant: 24),

            dayControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            dayControl.centerYAnchor.constraint(equalTo: usageModeControl.centerYAnchor),
            usagePreviousDayButton.widthAnchor.constraint(equalToConstant: 22),
            usagePreviousDayButton.heightAnchor.constraint(equalToConstant: 22),
            usageNextDayButton.widthAnchor.constraint(equalToConstant: 22),
            usageNextDayButton.heightAnchor.constraint(equalToConstant: 22),
            usageDayLabel.widthAnchor.constraint(equalToConstant: 118),

            yearControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            yearControl.centerYAnchor.constraint(equalTo: usageModeControl.centerYAnchor),
            usagePreviousYearButton.widthAnchor.constraint(equalToConstant: 22),
            usagePreviousYearButton.heightAnchor.constraint(equalToConstant: 22),
            usageNextYearButton.widthAnchor.constraint(equalToConstant: 22),
            usageNextYearButton.heightAnchor.constraint(equalToConstant: 22),
            usageYearLabel.widthAnchor.constraint(equalToConstant: 48),

            usageSummaryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            usageSummaryLabel.centerYAnchor.constraint(equalTo: usageModeControl.centerYAnchor),
            usageSummaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dayControl.trailingAnchor, constant: 10),
            usageSummaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: yearControl.trailingAnchor, constant: 10),
        ])

        return container
    }

    private func accountsHeaderView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Codex Accounts")
        titleLabel.font = .systemFont(ofSize: 12.8, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        accountsSummaryLabel.font = .systemFont(ofSize: 11.4, weight: .regular)
        accountsSummaryLabel.textColor = .secondaryLabelColor
        accountsSummaryLabel.alignment = .right
        accountsSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(accountsSummaryLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accountsSummaryLabel.leadingAnchor, constant: -18),
            accountsSummaryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            accountsSummaryLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func configureSwitch(_ control: SettingsSwitch, action: Selector) {
        control.target = self
        control.action = action
    }

    private func configureAutoCollapseStepper() {
        autoCollapseStepper.minValue = Double(AgentBarPreferences.minExpansionAutoCollapseDelayMilliseconds)
        autoCollapseStepper.maxValue = Double(AgentBarPreferences.maxExpansionAutoCollapseDelayMilliseconds)
        autoCollapseStepper.increment = 100
        autoCollapseStepper.target = self
        autoCollapseStepper.action = #selector(autoCollapseDelayChanged(_:))
    }

    private func refreshControls() {
        launchAtLoginSwitch.isOn = launchAtLogin.isEnabled
        automaticUpdatesSwitch.isOn = updater.automaticallyChecksForUpdates
        let delay = preferences.expansionAutoCollapseDelayMilliseconds
        autoCollapseStepper.doubleValue = Double(delay)
        autoCollapseValueLabel.stringValue = "\(delay) ms"
    }

    private func refreshUsage() {
        let scanner = CodexCostScanner()
        let activityScanner = CodexActivityScanner()
        let year = selectedUsageYear
        let day = selectedUsageDay
        let task = Task.detached(priority: .utility) {
            (
                scanner.yearlyTokenUsage(year: year),
                scanner.usageYearRange(),
                scanner.hourlyTokenUsage(on: day),
                activityScanner.hourlyActivityUsage(on: day))
        }
        Task { [weak self] in
            let (snapshot, yearRange, hourlySnapshot, activitySnapshot) = await task.value
            self?.applyUsage(
                snapshot,
                yearRange: yearRange,
                year: year,
                day: day,
                hourlySnapshot: hourlySnapshot,
                activitySnapshot: activitySnapshot)
        }
    }

    func refreshAccounts() {
        applyAccounts(accountsProvider())
    }

    private func applyAccounts(_ accounts: [CodexAccountUsageSnapshot]) {
        accountsListView.accounts = accounts
        accountsListHeightConstraint?.constant = accountsListView.preferredHeight
        let count = accounts.count
        accountsSummaryLabel.stringValue = count == 1 ? "1 account" : "\(count) accounts"
        updateContentBottomConstraint(for: selectedPage)
    }

    private func applyUsage(
        _ snapshot: CodexDailyTokenUsageSnapshot,
        yearRange: ClosedRange<Int>,
        year: Int,
        day: Date,
        hourlySnapshot: CodexHourlyTokenUsageSnapshot,
        activitySnapshot: CodexActivityUsageSnapshot)
    {
        usageYearRange = yearRange
        selectedUsageYear = min(max(year, yearRange.lowerBound), yearRange.upperBound)
        selectedUsageDay = Self.usageCalendar.startOfDay(for: day)
        usageHeatmapView.snapshot = snapshot
        usageDayChartView.snapshot = hourlySnapshot
        usageVibeChartView.snapshot = activitySnapshot
        usageYearLabel.stringValue = "\(selectedUsageYear)"
        usagePreviousYearButton.isEnabled = selectedUsageYear > usageYearRange.lowerBound
        usageNextYearButton.isEnabled = selectedUsageYear < usageYearRange.upperBound
        updateUsageDayControls()
        updateUsageSummaryLabel()
        updateUsageModeVisibility()
    }

    @objc private func previousUsageDay() {
        guard let day = Self.usageCalendar.date(byAdding: .day, value: -1, to: selectedUsageDay) else { return }
        selectedUsageDay = Self.usageCalendar.startOfDay(for: day)
        updateUsageDayControls()
        refreshUsage()
    }

    @objc private func nextUsageDay() {
        let today = Self.usageCalendar.startOfDay(for: Date())
        guard selectedUsageDay < today,
              let day = Self.usageCalendar.date(byAdding: .day, value: 1, to: selectedUsageDay)
        else { return }
        selectedUsageDay = min(Self.usageCalendar.startOfDay(for: day), today)
        updateUsageDayControls()
        refreshUsage()
    }

    @objc private func previousUsageYear() {
        guard selectedUsageYear > usageYearRange.lowerBound else { return }
        selectedUsageYear -= 1
        refreshUsage()
    }

    @objc private func nextUsageYear() {
        guard selectedUsageYear < usageYearRange.upperBound else { return }
        selectedUsageYear += 1
        refreshUsage()
    }

    @objc private func launchAtLoginChanged(_ sender: SettingsSwitch) {
        do {
            try launchAtLogin.setEnabled(sender.isOn)
        } catch {
            showError(title: "Launch at Login", message: error.localizedDescription)
        }
        refreshControls()
    }

    @objc private func automaticUpdatesChanged(_ sender: SettingsSwitch) {
        updater.automaticallyChecksForUpdates = sender.isOn
        refreshControls()
    }

    @objc private func autoCollapseDelayChanged(_ sender: NSStepper) {
        preferences.expansionAutoCollapseDelayMilliseconds = Int(sender.doubleValue)
        refreshControls()
    }

    func showPage(_ page: SettingsPage) {
        selectedPage = page
        switch page {
        case .general:
            titleLabel.stringValue = "General"
        case .accounts:
            titleLabel.stringValue = "Accounts"
            refreshAccounts()
        case .usage:
            titleLabel.stringValue = "Usage"
        case .about:
            titleLabel.stringValue = "About"
            updater.refreshUpdateStatus()
        }
        generalCard.isHidden = page != .general
        accountsSummaryLabel.superview?.isHidden = page != .accounts
        accountsCard.isHidden = page != .accounts
        usageHeaderContainer?.isHidden = page != .usage
        usageCard.isHidden = page != .usage
        updateUsageModeVisibility()
        aboutCard.isHidden = page != .about
        sidebar.select(page)
    }

    private func updateContentBottomConstraint(for page: SettingsPage) {
        contentBottomConstraint?.isActive = false
        let targetView: NSView
        switch page {
        case .general:
            targetView = generalCard
        case .accounts:
            targetView = accountsCard
        case .usage:
            targetView = usageViewMode == .day ? usageVibeCard : usageCard
        case .about:
            targetView = aboutCard
        }
        let constraint = contentView.bottomAnchor.constraint(greaterThanOrEqualTo: targetView.bottomAnchor, constant: 18)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        contentBottomConstraint = constraint
    }

    private static func formatTokens(_ tokens: Int) -> String {
        AgentBarDisplayFormatting.tokens(tokens)
    }

    private func updateUsageSummaryLabel() {
        switch usageViewMode {
        case .day:
            usageSummaryLabel.stringValue = "Total \(Self.formatTokens(usageDayChartView.snapshot.totalTokens)) Tokens"
        case .year:
            usageSummaryLabel.stringValue = "Total \(Self.formatTokens(usageHeatmapView.snapshot.totalTokens)) Tokens"
        }
    }

    private func updateUsageDayControls() {
        usageDayLabel.stringValue = usageDayFormatter.string(from: selectedUsageDay)
        usageNextDayButton.isEnabled = selectedUsageDay < Self.usageCalendar.startOfDay(for: Date())
    }

    private func updateUsageModeVisibility() {
        usageModeControl.selectedSegment = usageViewMode.rawValue
        let showingUsage = selectedPage == .usage
        let showingYear = showingUsage && usageViewMode == .year
        let showingDay = showingUsage && usageViewMode == .day
        usageDayControl?.isHidden = !showingDay
        usageYearControl?.isHidden = !showingYear
        usageSummaryLabel.isHidden = !showingYear
        usageHeatmapScrollView.isHidden = !showingYear
        usageDayChartView.isHidden = !showingDay
        usageVibeCard.isHidden = !showingDay
        usageTooltipOverlayView.isHidden = !showingUsage
        updateUsageSummaryLabel()
        if !showingYear {
            usageTooltipOverlayView.hoveredItem = nil
        }
        if !showingDay {
            usageTooltipOverlayView.hoveredHourItem = nil
            usageTooltipOverlayView.hoveredActivityItem = nil
        }
        updateContentBottomConstraint(for: selectedPage)
    }

    @objc private func usageModeChanged(_ sender: NSSegmentedControl) {
        guard let mode = UsageViewMode(rawValue: sender.selectedSegment), usageViewMode != mode else { return }
        usageViewMode = mode
        updateUsageModeVisibility()
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/iFurySt/agent-bar") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdatesFromAbout() {
        updater.checkForUpdatesFromAbout()
        applyUpdateStatus(updater.status)
    }

    private func applyUpdateStatus(_ status: AgentBarUpdateStatus) {
        updateRow.status = status
    }

    private func switchAccount(_ accountID: String) {
        onAccountSwitch?(accountID)
        refreshAccounts()
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
final class SettingsSidebarView: NSView {
    var onGeneral: (() -> Void)?
    var onAccounts: (() -> Void)?
    var onUsage: (() -> Void)?
    var onAbout: (() -> Void)?

    private let selectedButton = SidebarItemView(title: "General", symbolName: "gearshape", selected: true)
    private let accountsButton = SidebarItemView(title: "Accounts", symbolName: "person.2", selected: false)
    private let usageButton = SidebarItemView(title: "Usage", symbolName: "chart.bar.xaxis", selected: false)
    private let aboutButton = SidebarItemView(title: "About", symbolName: "info.circle", selected: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackgroundColor()

        selectedButton.target = self
        selectedButton.action = #selector(generalPressed)
        accountsButton.target = self
        accountsButton.action = #selector(accountsPressed)
        usageButton.target = self
        usageButton.action = #selector(usagePressed)
        aboutButton.target = self
        aboutButton.action = #selector(aboutPressed)

        let stackView = NSStackView(views: [selectedButton, accountsButton, usageButton, aboutButton])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 38),
            selectedButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            accountsButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            usageButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            aboutButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            selectedButton.heightAnchor.constraint(equalToConstant: 28),
            accountsButton.heightAnchor.constraint(equalToConstant: 28),
            usageButton.heightAnchor.constraint(equalToConstant: 28),
            aboutButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundColor()
    }

    fileprivate func select(_ page: SettingsPage) {
        selectedButton.isSelected = page == .general
        accountsButton.isSelected = page == .accounts
        usageButton.isSelected = page == .usage
        aboutButton.isSelected = page == .about
    }

    @objc private func generalPressed() {
        onGeneral?()
    }

    @objc private func accountsPressed() {
        onAccounts?()
    }

    @objc private func usagePressed() {
        onUsage?()
    }

    @objc private func aboutPressed() {
        onAbout?()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = AgentBarSettingsPalette.sidebarBackground.resolvedCGColor(for: effectiveAppearance)
    }
}

final class SidebarItemView: NSControl {
    var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }
    private let imageView = NSImageView()
    private let titleLabel: NSTextField

    init(title: String, symbolName: String, selected: Bool) {
        isSelected = selected
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        imageView.imageScaling = .scaleProportionallyDown
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            image.isTemplate = true
            imageView.image = image.withSymbolConfiguration(.init(pointSize: 11.5, weight: .semibold))
        }

        addSubview(imageView)
        addSubview(titleLabel)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateSelectionAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        guard !isSelected else { return }
        sendAction(action, to: target)
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = isSelected ? AgentBarSettingsPalette.selection.cgColor : NSColor.clear.cgColor
    }

    private func updateSelectionAppearance() {
        layer?.backgroundColor = isSelected ? AgentBarSettingsPalette.selection.cgColor : NSColor.clear.cgColor
        imageView.contentTintColor = isSelected ? .white : AgentBarSettingsPalette.selection
        titleLabel.font = .systemFont(ofSize: 11.8, weight: isSelected ? .semibold : .regular)
        titleLabel.textColor = isSelected ? .white : .labelColor
    }
}

final class SettingsAccountsListView: NSView {
    var accounts: [CodexAccountUsageSnapshot] = [] {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
            resetCursorRects()
        }
    }
    var onAccountSelected: ((String) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var hoveredSwitchAccountID: String?

    var preferredHeight: CGFloat {
        guard !accounts.isEmpty else { return 112 }
        return CGFloat(accounts.count) * Self.rowHeight
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: preferredHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !accounts.isEmpty else {
            drawEmptyState()
            return
        }

        let ordered = orderedAccounts()
        for (index, account) in ordered.enumerated() {
            let rect = rowRect(at: index)
            guard rect.intersects(dirtyRect) else { continue }
            drawRow(account, in: rect)
            if index < ordered.count - 1 {
                AgentBarSettingsPalette.separator.setFill()
                NSBezierPath(rect: NSRect(x: rect.minX + 20, y: rect.maxY - 1, width: rect.width - 40, height: 1)).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let account = account(at: point), !account.isCurrent else {
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
        let point = convert(event.locationInWindow, from: nil)
        let accountID = switchableAccount(at: point)?.id
        updateHoveredSwitchAccount(accountID)
        if accountID != nil {
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
        for (index, account) in orderedAccounts().enumerated() where !account.isCurrent {
            addCursorRect(switchRect(for: account, in: rowRect(at: index)), cursor: .pointingHand)
        }
    }

    private func account(at point: NSPoint) -> CodexAccountUsageSnapshot? {
        let ordered = orderedAccounts()
        guard point.y >= 0 else { return nil }
        for index in ordered.indices {
            let account = ordered[index]
            if switchRect(for: account, in: rowRect(at: index)).contains(point) {
                return account
            }
        }
        return nil
    }

    private func switchableAccount(at point: NSPoint) -> CodexAccountUsageSnapshot? {
        guard let account = account(at: point), !account.isCurrent else { return nil }
        return account
    }

    private func updateHoveredSwitchAccount(_ accountID: String?) {
        guard hoveredSwitchAccountID != accountID else { return }
        hoveredSwitchAccountID = accountID
        needsDisplay = true
    }

    private func orderedAccounts() -> [CodexAccountUsageSnapshot] {
        accounts.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    private func rowRect(at index: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
    }

    private func drawEmptyState() {
        let text = "No saved Codex accounts yet"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func drawRow(_ account: CodexAccountUsageSnapshot, in rect: NSRect) {
        let layout = titleLayout(account.label, plan: account.plan, in: rect)
        let title = attributedTitle(account.label)
        title.draw(in: layout.titleRect)

        if let plan = account.plan, let chipRect = layout.chipRect {
            drawChip(plan, in: chipRect)
        }
        drawSwitchButton(
            isCurrent: account.isCurrent,
            isHovered: hoveredSwitchAccountID == account.id,
            in: layout.switchRect)

        let metricWidth = max(0, rect.width - 40)
        drawMetric(
            title: "5h",
            percent: account.rateLimits.fiveHourRemainingPercent,
            resetAt: account.rateLimits.fiveHourResetAt,
            in: NSRect(x: rect.minX + 20, y: rect.minY + 32, width: metricWidth, height: 12))
        drawMetric(
            title: "7d",
            percent: account.rateLimits.weeklyRemainingPercent,
            resetAt: account.rateLimits.weeklyResetAt,
            in: NSRect(x: rect.minX + 20, y: rect.minY + 49, width: metricWidth, height: 12))
    }

    private func switchRect(for account: CodexAccountUsageSnapshot, in rect: NSRect) -> NSRect {
        titleLayout(account.label, plan: account.plan, in: rect).switchRect
    }

    private func titleLayout(_ title: String, plan: String?, in rect: NSRect) -> TitleLayout {
        let title = attributedTitle(title)
        let resolvedChipSize = plan.map { chipSize(for: $0) } ?? NSSize.zero
        let chipGap: CGFloat = plan == nil ? 0 : 7
        let switchGap: CGFloat = 6
        let rightLimit = rect.maxX - 20
        let reservedWidth = resolvedChipSize.width + chipGap + switchGap + Self.switchButtonWidth
        let titleWidth = min(
            ceil(title.size().width),
            max(60, rightLimit - rect.minX - 20 - reservedWidth))
        let titleRect = NSRect(x: rect.minX + 20, y: rect.minY + 12, width: titleWidth, height: 14)

        let chipRect: NSRect?
        let switchX: CGFloat
        if plan != nil {
            let rect = NSRect(
                x: titleRect.maxX + chipGap,
                y: rect.minY + 11,
                width: resolvedChipSize.width,
                height: resolvedChipSize.height)
            chipRect = rect
            switchX = rect.maxX + switchGap
        } else {
            chipRect = nil
            switchX = titleRect.maxX + switchGap
        }

        let switchRect = NSRect(
            x: min(switchX, rightLimit - Self.switchButtonWidth),
            y: rect.minY + 11,
            width: Self.switchButtonWidth,
            height: Self.switchButtonHeight)
        return TitleLayout(titleRect: titleRect, chipRect: chipRect, switchRect: switchRect)
    }

    private func attributedTitle(_ value: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        return NSAttributedString(
            string: truncated(value, maxLength: 38),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.8, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
    }

    private func drawMetric(title: String, percent: Int?, resetAt: Date?, in rect: NSRect) {
        let percentText = percent.map { "\(min(100, max(0, $0)))%" } ?? "--%"
        let resetText = resetAt.map { Self.countdown(to: $0) } ?? "--"
        let label = NSAttributedString(
            string: "\(title) \(percentText)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9.7, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        let reset = NSAttributedString(
            string: resetText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 8.8, weight: .medium),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])

        label.draw(in: NSRect(x: rect.minX, y: rect.minY, width: 46, height: rect.height))
        reset.draw(in: NSRect(x: rect.maxX - 54, y: rect.minY + 1, width: 54, height: rect.height))

        let trackRect = NSRect(x: rect.minX + 51, y: rect.minY + 4, width: max(0, rect.width - 111), height: 5)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
        AgentBarSettingsPalette.separator.withAlphaComponent(0.72).setFill()
        track.fill()

        guard let percent else { return }
        let ratio = CGFloat(min(100, max(0, percent))) / 100
        guard ratio > 0 else { return }
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(4, trackRect.width * ratio),
            height: trackRect.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
        Self.percentColor(percent).withAlphaComponent(0.86).setFill()
        fill.fill()
    }

    private func drawSwitchButton(isCurrent: Bool, isHovered: Bool, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        if isCurrent {
            NSColor.systemGreen.withAlphaComponent(0.12).setFill()
            NSColor.systemGreen.withAlphaComponent(0.26).setStroke()
        } else if isHovered {
            AgentBarSettingsPalette.controlHoverBackground.setFill()
            AgentBarSettingsPalette.selection.withAlphaComponent(0.58).setStroke()
        } else {
            AgentBarSettingsPalette.controlBackground.setFill()
            AgentBarSettingsPalette.cardBorder.setStroke()
        }
        path.fill()
        path.lineWidth = 0.8
        path.stroke()

        let symbolName = isCurrent ? "checkmark" : "arrow.left.arrow.right"
        let symbolColor = isCurrent ? NSColor.systemGreen : AgentBarSettingsPalette.selection.withAlphaComponent(isHovered ? 1 : 0.82)
        drawSymbol(symbolName, color: symbolColor, in: rect.insetBy(dx: 5.6, dy: 3))
    }

    private func drawSymbol(_ symbolName: String, color: NSColor, in rect: NSRect) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        {
            image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil)
            return
        }

        let fallback = symbolName == "checkmark" ? "OK" : "><"
        let attributed = NSAttributedString(
            string: fallback,
            attributes: [
                .font: NSFont.systemFont(ofSize: 7, weight: .bold),
                .foregroundColor: color,
            ])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    private func chipSize(for text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .bold)])
        return NSSize(width: ceil(size.width) + 12, height: 15)
    }

    private func drawChip(_ text: String, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.24).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor.systemBlue,
            ])
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
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

    private static let rowHeight: CGFloat = 72
    private static let switchButtonWidth: CGFloat = 24
    private static let switchButtonHeight: CGFloat = 15

    private struct TitleLayout {
        let titleRect: NSRect
        let chipRect: NSRect?
        let switchRect: NSRect
    }
}

final class SettingsUpdateRowView: NSControl {
    var status: AgentBarUpdateStatus = AgentBarUpdateStatus(
        currentVersion: "0.0.0-dev",
        latestVersion: nil,
        state: .idle,
        canCheckForUpdates: false)
    {
        didSet {
            updateContent()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "Version")
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "Check", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11.8, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.font = .systemFont(ofSize: 11, weight: .medium)
        actionButton.target = self
        actionButton.action = #selector(actionPressed)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, statusLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(textStack)
        addSubview(actionButton)

        textStack.translatesAutoresizingMaskIntoConstraints = false
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -14),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateContent()
    }

    private func updateContent() {
        titleLabel.stringValue = "Version \(status.currentVersion)"
        statusLabel.stringValue = statusText
        actionButton.title = actionTitle
        actionButton.isEnabled = status.canCheckForUpdates && !isChecking
    }

    private var isChecking: Bool {
        if case .checking = status.state {
            return true
        }
        return false
    }

    private var statusText: String {
        switch status.state {
        case .idle:
            return "Update status not checked yet"
        case .checking:
            return "Checking for updates..."
        case .upToDate:
            if let latestVersion = status.latestVersion, latestVersion != status.currentVersion {
                return "Latest compatible version is \(latestVersion)"
            }
            return "You are up to date"
        case .updateAvailable:
            return "AgentBar \(status.latestVersion ?? "newer version") is available"
        case let .failed(message):
            return "Update check failed: \(message)"
        }
    }

    private var actionTitle: String {
        switch status.state {
        case .checking:
            return "Checking..."
        case .updateAvailable:
            return "Update"
        default:
            return "Check"
        }
    }

    @objc private func actionPressed() {
        sendAction(action, to: target)
    }
}

final class SettingsLinkRowView: NSControl {
    init(title: String, detail: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11.8, weight: .regular)
        titleLabel.textColor = .labelColor

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let chevronView = NSImageView()
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = .tertiaryLabelColor
        if let image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open GitHub") {
            image.isTemplate = true
            chevronView.image = image.withSymbolConfiguration(.init(pointSize: 11.5, weight: .medium))
        }

        addSubview(textStack)
        addSubview(chevronView)

        textStack.translatesAutoresizingMaskIntoConstraints = false
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -16),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 16),
            chevronView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

final class TokenUsageHeatmapView: NSView {
    private static let cellSize: CGFloat = 11
    private static let cellGap: CGFloat = 4
    private static let leftLabelWidth: CGFloat = 36
    private static let monthLabelHeight: CGFloat = 24
    private static let weekCount: CGFloat = 54
    static let contentHeight: CGFloat = 142
    static let contentWidth: CGFloat = leftLabelWidth + weekCount * (cellSize + cellGap)

    var snapshot = CodexDailyTokenUsageSnapshot(days: []) {
        didSet {
            hoveredItem = nil
            onHoverChanged?(nil, nil)
            needsDisplay = true
        }
    }
    var onHoverChanged: ((NSRect?, CodexDailyTokenUsage?) -> Void)?

    private static let tooltipVerticalPadding: CGFloat = 14
    private static let tooltipHorizontalPadding: CGFloat = 14
    private var cellRects: [(rect: NSRect, entry: CodexDailyTokenUsage)] = []
    private var hoveredItem: (rect: NSRect, entry: CodexDailyTokenUsage)?
    private var trackingArea: NSTrackingArea?
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.contentWidth, height: Self.contentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let entries = snapshot.days
        guard !entries.isEmpty else {
            drawEmptyState()
            return
        }

        cellRects = makeCellRects(for: entries)
        drawMonthLabels(entries: entries)
        drawWeekdayLabels()
        for item in cellRects where item.rect.intersects(dirtyRect) {
            color(for: item.entry.tokens, maxTokens: snapshot.maxDailyTokens).setFill()
            NSBezierPath(roundedRect: item.rect, xRadius: 3, yRadius: 3).fill()
        }

        if let hoveredItem {
            AgentBarSettingsPalette.heatmapHoverStroke.setStroke()
            let outline = hoveredItem.rect.insetBy(dx: -2, dy: -2)
            let path = NSBezierPath(roundedRect: outline, xRadius: 4, yRadius: 4)
            path.lineWidth = 2
            path.stroke()
        }
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
        let point = convert(event.locationInWindow, from: nil)
        let next = cellRects.first { $0.rect.contains(point) }
        guard next?.entry.dayKey != hoveredItem?.entry.dayKey else { return }
        hoveredItem = next
        onHoverChanged?(next?.rect, next?.entry)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredItem = nil
        onHoverChanged?(nil, nil)
        needsDisplay = true
    }

    private func drawEmptyState() {
        let text = "No local Codex token usage yet"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.8, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes)
    }

    private func makeCellRects(for entries: [CodexDailyTokenUsage]) -> [(rect: NSRect, entry: CodexDailyTokenUsage)] {
        guard let first = entries.first else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let weekday = calendar.component(.weekday, from: first.day) - 1
        let pitch = Self.cellSize + Self.cellGap
        let totalWidth = Self.weekCount * pitch - Self.cellGap
        let originX = Self.leftLabelWidth + max(0, (bounds.width - Self.leftLabelWidth - totalWidth) / 2)
        let originY = max(0, bounds.height - Self.monthLabelHeight - CGFloat(7) * pitch - 4)

        return entries.enumerated().map { offset, entry in
            let absoluteDay = weekday + offset
            let week = absoluteDay / 7
            let day = absoluteDay % 7
            let rect = NSRect(
                x: originX + CGFloat(week) * pitch,
                y: originY + CGFloat(6 - day) * pitch,
                width: Self.cellSize,
                height: Self.cellSize)
            return (rect, entry)
        }
    }

    private func drawMonthLabels(entries: [CodexDailyTokenUsage]) {
        guard !cellRects.isEmpty else { return }
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        var drawnMonths: Set<Int> = []
        let labelY = (cellRects.map { $0.rect.maxY }.max() ?? 0) + 10
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]

        for (index, item) in cellRects.enumerated() {
            let entry = entries[index]
            let day = calendar.component(.day, from: entry.day)
            let month = calendar.component(.month, from: entry.day)
            guard day <= 7, !drawnMonths.contains(month) else { continue }
            drawnMonths.insert(month)
            formatter.string(from: entry.day).draw(
                at: NSPoint(x: item.rect.minX, y: labelY),
                withAttributes: attributes)
        }
    }

    private func drawWeekdayLabels() {
        guard !cellRects.isEmpty else { return }
        let pitch = Self.cellSize + Self.cellGap
        let labels: [(String, Int)] = [("Mon", 1), ("Wed", 3), ("Fri", 5)]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let labelHeight = "Mon".size(withAttributes: attributes).height
        let topCellMaxY = cellRects.map { $0.rect.maxY }.max() ?? 0

        for (label, weekdayIndex) in labels {
            let rowCenterY = topCellMaxY - CGFloat(weekdayIndex) * pitch - Self.cellSize / 2
            let y = rowCenterY - labelHeight / 2
            label.draw(at: NSPoint(x: 0, y: y), withAttributes: attributes)
        }
    }

    fileprivate static func drawTooltip(
        for item: (rect: NSRect, entry: CodexDailyTokenUsage),
        in bounds: NSRect,
        dateFormatter: DateFormatter)
    {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.8, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let costAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.6, weight: .medium),
            .foregroundColor: AgentBarSettingsPalette.heatmapTooltipCost,
        ]
        let tokenAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.6, weight: .medium),
            .foregroundColor: AgentBarSettingsPalette.heatmapTooltipTokens,
        ]
        let title = dateFormatter.string(from: item.entry.day)
        let cost = Self.formatCost(item.entry.costUSD)
        let tokens = "\(Self.formatTokens(item.entry.tokens)) Tokens"
        let titleSize = title.size(withAttributes: titleAttributes)
        let costSize = cost.size(withAttributes: costAttributes)
        let tokenSize = tokens.size(withAttributes: tokenAttributes)
        let tooltipWidth = max(titleSize.width, costSize.width, tokenSize.width) + tooltipHorizontalPadding * 2
        let tooltipHeight = titleSize.height + costSize.height + tokenSize.height + tooltipVerticalPadding * 2 + 10
        let preferredX = item.rect.midX - tooltipWidth / 2
        let x = min(max(0, preferredX), max(0, bounds.width - tooltipWidth))
        let yAbove = item.rect.maxY + 12
        let fitsAbove = yAbove + tooltipHeight <= bounds.height
        let yBelow = item.rect.minY - tooltipHeight - 12
        let y = fitsAbove ? yAbove : max(0, yBelow)
        let rect = NSRect(x: x, y: y, width: tooltipWidth, height: tooltipHeight)

        AgentBarSettingsPalette.heatmapTooltipBackground.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()

        let pointer = NSBezierPath()
        let pointerX = min(max(item.rect.midX, rect.minX + 14), rect.maxX - 14)
        if fitsAbove {
            pointer.move(to: NSPoint(x: pointerX - 8, y: rect.minY))
            pointer.line(to: NSPoint(x: pointerX, y: rect.minY - 9))
            pointer.line(to: NSPoint(x: pointerX + 8, y: rect.minY))
        } else {
            pointer.move(to: NSPoint(x: pointerX - 8, y: rect.maxY))
            pointer.line(to: NSPoint(x: pointerX, y: rect.maxY + 9))
            pointer.line(to: NSPoint(x: pointerX + 8, y: rect.maxY))
        }
        pointer.close()
        pointer.fill()

        title.draw(
            at: NSPoint(x: rect.minX + tooltipHorizontalPadding, y: rect.maxY - tooltipVerticalPadding - titleSize.height),
            withAttributes: titleAttributes)
        cost.draw(
            at: NSPoint(x: rect.minX + tooltipHorizontalPadding, y: rect.maxY - tooltipVerticalPadding - titleSize.height - 22),
            withAttributes: costAttributes)
        tokens.draw(
            at: NSPoint(x: rect.minX + tooltipHorizontalPadding, y: rect.maxY - tooltipVerticalPadding - titleSize.height - 42),
            withAttributes: tokenAttributes)
    }

    private static func formatCost(_ cost: Double) -> String {
        if cost < 0.005 {
            return String(format: "$%.4f spent", cost)
        }
        return String(format: "$%.2f spent", cost)
    }

    private static func formatTokens(_ tokens: Int) -> String {
        AgentBarDisplayFormatting.tokens(tokens)
    }

    private func color(for tokens: Int, maxTokens: Int) -> NSColor {
        guard tokens > 0, maxTokens > 0 else {
            return AgentBarSettingsPalette.heatmapEmpty
        }

        let ratio = Double(tokens) / Double(maxTokens)
        switch ratio {
        case 0..<0.18:
            return AgentBarSettingsPalette.heatmapLevel1
        case 0..<0.38:
            return AgentBarSettingsPalette.heatmapLevel2
        case 0..<0.68:
            return AgentBarSettingsPalette.heatmapLevel3
        default:
            return AgentBarSettingsPalette.heatmapLevel4
        }
    }
}

fileprivate struct UsageHourlyTooltipItem {
    let point: NSPoint
    let hour: CodexHourlyTokenUsage
    let buckets: [UsageHourlyTooltipBucket]
}

fileprivate struct UsageHourlyTooltipBucket {
    let title: String
    let tokens: Int
}

fileprivate struct UsageActivityTooltipItem {
    let point: NSPoint
    let hour: CodexActivityHourUsage
}

final class UsageTooltipOverlayView: NSView {
    var hoveredItem: (rect: NSRect, entry: CodexDailyTokenUsage)? {
        didSet {
            needsDisplay = true
        }
    }
    fileprivate var hoveredHourItem: UsageHourlyTooltipItem? {
        didSet {
            needsDisplay = true
        }
    }
    fileprivate var hoveredActivityItem: UsageActivityTooltipItem? {
        didSet {
            needsDisplay = true
        }
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let hoveredActivityItem {
            drawActivityTooltip(hoveredActivityItem)
        } else if let hoveredHourItem {
            drawHourlyTooltip(hoveredHourItem)
        } else if let hoveredItem {
            TokenUsageHeatmapView.drawTooltip(
                for: hoveredItem,
                in: bounds,
                dateFormatter: dateFormatter)
        }
    }

    private func drawActivityTooltip(_ item: UsageActivityTooltipItem) {
        let title = String(format: "%02d:00", item.hour.hour)
        let total = "\(VibeCodingTimeChartView.formatDuration(item.hour.minutes)) active"

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.6, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.8, weight: .medium),
            .foregroundColor: AgentBarSettingsPalette.heatmapTooltipTokens,
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let totalSize = total.size(withAttributes: totalAttributes)
        let width = min(max(132, max(titleSize.width, totalSize.width) + 24), max(132, bounds.width - 12))
        let height: CGFloat = 56
        let preferredX = item.point.x - width / 2
        let x = min(max(6, preferredX), max(6, bounds.width - width - 6))
        let preferredY = item.point.y + 18
        let y = min(max(6, preferredY), max(6, bounds.maxY - height - 6))
        let rect = NSRect(x: x, y: y, width: width, height: height)

        AgentBarSettingsPalette.heatmapTooltipBackground.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()

        let pointer = NSBezierPath()
        let pointerX = min(max(item.point.x, rect.minX + 14), rect.maxX - 14)
        pointer.move(to: NSPoint(x: pointerX - 7, y: rect.minY))
        pointer.line(to: NSPoint(x: pointerX, y: rect.minY - 8))
        pointer.line(to: NSPoint(x: pointerX + 7, y: rect.minY))
        pointer.close()
        pointer.fill()

        title.draw(at: NSPoint(x: rect.minX + 12, y: rect.maxY - 22), withAttributes: titleAttributes)
        total.draw(at: NSPoint(x: rect.minX + 12, y: rect.maxY - 42), withAttributes: totalAttributes)
    }

    private func drawHourlyTooltip(_ item: UsageHourlyTooltipItem) {
        let title = String(format: "%02d:00", item.hour.hour)
        let total = "\(AgentBarDisplayFormatting.tokens(item.hour.totalTokens)) Tokens"
        let bucketSummary = item.buckets
            .filter { $0.tokens > 0 }
            .map { "\($0.title) \(AgentBarDisplayFormatting.tokens($0.tokens))" }
            .joined(separator: "  ")

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.6, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.8, weight: .medium),
            .foregroundColor: AgentBarSettingsPalette.heatmapTooltipTokens,
        ]
        let modelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.8, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1),
        ]

        let titleSize = title.size(withAttributes: titleAttributes)
        let totalSize = total.size(withAttributes: totalAttributes)
        let modelSize = bucketSummary.size(withAttributes: modelAttributes)
        let width = min(
            max(132, max(titleSize.width, totalSize.width, modelSize.width) + 24),
            max(132, bounds.width - 12))
        let height: CGFloat = bucketSummary.isEmpty ? 56 : 76
        let preferredX = item.point.x - width / 2
        let x = min(max(6, preferredX), max(6, bounds.width - width - 6))
        let preferredY = item.point.y + 18
        let y = min(max(6, preferredY), max(6, bounds.maxY - height - 6))
        let rect = NSRect(x: x, y: y, width: width, height: height)

        AgentBarSettingsPalette.heatmapTooltipBackground.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()

        let pointer = NSBezierPath()
        let pointerX = min(max(item.point.x, rect.minX + 14), rect.maxX - 14)
        pointer.move(to: NSPoint(x: pointerX - 7, y: rect.minY))
        pointer.line(to: NSPoint(x: pointerX, y: rect.minY - 8))
        pointer.line(to: NSPoint(x: pointerX + 7, y: rect.minY))
        pointer.close()
        pointer.fill()

        title.draw(at: NSPoint(x: rect.minX + 12, y: rect.maxY - 22), withAttributes: titleAttributes)
        total.draw(at: NSPoint(x: rect.minX + 12, y: rect.maxY - 42), withAttributes: totalAttributes)
        if !bucketSummary.isEmpty {
            bucketSummary.draw(
                in: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16),
                withAttributes: modelAttributes)
        }
    }
}

final class TokenUsageHourlyChartView: NSView {
    static let contentHeight: CGFloat = TokenUsageHeatmapView.contentHeight

    var snapshot = CodexHourlyTokenUsageSnapshot(day: Date(), dayKey: "", hours: []) {
        didSet {
            hoveredHour = nil
            onHoverChanged?(nil, nil, [])
            needsDisplay = true
        }
    }
    fileprivate var onHoverChanged: ((NSPoint?, CodexHourlyTokenUsage?, [UsageHourlyTooltipBucket]) -> Void)?

    private var barHitRects: [(rect: NSRect, hour: CodexHourlyTokenUsage)] = []
    private var hoveredHour: CodexHourlyTokenUsage?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.contentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawHeader()
        let plotRect = NSRect(x: 50, y: 58, width: max(120, bounds.width - 58), height: max(44, bounds.height - 92))
        drawGrid(in: plotRect)
        drawBars(in: plotRect)
        drawHourLabels(in: plotRect)
        drawLegend(in: NSRect(x: plotRect.minX, y: 0, width: plotRect.width, height: 34))
    }

    private func drawHeader() {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.6, weight: .semibold),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        "Tokens".draw(at: NSPoint(x: 0, y: bounds.maxY - 16), withAttributes: titleAttributes)

        let total = "Total \(AgentBarDisplayFormatting.tokens(snapshot.totalTokens)) Tokens"
        let totalSize = total.size(withAttributes: totalAttributes)
        let dotSize: CGFloat = 7
        let gap: CGFloat = 7
        let groupWidth = dotSize + gap + totalSize.width
        let groupX = max(0, bounds.maxX - groupWidth)
        let textY = bounds.maxY - 17
        let dotY = textY + totalSize.height / 2 - dotSize / 2
        (activeModelBuckets.first?.color ?? AgentBarSettingsPalette.chartOther).setFill()
        NSBezierPath(ovalIn: NSRect(x: groupX, y: dotY, width: dotSize, height: dotSize)).fill()
        total.draw(at: NSPoint(x: groupX + dotSize + gap, y: textY), withAttributes: totalAttributes)
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
        let point = convert(event.locationInWindow, from: nil)
        let next = barHitRects.first { $0.rect.contains(point) }?.hour
        let nextBuckets = next.map { tooltipBuckets(for: $0.models) } ?? []
        onHoverChanged?(next == nil ? nil : point, next, nextBuckets)
        guard next?.hour != hoveredHour?.hour else {
            needsDisplay = true
            return
        }
        hoveredHour = next
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredHour = nil
        onHoverChanged?(nil, nil, [])
        needsDisplay = true
    }

    private func drawGrid(in plotRect: NSRect) {
        let maxTokens = axisMaximum
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let gridColor = AgentBarSettingsPalette.chartGrid
        let ticks = [0, maxTokens / 2, maxTokens]

        for (index, value) in ticks.enumerated() {
            let y = plotRect.minY + CGFloat(index) / CGFloat(ticks.count - 1) * plotRect.height
            gridColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 0.7
            path.move(to: NSPoint(x: plotRect.minX, y: y))
            path.line(to: NSPoint(x: plotRect.maxX, y: y))
            path.stroke()

            let label = value == 0 ? "0" : AgentBarDisplayFormatting.tokens(value)
            let size = label.size(withAttributes: labelAttributes)
            label.draw(
                at: NSPoint(x: plotRect.minX - size.width - 10, y: y - size.height / 2),
                withAttributes: labelAttributes)
        }
    }

    private func drawBars(in plotRect: NSRect) {
        let hours = normalizedHours
        guard !hours.isEmpty else { return }

        barHitRects = []
        let maxTokens = max(1, axisMaximum)
        let slotWidth = plotRect.width / 24
        let barGap = slotWidth < 8 ? 0 : min(6, slotWidth * 0.18)
        let barWidth = max(1.5, min(13, slotWidth - barGap))

        for hour in hours {
            var y = plotRect.minY
            let x = plotRect.minX + CGFloat(hour.hour) * slotWidth + (slotWidth - barWidth) / 2
            let visibleBuckets = bucketedModels(hour.models).filter { $0.tokens > 0 }
            var drawnRect: NSRect?
            for (index, bucket) in visibleBuckets.enumerated() {
                let height = max(1.5, CGFloat(bucket.tokens) / CGFloat(maxTokens) * plotRect.height)
                bucket.color.setFill()
                let rect = NSRect(x: x, y: y, width: barWidth, height: min(height, plotRect.maxY - y))
                if index == visibleBuckets.count - 1 {
                    Self.topRoundedBarPath(rect: rect, radius: min(2.4, rect.width / 2, rect.height / 2)).fill()
                } else {
                    rect.fill()
                }
                drawnRect = drawnRect.map { $0.union(rect) } ?? rect
                y += height
            }
            if let drawnRect {
                let hitRect = drawnRect.insetBy(dx: min(0, -max(2, slotWidth * 0.18)), dy: -3)
                barHitRects.append((hitRect, hour))
                if hoveredHour?.hour == hour.hour {
                    AgentBarSettingsPalette.heatmapHoverStroke.setStroke()
                    let path = NSBezierPath(roundedRect: drawnRect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4)
                    path.lineWidth = 1.5
                    path.stroke()
                }
            }
        }
    }

    private func drawHourLabels(in plotRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let slotWidth = plotRect.width / 24
        for hour in stride(from: 0, through: 24, by: 4) {
            let label = hour == 24 ? "Hours" : String(format: "%02d", hour)
            let size = label.size(withAttributes: attributes)
            let x = hour == 24
                ? plotRect.maxX - size.width
                : plotRect.minX + CGFloat(hour) * slotWidth + slotWidth / 2 - size.width / 2
            label.draw(at: NSPoint(x: x, y: plotRect.minY - 22), withAttributes: attributes)
        }
    }

    private func drawLegend(in rect: NSRect) {
        let buckets = activeModelBuckets
        guard !buckets.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.6, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let items = buckets.map { bucket -> LegendItem in
            let labelSize = bucket.title.size(withAttributes: attributes)
            return LegendItem(bucket: bucket, labelSize: labelSize, width: 16 + labelSize.width)
        }
        let rowGap: CGFloat = 6
        let lineHeight: CGFloat = 14
        let rows = legendRows(items: items, maxWidth: rect.width, gap: rowGap)
        let totalHeight = CGFloat(rows.count) * lineHeight + CGFloat(max(0, rows.count - 1)) * 4
        var y = rect.minY + max(0, (rect.height - totalHeight) / 2) + totalHeight - lineHeight

        for row in rows {
            let rowWidth = row.reduce(CGFloat(0)) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * rowGap
            var x = rect.minX + max(0, (rect.width - rowWidth) / 2)
            for item in row {
                item.bucket.color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y + 2, width: 10, height: 10), xRadius: 3, yRadius: 3).fill()
                item.bucket.title.draw(at: NSPoint(x: x + 16, y: y - 1), withAttributes: attributes)
                x += item.width + rowGap
            }
            y -= lineHeight + 4
        }
    }

    private func legendRows(items: [LegendItem], maxWidth: CGFloat, gap: CGFloat) -> [[LegendItem]] {
        var rows: [[LegendItem]] = []
        var current: [LegendItem] = []
        var currentWidth: CGFloat = 0
        for item in items {
            let nextWidth = current.isEmpty ? item.width : currentWidth + gap + item.width
            if !current.isEmpty, nextWidth > maxWidth {
                rows.append(current)
                current = [item]
                currentWidth = item.width
            } else {
                current.append(item)
                currentWidth = nextWidth
            }
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private static func topRoundedBarPath(rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.curve(
            to: NSPoint(x: rect.maxX - radius, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - radius * 0.45),
            controlPoint2: NSPoint(x: rect.maxX - radius * 0.45, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
        path.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY - radius),
            controlPoint1: NSPoint(x: rect.minX + radius * 0.45, y: rect.maxY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - radius * 0.45))
        path.close()
        return path
    }

    private var normalizedHours: [CodexHourlyTokenUsage] {
        if snapshot.hours.count == 24 { return snapshot.hours }
        return (0..<24).map { hour in
            snapshot.hours.first { $0.hour == hour } ?? CodexHourlyTokenUsage(hour: hour, models: [])
        }
    }

    private var axisMaximum: Int {
        Self.niceMaximum(max(1, snapshot.maxHourlyTokens))
    }

    private func bucketedModels(_ models: [CodexHourlyModelTokenUsage]) -> [LegendBucket] {
        var buckets = activeModelBuckets
        for model in models {
            guard let index = buckets.firstIndex(where: { $0.model == model.model }) else { continue }
            buckets[index].tokens += model.tokens
        }
        return buckets
    }

    private func tooltipBuckets(for models: [CodexHourlyModelTokenUsage]) -> [UsageHourlyTooltipBucket] {
        bucketedModels(models)
            .filter { $0.tokens > 0 }
            .map { UsageHourlyTooltipBucket(title: $0.title, tokens: $0.tokens) }
    }

    private var activeModelBuckets: [LegendBucket] {
        var totals: [String: Int] = [:]
        for hour in normalizedHours {
            for model in hour.models where model.tokens > 0 {
                totals[model.model, default: 0] += model.tokens
            }
        }
        return totals
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .enumerated()
            .map { index, entry in
                LegendBucket(
                    model: entry.key,
                    title: Self.displayName(for: entry.key),
                    color: Self.modelColors[index % Self.modelColors.count])
            }
    }

    private static let modelColors: [NSColor] = [
        AgentBarSettingsPalette.chartGPT55,
        AgentBarSettingsPalette.chartGPT54,
        AgentBarSettingsPalette.chartClaude,
        AgentBarSettingsPalette.chartGemini,
        AgentBarSettingsPalette.chartOther,
    ]

    private static func niceMaximum(_ value: Int) -> Int {
        guard value > 0 else { return 1 }
        let exponent = floor(log10(Double(value)))
        let magnitude = pow(10, exponent)
        let normalized = Double(value) / magnitude
        let nice: Double
        switch normalized {
        case ...1.5:
            nice = 1.5
        case ...2:
            nice = 2
        case ...5:
            nice = 5
        default:
            nice = 10
        }
        return max(1, Int(nice * magnitude))
    }

    private struct LegendBucket {
        let model: String
        let title: String
        let color: NSColor
        var tokens: Int = 0
    }

    private struct LegendItem {
        let bucket: LegendBucket
        let labelSize: NSSize
        let width: CGFloat
    }

    private static func displayName(for model: String) -> String {
        if model.hasPrefix("gpt-") {
            return "GPT-\(model.dropFirst("gpt-".count))"
        }
        let parts = model
            .split(separator: "-")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return model }
        return parts.map { part in
            if part.lowercased() == "gpt" {
                return "GPT"
            }
            return part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }
}

final class VibeCodingTimeChartView: NSView {
    static let contentHeight: CGFloat = TokenUsageHeatmapView.contentHeight

    var snapshot = CodexActivityUsageSnapshot(day: Date(), dayKey: "", hours: []) {
        didSet {
            hoveredHour = nil
            onHoverChanged?(nil, nil)
            needsDisplay = true
        }
    }
    fileprivate var onHoverChanged: ((NSPoint?, CodexActivityHourUsage?) -> Void)?

    private var pointHitRects: [(rect: NSRect, hour: CodexActivityHourUsage, point: NSPoint)] = []
    private var hoveredHour: CodexActivityHourUsage?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.contentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawHeader()
        let plotRect = NSRect(x: 50, y: 30, width: max(120, bounds.width - 58), height: max(48, bounds.height - 64))
        drawGrid(in: plotRect)
        drawCurve(in: plotRect)
        drawHourLabels(in: plotRect)
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
        let point = convert(event.locationInWindow, from: nil)
        let next = pointHitRects.first { $0.rect.contains(point) }
        onHoverChanged?(next?.point, next?.hour)
        guard next?.hour.hour != hoveredHour?.hour else {
            needsDisplay = true
            return
        }
        hoveredHour = next?.hour
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredHour = nil
        onHoverChanged?(nil, nil)
        needsDisplay = true
    }

    private func drawHeader() {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.6, weight: .semibold),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let totalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let title = "Vibe Coding Time"
        title.draw(at: NSPoint(x: 0, y: bounds.maxY - 16), withAttributes: titleAttributes)

        let total = "\(Self.formatDuration(snapshot.totalMinutes)) Total"
        let totalSize = total.size(withAttributes: totalAttributes)
        let dotSize: CGFloat = 7
        let gap: CGFloat = 7
        let groupWidth = dotSize + gap + totalSize.width
        let groupX = max(0, bounds.maxX - groupWidth)
        let textY = bounds.maxY - 17
        let dotY = textY + totalSize.height / 2 - dotSize / 2
        let dotRect = NSRect(x: groupX, y: dotY, width: dotSize, height: dotSize)
        AgentBarSettingsPalette.chartClaude.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        total.draw(at: NSPoint(x: dotRect.maxX + gap, y: textY), withAttributes: totalAttributes)
    }

    private func drawGrid(in plotRect: NSRect) {
        let maximum = axisMaximum
        let ticks = [0, maximum / 2, maximum]
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]

        for (index, value) in ticks.enumerated() {
            let y = plotRect.minY + CGFloat(index) / CGFloat(ticks.count - 1) * plotRect.height
            AgentBarSettingsPalette.chartGrid.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 0.7
            path.move(to: NSPoint(x: plotRect.minX, y: y))
            path.line(to: NSPoint(x: plotRect.maxX, y: y))
            path.stroke()

            let label = value == 0 ? "0" : "\(value)m"
            let size = label.size(withAttributes: labelAttributes)
            label.draw(
                at: NSPoint(x: plotRect.minX - size.width - 10, y: y - size.height / 2),
                withAttributes: labelAttributes)
        }
    }

    private func drawCurve(in plotRect: NSRect) {
        let hours = normalizedHours
        pointHitRects = []
        guard hours.contains(where: { $0.minutes > 0 }) else { return }

        let maximum = Double(axisMaximum)
        let slotWidth = plotRect.width / 24
        let points = hours.map { hour -> NSPoint in
            let x = plotRect.minX + CGFloat(hour.hour) * slotWidth + slotWidth / 2
            let y = plotRect.minY + min(1, max(0, CGFloat(hour.minutes / maximum))) * plotRect.height
            return NSPoint(x: x, y: y)
        }

        let area = NSBezierPath()
        area.move(to: NSPoint(x: points[0].x, y: plotRect.minY))
        for point in points {
            area.line(to: point)
        }
        area.line(to: NSPoint(x: points[points.count - 1].x, y: plotRect.minY))
        area.close()
        NSGradient(
            starting: AgentBarSettingsPalette.chartClaude.withAlphaComponent(0.22),
            ending: AgentBarSettingsPalette.chartClaude.withAlphaComponent(0.02))?
            .draw(in: area, angle: 90)

        let line = NSBezierPath()
        line.move(to: points[0])
        for point in points.dropFirst() {
            line.line(to: point)
        }
        AgentBarSettingsPalette.chartClaude.setStroke()
        line.lineWidth = 2
        line.stroke()

        for (index, point) in points.enumerated() where point.y > plotRect.minY + 0.5 {
            let hour = hours[index]
            pointHitRects.append((
                rect: NSRect(x: point.x - max(6, slotWidth * 0.35), y: point.y - 8, width: max(12, slotWidth * 0.7), height: 16),
                hour: hour,
                point: point))
            AgentBarSettingsPalette.cardBackground.setFill()
            AgentBarSettingsPalette.chartClaude.setStroke()
            let isHovered = hoveredHour?.hour == hour.hour
            let radius: CGFloat = isHovered ? 4 : 3
            let dot = NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            dot.lineWidth = isHovered ? 2 : 1.5
            dot.fill()
            dot.stroke()
        }
    }

    private func drawHourLabels(in plotRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let slotWidth = plotRect.width / 24
        for hour in stride(from: 0, through: 24, by: 4) {
            let label = hour == 24 ? "Hours" : String(format: "%02d", hour)
            let size = label.size(withAttributes: attributes)
            let x = hour == 24
                ? plotRect.maxX - size.width
                : plotRect.minX + CGFloat(hour) * slotWidth + slotWidth / 2 - size.width / 2
            label.draw(at: NSPoint(x: x, y: plotRect.minY - 22), withAttributes: attributes)
        }
    }

    private var normalizedHours: [CodexActivityHourUsage] {
        if snapshot.hours.count == 24 { return snapshot.hours }
        return (0..<24).map { hour in
            snapshot.hours.first { $0.hour == hour } ?? CodexActivityHourUsage(hour: hour, minutes: 0)
        }
    }

    private var axisMaximum: Int {
        let value = max(60, Int(ceil(snapshot.maxHourlyMinutes)))
        return Self.niceMinuteMaximum(value)
    }

    private static func niceMinuteMaximum(_ value: Int) -> Int {
        if value <= 60 { return 60 }
        if value <= 120 { return 120 }
        if value <= 180 { return 180 }
        if value <= 240 { return 240 }
        return Int(ceil(Double(value) / 60)) * 60
    }

    fileprivate static func formatDuration(_ minutes: Double) -> String {
        let rounded = max(0, Int(minutes.rounded()))
        let hours = rounded / 60
        let mins = rounded % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

final class SettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        updateLayerColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.backgroundColor = AgentBarSettingsPalette.cardBackground.resolvedCGColor(for: effectiveAppearance)
        layer?.borderColor = AgentBarSettingsPalette.cardBorder.resolvedCGColor(for: effectiveAppearance)
    }
}

final class SettingsBackgroundView: NSView {
    private let color: NSColor

    init(frame frameRect: NSRect = .zero, color: NSColor) {
        self.color = color
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = color.resolvedCGColor(for: effectiveAppearance)
    }
}

final class SeparatorView: NSView {
    private let color: NSColor

    init(color: NSColor = AgentBarSettingsPalette.separator) {
        self.color = color
        super.init(frame: .zero)
        configure()
    }

    override init(frame frameRect: NSRect) {
        color = AgentBarSettingsPalette.separator
        super.init(frame: frameRect)
        configure()
    }

    private func configure() {
        wantsLayer = true
        updateLayerColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerColor()
    }

    private func updateLayerColor() {
        layer?.backgroundColor = color.resolvedCGColor(for: effectiveAppearance)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }
}

final class InsetSeparatorView: NSView {
    init(inset: CGFloat) {
        super.init(frame: .zero)

        let lineView = SeparatorView()
        lineView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lineView)

        NSLayoutConstraint.activate([
            lineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            lineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            lineView.centerYAnchor.constraint(equalTo: centerYAnchor),
            lineView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }
}

final class SettingsSwitch: NSSwitch {
    var isOn: Bool {
        get { state == .on }
        set { state = newValue ? .on : .off }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controlSize = .regular
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 22)
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

final class SettingsIconButton: NSButton {
    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.32
        }
    }

    init(symbolName: String, accessibilityDescription: String) {
        super.init(frame: .zero)
        title = ""
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = AgentBarSettingsPalette.heatmapLabel
        toolTip = accessibilityDescription
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription) {
            image.isTemplate = true
            self.image = image.withSymbolConfiguration(.init(pointSize: 10.8, weight: .semibold))
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

}

enum AgentBarSettingsPalette {
    static let sidebarBackground = dynamic(light: 0xE6E5E3, dark: 0x252629)
    static let contentBackground = dynamic(light: 0xF3F1EF, dark: 0x1F2023)
    static let cardBackground = dynamic(light: 0xEFEDEB, dark: 0x2A2B2E)
    static let selection = NSColor(hex: 0x226CFF)
    static let cardBorder = dynamic(light: 0xE2E0DF, dark: 0x3A3B3F)
    static let separator = dynamic(light: 0xE4E2E1, dark: 0x383A3D)
    static let sidebarDivider = dynamic(light: 0xD6D5D3, dark: 0x343539)
    static let controlBackground = dynamic(light: 0xFFFFFF, dark: 0x34363A, lightAlpha: 0.70, darkAlpha: 0.92)
    static let controlHoverBackground = dynamic(light: 0xFFFFFF, dark: 0x3D4046, lightAlpha: 0.88, darkAlpha: 1)
    static let heatmapLabel = dynamic(light: 0x5D6268, dark: 0xA7ADB4)
    static let heatmapEmpty = dynamic(light: 0xE7E7E7, dark: 0x303236)
    static let heatmapLevel1 = dynamic(light: 0xA9D6C9, dark: 0x285246)
    static let heatmapLevel2 = dynamic(light: 0x78BDA9, dark: 0x34705F)
    static let heatmapLevel3 = dynamic(light: 0x4B9C82, dark: 0x409178)
    static let heatmapLevel4 = dynamic(light: 0x177953, dark: 0x59C79F)
    static let heatmapHoverStroke = dynamic(light: 0x7D858D, dark: 0xC2CBD4)
    static let heatmapTooltipBackground = NSColor(hex: 0x2F2F30)
    static let heatmapTooltipCost = NSColor(hex: 0x5FE58A)
    static let heatmapTooltipTokens = NSColor(hex: 0x72A9FF)
    static let chartGrid = dynamic(light: 0xD8DADD, dark: 0x3A3D42, lightAlpha: 0.78, darkAlpha: 0.78)
    static let chartGPT55 = dynamic(light: 0x4BD181, dark: 0x57D98B)
    static let chartGPT54 = dynamic(light: 0x2F76F6, dark: 0x5B91FF)
    static let chartClaude = dynamic(light: 0x8F45E8, dark: 0xA66BFF)
    static let chartGemini = dynamic(light: 0xFF8A4F, dark: 0xFF9A66)
    static let chartOther = dynamic(light: 0xB6BBC3, dark: 0x737984)

    private static func dynamic(
        light: Int,
        dark: Int,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1)
        -> NSColor
    {
        NSColor(name: nil) { appearance in
            NSColor(
                hex: appearance.isDarkMode ? dark : light,
                alpha: appearance.isDarkMode ? darkAlpha : lightAlpha)
        }
    }
}

private extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    func resolvedCGColor(for appearance: NSAppearance) -> CGColor {
        var resolvedColor = cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = self.cgColor
        }
        return resolvedColor
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@MainActor
final class AgentBarLaunchAtLoginController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
            return
        }

        guard SMAppService.mainApp.status == .enabled ||
            SMAppService.mainApp.status == .requiresApproval
        else {
            return
        }
        try SMAppService.mainApp.unregister()
    }
}
