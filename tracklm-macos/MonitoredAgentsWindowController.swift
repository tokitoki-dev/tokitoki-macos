import AppKit

@MainActor
final class MonitoredAgentsWindowController: NSWindowController {
    private let claudeRow = MonitoredAgentRow(title: "Claude Code")
    private let codexRow = MonitoredAgentRow(title: "Codex")
    private var onChange: (([String]) -> Void)?

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 116))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agents"
        window.contentView = contentView
        window.isReleasedWhenClosed = false

        super.init(window: window)
        configureContent(in: contentView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(enabledProviders: [String], onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        claudeRow.toggle.state = enabledProviders.contains("claude") ? .on : .off
        codexRow.toggle.state = enabledProviders.contains("codex") ? .on : .off

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent(in contentView: NSView) {
        claudeRow.toggle.target = self
        claudeRow.toggle.action = #selector(agentToggled)
        codexRow.toggle.target = self
        codexRow.toggle.action = #selector(agentToggled)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let rows = NSStackView(views: [claudeRow, divider, codexRow])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 0

        let stack = NSStackView(views: [rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func agentToggled() {
        let providers = selectedProviders
        guard !providers.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Select an agent"
            alert.informativeText = "At least one agent must remain monitored."
            alert.runModal()
            claudeRow.toggle.state = .on
            return
        }
        onChange?(providers)
    }

    private var selectedProviders: [String] {
        [
            claudeRow.toggle.state == .on ? "claude" : nil,
            codexRow.toggle.state == .on ? "codex" : nil,
        ].compactMap { $0 }
    }
}

@MainActor
private final class MonitoredAgentRow: NSView {
    let toggle = NSSwitch()

    init(title: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.controlSize = .small

        addSubview(titleLabel)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
