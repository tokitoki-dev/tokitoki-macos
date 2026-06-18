import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let agentProcess = AgentProcess()
    private let client = AgentClient()
    private let activityMonitor = ActivityMonitor()

    private var refreshTimer: Timer?
    private var isHealthy = false
    private var todayTokens: Int?
    private var lastActivity: ActivitySnapshot?
    private var lastHeartbeatAt: Date?

    // Menu items we mutate on refresh.
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let tokensMenuItem = NSMenuItem(title: "Today: —", action: nil, keyEquivalent: "")
    private let activityMenuItem = NSMenuItem(title: "Activity: —", action: nil, keyEquivalent: "")
    private let accessibilityMenuItem = NSMenuItem(
        title: "Enable Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "chart.bar.fill", accessibilityDescription: "TokiToki")
        statusItem.button?.image?.isTemplate = true

        buildMenu()
        activityMonitor.delegate = self

        // Start the sidecar agent, then poll its health/usage.
        agentProcess.start()
        activityMonitor.start()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        // Give the agent a moment to bind its port before the first probe.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityMonitor.stop()
        agentProcess.stop()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        statusMenuItem.isEnabled = false
        tokensMenuItem.isEnabled = false
        activityMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(tokensMenuItem)
        menu.addItem(activityMenuItem)
        menu.addItem(accessibilityMenuItem)
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

        if let lastActivity {
            activityMenuItem.title = "Activity: \(Self.truncate(lastActivity.displayTitle, to: 48))"
        } else {
            activityMenuItem.title = "Activity: —"
        }

        let needsAccessibility = !activityMonitor.isAccessibilityTrusted
        accessibilityMenuItem.isHidden = !needsAccessibility
        accessibilityMenuItem.isEnabled = needsAccessibility
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
            if isHealthy, let lastActivity {
                recordHeartbeat(for: lastActivity)
            }
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

    @objc private func requestAccessibility() {
        _ = activityMonitor.requestAccessibilityPermission()
        render()
    }

    private func recordHeartbeat(for snapshot: ActivitySnapshot) {
        guard isHealthy else { return }
        guard shouldRecordHeartbeat(for: snapshot) else { return }

        lastHeartbeatAt = Date()
        let heartbeat = Heartbeat(
            time: snapshot.timestamp,
            entity: snapshot.entity,
            project: snapshot.bundleIdentifier,
            language: "",
            editor: snapshot.appName,
            type: "app"
        )

        Task {
            do {
                try await client.recordHeartbeat(heartbeat)
            } catch {
                NSLog("TokiToki: failed to record activity heartbeat: \(error)")
            }
        }
    }

    private func shouldRecordHeartbeat(for snapshot: ActivitySnapshot) -> Bool {
        guard let previous = lastActivity else { return true }
        if previous.bundleIdentifier != snapshot.bundleIdentifier || previous.entity != snapshot.entity {
            return true
        }

        guard let lastHeartbeatAt else { return true }
        return Date().timeIntervalSince(lastHeartbeatAt) >= 120
    }

    private static func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func truncate(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }
}

extension AppDelegate: ActivityMonitorDelegate {
    func activityMonitor(_ monitor: ActivityMonitor, didUpdate snapshot: ActivitySnapshot) {
        recordHeartbeat(for: snapshot)
        lastActivity = snapshot
        render()
    }

    func activityMonitor(_ monitor: ActivityMonitor, accessibilityChanged isTrusted: Bool) {
        render()
    }
}
