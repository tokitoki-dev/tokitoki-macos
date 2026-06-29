import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let apiKeyField = NSTextField(frame: .zero)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let versionLabel = NSTextField(labelWithString: "")
    private var saveAPIKey: ((String?) -> Void)?

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
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
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(apiKey: String?, saveAPIKey: @escaping (String?) -> Void) {
        self.saveAPIKey = saveAPIKey
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
        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas
        buttonRow.spacing = 8

        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [apiKeyLabel, apiKeyField, launchAtLoginCheckbox, versionLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 56),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 60),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -60),
            apiKeyField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
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
