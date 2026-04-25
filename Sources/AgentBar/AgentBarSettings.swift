import AppKit
import AgentBarCore
import ServiceManagement

fileprivate enum SettingsPage {
    case general
    case usage
    case about
}

@MainActor
final class AgentBarSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(updater: AgentBarUpdater, preferences: AgentBarPreferences) {
        let contentViewController = AgentBarSettingsViewController(updater: updater, preferences: preferences)
        let window = AgentBarSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "AgentBar Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = contentViewController
        window.minSize = NSSize(width: 720, height: 380)

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

    func showSettings() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
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
    private let updater: AgentBarUpdater
    private let preferences: AgentBarPreferences
    private let launchAtLogin = AgentBarLaunchAtLoginController()
    private let launchAtLoginSwitch = SettingsSwitch()
    private let automaticUpdatesSwitch = SettingsSwitch()
    private let autoCollapseStepper = NSStepper()
    private let autoCollapseValueLabel = NSTextField(labelWithString: "")
    private let sidebar = SettingsSidebarView()
    private let titleLabel = NSTextField(labelWithString: "General")
    private let generalCard = SettingsCardView()
    private let usageCard = SettingsCardView()
    private let usageHeatmapView = TokenUsageHeatmapView()
    private let usageSummaryLabel = NSTextField(labelWithString: "Scanning local Codex sessions...")
    private let usagePreviousYearButton = SettingsIconButton(symbolName: "chevron.left", accessibilityDescription: "Previous year")
    private let usageNextYearButton = SettingsIconButton(symbolName: "chevron.right", accessibilityDescription: "Next year")
    private let usageYearLabel = NSTextField(labelWithString: "")
    private var selectedUsageYear = Calendar.current.component(.year, from: Date())
    private var usageYearRange = Calendar.current.component(.year, from: Date())...Calendar.current.component(.year, from: Date())
    private let aboutCard = SettingsCardView()

