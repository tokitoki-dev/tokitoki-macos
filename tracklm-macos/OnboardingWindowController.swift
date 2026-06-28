import AppKit

@MainActor
final class OnboardingWindowController: NSWindowController {
    private let apiKeyStatus = NSTextField(labelWithString: "")
    private let agentsStatus = NSTextField(labelWithString: "")
    private let launchStatus = NSTextField(labelWithString: "")
    private var onSetKey: (() -> Void)?
    private var onChooseAgents: (() -> Void)?
    private var onDone: (() -> Void)?

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup"
        window.contentView = contentView
        window.isReleasedWhenClosed = false

        super.init(window: window)
        configureContent(in: contentView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(
        hasAPIKey: Bool,
        enabledProviders: [String],
        onSetKey: @escaping () -> Void,
        onChooseAgents: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.onSetKey = onSetKey
        self.onChooseAgents = onChooseAgents
        self.onDone = onDone
        apiKeyStatus.stringValue = hasAPIKey ? "Configured" : "Required"
        agentsStatus.stringValue = enabledProviders.map(Self.providerTitle).joined(separator: ", ")
        launchStatus.stringValue = LaunchAtLogin.isEnabled ? "On" : "Optional"

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent(in contentView: NSView) {
        let title = NSTextField(labelWithString: "Finish TrackLM setup")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Set the key, choose local agents, then TrackLM can sync.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 0

        let keyButton = NSButton(title: "Set Key", target: self, action: #selector(setKey))
        let agentsButton = NSButton(title: "Agents", target: self, action: #selector(chooseAgents))
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r"

        let rows = NSStackView(views: [
            OnboardingRow(title: "API Key", detail: "Required for upload.", statusLabel: apiKeyStatus, actionButton: keyButton),
            OnboardingRow(title: "Local Agents", detail: "Claude Code and Codex folders.", statusLabel: agentsStatus, actionButton: agentsButton),
            OnboardingRow(title: "Launch at Login", detail: "Optional.", statusLabel: launchStatus, actionButton: nil),
        ])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 8

        let footer = NSStackView(views: [NSView(), doneButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill

        let stack = NSStackView(views: [title, subtitle, rows, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func setKey() {
        onSetKey?()
    }

    @objc private func chooseAgents() {
        onChooseAgents?()
    }

    @objc private func done() {
        onDone?()
        close()
    }

    private static func providerTitle(_ provider: String) -> String {
        switch provider {
        case "claude":
            return "Claude Code"
        case "codex":
            return "Codex"
        default:
            return provider
        }
    }
}

@MainActor
private final class OnboardingRow: NSView {
    init(title: String, detail: String, statusLabel: NSTextField, actionButton: NSButton?) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(statusLabel)
        if let actionButton {
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(actionButton)
            NSLayoutConstraint.activate([
                actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                statusLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -12),
            ])
        } else {
            NSLayoutConstraint.activate([
                statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
