import AppKit
import ServiceManagement

fileprivate enum SettingsPage {
    case general
    case about
}

@MainActor
final class AgentBarSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(updater: AgentBarUpdater) {
        let contentViewController = AgentBarSettingsViewController(updater: updater)
        let window = AgentBarSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "AgentBar Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = contentViewController
        window.minSize = NSSize(width: 620, height: 300)

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
    private let launchAtLogin = AgentBarLaunchAtLoginController()
    private let launchAtLoginSwitch = SettingsSwitch()
    private let automaticUpdatesSwitch = SettingsSwitch()
    private let sidebar = SettingsSidebarView()
    private let titleLabel = NSTextField(labelWithString: "General")
    private let generalCard = SettingsCardView()
    private let aboutCard = SettingsCardView()

    init(updater: AgentBarUpdater) {
        self.updater = updater
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 320))
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
        let githubRow = SettingsLinkRowView(
            title: "GitHub Repository",
            detail: "github.com/iFurySt/agent-bar")
        githubRow.target = self
        githubRow.action = #selector(openGitHub)

        configureSwitch(launchAtLoginSwitch, action: #selector(launchAtLoginChanged(_:)))
        configureSwitch(automaticUpdatesSwitch, action: #selector(automaticUpdatesChanged(_:)))

        let cardStack = NSStackView(views: [launchRow, separator, updatesRow])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        generalCard.addSubview(cardStack)

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
        contentView.addSubview(aboutCard)

        for view in [sidebar, sidebarDivider, contentView, titleLabel, generalCard, aboutCard] {
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
            launchRow.heightAnchor.constraint(equalToConstant: 40),
            updatesRow.heightAnchor.constraint(equalToConstant: 40),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            githubRow.widthAnchor.constraint(equalTo: aboutStack.widthAnchor),
            githubRow.heightAnchor.constraint(equalToConstant: 48),
        ])

        sidebar.onGeneral = { [weak self] in
            self?.showPage(.general)
        }
        sidebar.onAbout = { [weak self] in
            self?.showPage(.about)
        }

        view = rootView
        showPage(.general)
        refreshControls()
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

    private func configureSwitch(_ control: SettingsSwitch, action: Selector) {
        control.target = self
        control.action = action
    }

    private func refreshControls() {
        launchAtLoginSwitch.isOn = launchAtLogin.isEnabled
        automaticUpdatesSwitch.isOn = updater.automaticallyChecksForUpdates
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

    private func showPage(_ page: SettingsPage) {
        titleLabel.stringValue = page == .general ? "General" : "About"
        generalCard.isHidden = page != .general
        aboutCard.isHidden = page != .about
        sidebar.select(page)
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
    var onAbout: (() -> Void)?

    private let selectedButton = SidebarItemView(title: "General", symbolName: "gearshape", selected: true)
    private let aboutButton = SidebarItemView(title: "About", symbolName: "info.circle", selected: false)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = AgentBarSettingsPalette.sidebarBackground.cgColor

        selectedButton.target = self
        selectedButton.action = #selector(generalPressed)
        aboutButton.target = self
        aboutButton.action = #selector(aboutPressed)

        let stackView = NSStackView(views: [selectedButton, aboutButton])
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
            aboutButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            selectedButton.heightAnchor.constraint(equalToConstant: 28),
            aboutButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    fileprivate func select(_ page: SettingsPage) {
        selectedButton.isSelected = page == .general
        aboutButton.isSelected = page == .about
    }

    @objc private func generalPressed() {
        onGeneral?()
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

enum AgentBarSettingsPalette {
    static let sidebarBackground = NSColor(hex: 0xE6E5E3)
    static let contentBackground = NSColor(hex: 0xF3F1EF)
    static let cardBackground = NSColor(hex: 0xEFEDEB)
    static let selection = NSColor(hex: 0x226CFF)
    static let cardBorder = NSColor(hex: 0xE2E0DF)
    static let separator = NSColor(hex: 0xE4E2E1)
    static let sidebarDivider = NSColor(hex: 0xD6D5D3)
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
