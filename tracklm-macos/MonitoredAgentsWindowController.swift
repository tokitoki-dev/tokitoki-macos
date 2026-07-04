import AppKit

enum AgentProvider {
    static let all: [(id: String, title: String)] = [
        ("claude", "Claude Code"),
        ("codex", "Codex"),
        ("copilot", "GitHub Copilot CLI"),
        ("gemini", "Gemini CLI"),
        ("kimi", "Kimi"),
        ("qwen", "Qwen"),
        ("openclaw", "OpenClaw"),
        ("pi", "pi-agent"),
        ("amp", "Amp"),
        ("droid", "Droid"),
        ("kilo", "Kilo"),
        ("hermes", "Hermes Agent"),
        ("codebuff", "Codebuff"),
        ("opencode", "OpenCode"),
        ("goose", "Goose"),
    ]

    static var defaultIDs: [String] {
        all.map { $0.id }
    }

    static func normalize(_ providers: [String]) -> [String] {
        let selected = Set(providers)
        return all.map { $0.id }.filter { selected.contains($0) }
    }
}

@MainActor
final class MonitoredAgentsWindowController: NSWindowController {
    private let agentRows = AgentProvider.all.map { MonitoredAgentRow(provider: $0.id, title: $0.title) }
    private var onChange: (([String]) -> Void)?

    init() {
        let height = CGFloat(32 + AgentProvider.all.count * 40 + max(0, AgentProvider.all.count - 1))
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: height))
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
        let enabled = Set(enabledProviders)
        for row in agentRows {
            row.toggle.state = enabled.contains(row.provider) ? .on : .off
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent(in contentView: NSView) {
        var arrangedViews: [NSView] = []
        for (index, row) in agentRows.enumerated() {
            row.toggle.target = self
            row.toggle.action = #selector(agentToggled)
            if index > 0 {
                let divider = NSView()
                divider.wantsLayer = true
                divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                arrangedViews.append(divider)
            }
            arrangedViews.append(row)
        }

        let rows = NSStackView(views: arrangedViews)
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
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
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
            agentRows.first?.toggle.state = .on
            return
        }
        onChange?(providers)
    }

    private var selectedProviders: [String] {
        agentRows.compactMap { row in
            row.toggle.state == .on ? row.provider : nil
        }
    }
}

@MainActor
private final class MonitoredAgentRow: NSView {
    let provider: String
    let toggle = NSSwitch()

    init(provider: String, title: String) {
        self.provider = provider
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