    init(updater: AgentBarUpdater, preferences: AgentBarPreferences) {
        self.updater = updater
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 420))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = AgentBarSettingsPalette.contentBackground.cgColor

        let sidebarDivider = SeparatorView(color: AgentBarSettingsPalette.sidebarDivider)
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AgentBarSettingsPalette.contentBackground.cgColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor

        let launchRow = settingsRow(title: "Launch at Login", control: launchAtLoginSwitch)
        let separator = InsetSeparatorView(inset: 14)
        let updatesRow = settingsRow(title: "Automatic Updates", control: automaticUpdatesSwitch)
        let separator2 = InsetSeparatorView(inset: 14)
        let autoCollapseRow = autoCollapseDelayRow()
        let usageHeader = usageHeaderView()
        let githubRow = SettingsLinkRowView(
            title: "GitHub Repository",
            detail: "github.com/iFurySt/agent-bar")
        githubRow.target = self
        githubRow.action = #selector(openGitHub)

        configureSwitch(launchAtLoginSwitch, action: #selector(launchAtLoginChanged(_:)))
        configureSwitch(automaticUpdatesSwitch, action: #selector(automaticUpdatesChanged(_:)))
        configureAutoCollapseStepper()

        let cardStack = NSStackView(views: [launchRow, separator, updatesRow, separator2, autoCollapseRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        generalCard.addSubview(cardStack)

        let usageStack = NSStackView(views: [usageHeader, usageHeatmapView])
        usageStack.orientation = .vertical
        usageStack.alignment = .leading
        usageStack.spacing = 14
        usageStack.translatesAutoresizingMaskIntoConstraints = false
        usageCard.addSubview(usageStack)

        let aboutStack = NSStackView(views: [githubRow])
        aboutStack.orientation = .vertical
        aboutStack.alignment = .leading
        aboutStack.spacing = 0
        aboutStack.translatesAutoresizingMaskIntoConstraints = false
        aboutCard.addSubview(aboutStack)

        rootView.addSubview(sidebar)
        rootView.addSubview(sidebarDivider)
        rootView.addSubview(contentView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(generalCard)
        contentView.addSubview(usageCard)
        contentView.addSubview(aboutCard)

        for view in [sidebar, sidebarDivider, contentView, titleLabel, generalCard, usageCard, aboutCard] {
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

            contentView.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),

            generalCard.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: 10),
            generalCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            generalCard.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),

            usageCard.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            usageCard.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            usageCard.topAnchor.constraint(equalTo: generalCard.topAnchor),

            aboutCard.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            aboutCard.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            aboutCard.topAnchor.constraint(equalTo: generalCard.topAnchor),

            cardStack.leadingAnchor.constraint(equalTo: generalCard.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: generalCard.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: generalCard.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: generalCard.bottomAnchor),

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

            usageStack.leadingAnchor.constraint(equalTo: usageCard.leadingAnchor, constant: 16),
            usageStack.trailingAnchor.constraint(equalTo: usageCard.trailingAnchor, constant: -16),
            usageStack.topAnchor.constraint(equalTo: usageCard.topAnchor, constant: 16),
            usageStack.bottomAnchor.constraint(equalTo: usageCard.bottomAnchor, constant: -16),
            usageHeader.widthAnchor.constraint(equalTo: usageStack.widthAnchor),
            usageHeatmapView.widthAnchor.constraint(lessThanOrEqualTo: usageStack.widthAnchor),
            usageHeatmapView.heightAnchor.constraint(equalToConstant: 190),

            githubRow.widthAnchor.constraint(equalTo: aboutStack.widthAnchor),
            githubRow.heightAnchor.constraint(equalToConstant: 48),
        ])

        sidebar.onGeneral = { [weak self] in
            self?.showPage(.general)
        }
        sidebar.onUsage = { [weak self] in
            self?.showPage(.usage)
        }
        sidebar.onAbout = { [weak self] in
            self?.showPage(.about)
        }

        view = rootView
        showPage(.general)
        refreshControls()
        refreshUsage()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshControls()
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

        usageSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 11.4, weight: .regular)
        usageSummaryLabel.textColor = .secondaryLabelColor
        usageSummaryLabel.alignment = .right
        usageSummaryLabel.lineBreakMode = .byTruncatingMiddle
        usageSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
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

        container.addSubview(titleLabel)
        container.addSubview(yearControl)
        container.addSubview(usageSummaryLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: yearControl.leadingAnchor, constant: -18),

            yearControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            yearControl.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            usagePreviousYearButton.widthAnchor.constraint(equalToConstant: 22),
            usagePreviousYearButton.heightAnchor.constraint(equalToConstant: 22),
            usageNextYearButton.widthAnchor.constraint(equalToConstant: 22),
            usageNextYearButton.heightAnchor.constraint(equalToConstant: 22),
            usageYearLabel.widthAnchor.constraint(equalToConstant: 48),

            usageSummaryLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            usageSummaryLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            usageSummaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: yearControl.trailingAnchor, constant: 18),
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
        let year = selectedUsageYear
        let task = Task.detached(priority: .utility) {
            (scanner.yearlyTokenUsage(year: year), scanner.usageYearRange())
        }
        Task { [weak self] in
            let (snapshot, yearRange) = await task.value
            self?.applyUsage(snapshot, yearRange: yearRange, year: year)
        }
    }

    private func applyUsage(_ snapshot: CodexDailyTokenUsageSnapshot, yearRange: ClosedRange<Int>, year: Int) {
        usageYearRange = yearRange
        selectedUsageYear = min(max(year, yearRange.lowerBound), yearRange.upperBound)
        usageHeatmapView.snapshot = snapshot
        usageSummaryLabel.stringValue = "\(Self.formatTokens(snapshot.totalTokens)) tokens in \(selectedUsageYear)"
        usageYearLabel.stringValue = "\(selectedUsageYear)"
        usagePreviousYearButton.isEnabled = selectedUsageYear > usageYearRange.lowerBound
        usageNextYearButton.isEnabled = selectedUsageYear < usageYearRange.upperBound
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

    private func showPage(_ page: SettingsPage) {
        switch page {
        case .general:
            titleLabel.stringValue = "General"
        case .usage:
            titleLabel.stringValue = "Usage"
        case .about:
            titleLabel.stringValue = "About"
        }
        generalCard.isHidden = page != .general
        usageCard.isHidden = page != .usage
        aboutCard.isHidden = page != .about
        sidebar.select(page)
    }

    private static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/iFurySt/agent-bar") else { return }
        NSWorkspace.shared.open(url)
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
    var onUsage: (() -> Void)?
    var onAbout: (() -> Void)?

    private let selectedButton = SidebarItemView(title: "General", symbolName: "gearshape", selected: true)
    private let usageButton = SidebarItemView(title: "Usage", symbolName: "chart.bar.xaxis", selected: false)
    private let aboutButton = SidebarItemView(title: "About", symbolName: "info.circle", selected: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = AgentBarSettingsPalette.sidebarBackground.cgColor

        selectedButton.target = self
        selectedButton.action = #selector(generalPressed)
        usageButton.target = self
        usageButton.action = #selector(usagePressed)
        aboutButton.target = self
        aboutButton.action = #selector(aboutPressed)

        let stackView = NSStackView(views: [selectedButton, usageButton, aboutButton])
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
            usageButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            aboutButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            selectedButton.heightAnchor.constraint(equalToConstant: 28),
            usageButton.heightAnchor.constraint(equalToConstant: 28),
            aboutButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    fileprivate func select(_ page: SettingsPage) {
        selectedButton.isSelected = page == .general
        usageButton.isSelected = page == .usage
        aboutButton.isSelected = page == .about
    }

    @objc private func generalPressed() {
        onGeneral?()
    }

    @objc private func usagePressed() {
        onUsage?()
    }

    @objc private func aboutPressed() {
        onAbout?()
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
    var snapshot = CodexDailyTokenUsageSnapshot(days: []) {
        didSet {
            hoveredItem = nil
            needsDisplay = true
        }
    }

    private let cellSize: CGFloat = 11
    private let cellGap: CGFloat = 4
    private let leftLabelWidth: CGFloat = 36
    private let monthLabelHeight: CGFloat = 24
    private let tooltipVerticalPadding: CGFloat = 14
    private let tooltipHorizontalPadding: CGFloat = 14
    private var cellRects: [(rect: NSRect, entry: CodexDailyTokenUsage)] = []
    private var hoveredItem: (rect: NSRect, entry: CodexDailyTokenUsage)?
    private var trackingArea: NSTrackingArea?
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
        NSSize(width: leftLabelWidth + 54 * (cellSize + cellGap), height: 190)
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
            drawTooltip(for: hoveredItem)
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
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredItem = nil
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
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: first.day) - 1
        let pitch = cellSize + cellGap
        let totalWidth = CGFloat(54) * pitch - cellGap
        let originX = leftLabelWidth + max(0, (bounds.width - leftLabelWidth - totalWidth) / 2)
        let originY = max(0, bounds.height - monthLabelHeight - CGFloat(7) * pitch - 4)

        return entries.enumerated().map { offset, entry in
            let absoluteDay = weekday + offset
            let week = absoluteDay / 7
            let day = absoluteDay % 7
            let rect = NSRect(
                x: originX + CGFloat(week) * pitch,
                y: originY + CGFloat(6 - day) * pitch,
                width: cellSize,
                height: cellSize)
            return (rect, entry)
        }
    }

    private func drawMonthLabels(entries: [CodexDailyTokenUsage]) {
        guard !cellRects.isEmpty else { return }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
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
        let pitch = cellSize + cellGap
        let labels: [(String, Int)] = [("Mon", 1), ("Wed", 3), ("Fri", 5)]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.8, weight: .regular),
            .foregroundColor: AgentBarSettingsPalette.heatmapLabel,
        ]
        let labelHeight = "Mon".size(withAttributes: attributes).height
        let topCellMaxY = cellRects.map { $0.rect.maxY }.max() ?? 0

        for (label, weekdayIndex) in labels {
            let rowCenterY = topCellMaxY - CGFloat(weekdayIndex) * pitch - cellSize / 2
            let y = rowCenterY - labelHeight / 2
            label.draw(at: NSPoint(x: 0, y: y), withAttributes: attributes)
        }
    }

    private func drawTooltip(for item: (rect: NSRect, entry: CodexDailyTokenUsage)) {
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
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
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

final class SettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = AgentBarSettingsPalette.cardBackground.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = AgentBarSettingsPalette.cardBorder.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
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
        layer?.backgroundColor = color.cgColor
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
    static let sidebarBackground = NSColor(hex: 0xE6E5E3)
    static let contentBackground = NSColor(hex: 0xF3F1EF)
    static let cardBackground = NSColor(hex: 0xEFEDEB)
    static let selection = NSColor(hex: 0x226CFF)
    static let cardBorder = NSColor(hex: 0xE2E0DF)
    static let separator = NSColor(hex: 0xE4E2E1)
    static let sidebarDivider = NSColor(hex: 0xD6D5D3)
    static let heatmapLabel = NSColor(hex: 0x5D6268)
    static let heatmapEmpty = NSColor(hex: 0xE7E7E7)
    static let heatmapLevel1 = NSColor(hex: 0xA9D6C9)
    static let heatmapLevel2 = NSColor(hex: 0x78BDA9)
    static let heatmapLevel3 = NSColor(hex: 0x4B9C82)
    static let heatmapLevel4 = NSColor(hex: 0x177953)
    static let heatmapHoverStroke = NSColor(hex: 0x7D858D)
    static let heatmapTooltipBackground = NSColor(hex: 0x2F2F30)
    static let heatmapTooltipCost = NSColor(hex: 0x5FE58A)
    static let heatmapTooltipTokens = NSColor(hex: 0x72A9FF)
}

private extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
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
