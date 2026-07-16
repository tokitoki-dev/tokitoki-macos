import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let apiKeyField = NSTextField(frame: .zero)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let versionLabel = NSTextField(labelWithString: "")
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "Automatically check for updates", target: nil, action: nil)
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)
    private let lastCheckLabel = NSTextField(labelWithString: "")
    private var saveAPIKey: ((String?) -> Void)?
    private var updater: Updater?
    private var shownAPIKey = ""

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 0))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = contentView
        window.isReleasedWhenClosed = false

        super.init(window: window)
        configureContent(in: contentView)
        window.setContentSize(NSSize(width: 420, height: contentView.fittingSize.height))
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(
        apiKey: String?,
        updater: Updater,
        saveAPIKey: @escaping (String?) -> Void
    ) {
        self.saveAPIKey = saveAPIKey
        self.updater = updater
        autoUpdateCheckbox.state = updater.automaticallyChecksForUpdates ? .on : .off
        checkNowButton.isEnabled = updater.canCheckForUpdates
        refreshLastCheck()
        apiKeyField.stringValue = apiKey ?? ""
        apiKeyField.placeholderString = "Paste your API key"
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

        let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        versionLabel.stringValue = "Version \(marketingVersion) (\(buildVersion))"

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        apiKeyField.selectText(nil)
    }

    private func configureContent(in contentView: NSView) {
        let apiKeyLabel = NSTextField(labelWithString: "API Key")
        apiKeyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.usesSingleLineMode = true
        apiKeyField.lineBreakMode = .byClipping
        apiKeyField.cell?.isScrollable = true
        apiKeyField.cell?.wraps = false

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))

        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 11)

        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)
        checkNowButton.target = self
        checkNowButton.action = #selector(runUpdateCheck)
        lastCheckLabel.textColor = .secondaryLabelColor
        lastCheckLabel.font = .systemFont(ofSize: 11)

        let separator = NSBox()
        separator.boxType = .separator

        let checkNowColumn = NSStackView(views: [checkNowButton, lastCheckLabel])
        checkNowColumn.orientation = .vertical
        checkNowColumn.alignment = .trailing
        checkNowColumn.spacing = 4

        let updatesRow = NSStackView()
        updatesRow.orientation = .horizontal
        updatesRow.alignment = .top
        updatesRow.addView(autoUpdateCheckbox, in: .leading)
        updatesRow.addView(checkNowColumn, in: .trailing)

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 8
        bottomRow.addView(versionLabel, in: .leading)
        bottomRow.addView(cancelButton, in: .trailing)
        bottomRow.addView(saveButton, in: .trailing)

        let stack = NSStackView(views: [apiKeyLabel, apiKeyField, launchAtLoginCheckbox, separator, updatesRow, bottomRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(6, after: apiKeyLabel)
        stack.setCustomSpacing(16, after: launchAtLoginCheckbox)
        stack.setCustomSpacing(16, after: separator)
        stack.setCustomSpacing(20, after: updatesRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            apiKeyField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            updatesRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func refreshLastCheck() {
        guard let date = updater?.lastUpdateCheckDate else {
            lastCheckLabel.stringValue = "Last check: Never"
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        lastCheckLabel.stringValue = "Last check: \(formatter.string(from: date))"
    }

    @objc private func autoUpdateChanged() {
        updater?.automaticallyChecksForUpdates = autoUpdateCheckbox.state == .on
    }

    @objc private func runUpdateCheck() {
        updater?.checkForUpdates()
        refreshLastCheck()
    }

    @objc private func launchAtLoginChanged() {
        do {
            try LaunchAtLogin.setEnabled(launchAtLoginCheckbox.state == .on)
        } catch {
            launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
            presentError(error)
        }
    }

    @objc private func save() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAPIKey?(apiKey.isEmpty ? nil : apiKey)
        close()
    }

    @objc private func cancel() {
        close()
    }
}
