import AppKit

@MainActor
private final class CheckboxWithDetailView: NSView {
    private let checkbox: NSButton

    init(checkbox: NSButton, titleLabel: NSTextField, detailLabel: NSTextField) {
        self.checkbox = checkbox
        super.init(frame: .zero)

        checkbox.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)
        addSubview(titleLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        titleLabel.addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(toggleCheckbox))
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func toggleCheckbox() {
        checkbox.performClick(nil)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let apiKeyField = NSTextField(frame: .zero)
    private let verifyAPIKeyButton = NSButton(title: "Verify Key", target: nil, action: nil)
    private let verificationProgress = NSProgressIndicator()
    private let verificationStatusImage = NSImageView()
    private let verificationStatusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let versionLabel = NSTextField(labelWithString: "")
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoUpdateTitleLabel = NSTextField(labelWithString: "Automatically check for updates")
    private lazy var autoUpdateDetails = CheckboxWithDetailView(
        checkbox: autoUpdateCheckbox,
        titleLabel: autoUpdateTitleLabel,
        detailLabel: versionLabel
    )
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)
    private let lastCheckLabel = NSTextField(labelWithString: "")
    private var saveAPIKey: ((String?) -> Void)?
    private var updater: Updater?
    private var shownAPIKey = ""
    private var verificationTask: Task<Void, Never>?
    private let apiKeyVerifier: APIKeyVerifier

    init(apiKeyVerifier: APIKeyVerifier = APIKeyVerifier(serverURL: AppConfig.serverURL)) {
        self.apiKeyVerifier = apiKeyVerifier
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
        window.delegate = self
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
        shownAPIKey = apiKey ?? ""
        apiKeyField.stringValue = shownAPIKey
        apiKeyField.placeholderString = "Paste your API key"
        verificationTask?.cancel()
        verificationTask = nil
        renderVerificationState(.idle)
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off

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
        apiKeyField.delegate = self

        verifyAPIKeyButton.target = self
        verifyAPIKeyButton.action = #selector(verifyAPIKey)
        verifyAPIKeyButton.bezelStyle = .rounded
        verifyAPIKeyButton.toolTip = "Check this key with the TokiToki server"

        verificationProgress.style = .spinning
        verificationProgress.controlSize = .small
        verificationProgress.isDisplayedWhenStopped = false

        verificationStatusImage.imageScaling = .scaleProportionallyDown
        verificationStatusImage.setContentHuggingPriority(.required, for: .horizontal)
        verificationStatusLabel.font = .systemFont(ofSize: 11)
        verificationStatusLabel.lineBreakMode = .byTruncatingTail
        verificationStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let apiKeyVerificationRow = NSStackView(
            views: [
                verifyAPIKeyButton,
                verificationProgress,
                verificationStatusImage,
                verificationStatusLabel,
            ]
        )
        apiKeyVerificationRow.orientation = .horizontal
        apiKeyVerificationRow.alignment = .centerY
        apiKeyVerificationRow.spacing = 7

        apiKeyField.nextKeyView = verifyAPIKeyButton
        verifyAPIKeyButton.nextKeyView = launchAtLoginCheckbox

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.stringValue = "Version \(AppConfig.version)"
        versionLabel.identifier = NSUserInterfaceItemIdentifier("versionLabel")

        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(autoUpdateChanged)
        autoUpdateCheckbox.identifier = NSUserInterfaceItemIdentifier("autoUpdateCheckbox")
        autoUpdateCheckbox.setAccessibilityLabel("Automatically check for updates")
        autoUpdateTitleLabel.identifier = NSUserInterfaceItemIdentifier("autoUpdateTitleLabel")
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
        updatesRow.addView(autoUpdateDetails, in: .leading)
        updatesRow.addView(checkNowColumn, in: .trailing)

        let stack = NSStackView(
            views: [
                apiKeyLabel,
                apiKeyField,
                apiKeyVerificationRow,
                launchAtLoginCheckbox,
                separator,
                updatesRow,
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(6, after: apiKeyLabel)
        stack.setCustomSpacing(8, after: apiKeyField)
        stack.setCustomSpacing(16, after: launchAtLoginCheckbox)
        stack.setCustomSpacing(16, after: separator)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            apiKeyField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            apiKeyVerificationRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            updatesRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        renderVerificationState(.idle)
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
    }

    @objc private func launchAtLoginChanged() {
        do {
            try LaunchAtLogin.setEnabled(launchAtLoginCheckbox.state == .on)
        } catch {
            launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
            presentError(error)
        }
    }

    @objc private func verifyAPIKey() {
        let apiKey = currentAPIKey
        guard !apiKey.isEmpty else { return }

        verificationTask?.cancel()
        renderVerificationState(.verifying)
        verificationTask = Task { [weak self, apiKeyVerifier] in
            do {
                let isValid = try await apiKeyVerifier.verify(apiKey)
                guard !Task.isCancelled else { return }
                self?.renderVerificationState(isValid ? .valid : .invalid)
            } catch {
                guard !Task.isCancelled else { return }
                self?.renderVerificationState(.unavailable)
            }
            self?.verificationTask = nil
        }
    }

    private var currentAPIKey: String {
        apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum VerificationState {
        case idle
        case verifying
        case valid
        case invalid
        case unavailable
    }

    private func renderVerificationState(_ state: VerificationState) {
        verificationProgress.stopAnimation(nil)
        verificationProgress.isHidden = true
        verificationStatusImage.isHidden = true
        verificationStatusLabel.stringValue = ""
        verificationStatusLabel.textColor = .secondaryLabelColor
        verifyAPIKeyButton.isEnabled = !currentAPIKey.isEmpty

        switch state {
        case .idle:
            break
        case .verifying:
            verifyAPIKeyButton.isEnabled = false
            verificationProgress.isHidden = false
            verificationProgress.startAnimation(nil)
            verificationStatusLabel.stringValue = "Verifying…"
        case .valid:
            showVerificationResult(
                symbol: "checkmark.circle.fill",
                color: .systemGreen,
                message: "Key is valid."
            )
        case .invalid:
            showVerificationResult(
                symbol: "xmark.circle.fill",
                color: .systemRed,
                message: "Key is invalid or has been revoked."
            )
        case .unavailable:
            showVerificationResult(
                symbol: "exclamationmark.triangle.fill",
                color: .systemOrange,
                message: "Couldn’t verify the key. Try again."
            )
        }
    }

    private func showVerificationResult(symbol: String, color: NSColor, message: String) {
        verificationStatusImage.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )
        verificationStatusImage.contentTintColor = color
        verificationStatusImage.isHidden = false
        verificationStatusLabel.stringValue = message
    }

}

extension SettingsWindowController: NSWindowDelegate {
    // Settings apply immediately; the API key is the one field with a commit
    // point, and that point is closing the window.
    func windowWillClose(_ notification: Notification) {
        verificationTask?.cancel()
        verificationTask = nil
        let apiKey = currentAPIKey
        guard apiKey != shownAPIKey else { return }
        saveAPIKey?(apiKey.isEmpty ? nil : apiKey)
    }

    // Sparkle's check runs in its own windows; when focus returns here the
    // "Last check" date and the button's availability may both have moved.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let updater else { return }
        checkNowButton.isEnabled = updater.canCheckForUpdates
        refreshLastCheck()
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        verificationTask?.cancel()
        verificationTask = nil
        renderVerificationState(.idle)
    }
}
