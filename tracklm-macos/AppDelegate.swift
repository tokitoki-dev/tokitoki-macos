import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let agentProcess = AgentProcess()
    private let client = AgentClient()

    private var refreshTimer: Timer?
    private var isHealthy = false
    private var todayTokens: Int?

    // Menu items we mutate on refresh.
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let tokensMenuItem = NSMenuItem(title: "Today: —", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "chart.bar.fill", accessibilityDescription: "TokiToki")
        statusItem.button?.image?.isTemplate = true

        buildMenu()

        // Start the sidecar agent, then poll its health/usage.
        agentProcess.start()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        // Give the agent a moment to bind its port before the first probe.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentProcess.stop()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        tokensMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(tokensMenuItem)
        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "s"))
        let dashboard = NSMenuItem(
            title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        menu.addItem(dashboard)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit TokiToki", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func render() {
        statusMenuItem.title = isHealthy ? "● Agent running" : "○ Agent offline"
        if let tokens = todayTokens {
            tokensMenuItem.title = "Today: \(Self.format(tokens)) tokens"
        } else {
            tokensMenuItem.title = "Today: —"
        }
    }

    // MARK: - Actions

    private func refresh() {
        Task { @MainActor in
            isHealthy = await client.isHealthy()
            if isHealthy {
                todayTokens = try? await client.todayTokens()
            } else {
                todayTokens = nil
            }
            render()
        }
    }

    @objc private func syncNow() {
        statusMenuItem.title = "Syncing…"
        Task { @MainActor in
            try? await client.syncNow()
            refresh()
        }
    }

    @objc private func openDashboard() {
        if let url = URL(string: "http://127.0.0.1:9093") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        Task { @MainActor in
            try? await client.quit()
            agentProcess.stop()
            NSApplication.shared.terminate(nil)
        }
    }

    private static func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
