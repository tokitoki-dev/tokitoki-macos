import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var client: AgentClient?
    private var agentStatus: AgentStatus?
    private var todayTokens: UInt64?

    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let tokensMenuItem = NSMenuItem(title: "Today: —", action: nil, keyEquivalent: "")
    private let indexedMenuItem = NSMenuItem(title: "Indexed: —", action: nil, keyEquivalent: "")
    private let scanMenuItem = NSMenuItem(title: "Scan Now", action: #selector(scanNow), keyEquivalent: "r")
    private let syncMenuItem = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "s")
    private let dashboardMenuItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "chart.bar.fill", accessibilityDescription: "TokiToki")
        statusItem.button?.image?.isTemplate = true

        buildMenu()
        client = AgentClient()
        Task { await scanAndRefresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func buildMenu() {
        let menu = NSMenu()
        [statusMenuItem, tokensMenuItem, indexedMenuItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }
        menu.addItem(.separator())
        menu.addItem(scanMenuItem)
        menu.addItem(syncMenuItem)
        menu.addItem(dashboardMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TokiToki", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func refresh() async {
        guard let client else {
            agentStatus = nil
            todayTokens = nil
            render(error: "CLI not found")
            return
        }

        do {
            let status = try await client.status()
            let tokens = try await client.todayTokens()
            agentStatus = status
            todayTokens = tokens
            render()
        } catch {
            agentStatus = nil
            todayTokens = nil
            render(error: error.localizedDescription)
        }
    }

    private func scanAndRefresh() async {
        guard let client else {
            render(error: "CLI not found")
            return
        }

        render(message: "Scanning local AI usage…")
        do {
            _ = try await client.scan()
        } catch {
            render(error: error.localizedDescription)
            return
        }
        await refresh()
    }

    private func render(message: String? = nil, error: String? = nil) {
        if let error {
            statusMenuItem.title = "○ \(Self.truncate(error, to: 64))"
            scanMenuItem.isEnabled = client != nil
            syncMenuItem.isEnabled = client != nil
            dashboardMenuItem.isEnabled = false
            return
        }
        if let message {
            statusMenuItem.title = message
            scanMenuItem.isEnabled = false
            syncMenuItem.isEnabled = false
            dashboardMenuItem.isEnabled = false
            return
        }

        statusMenuItem.title = agentStatus == nil ? "○ CLI unavailable" : "● Go agent ready"
        tokensMenuItem.title = todayTokens.map { "Today: \(Self.format($0)) tokens" } ?? "Today: —"
        indexedMenuItem.title = agentStatus.map { "Indexed: \(Self.format($0.indexedEvents)) events" } ?? "Indexed: —"
        scanMenuItem.isEnabled = client != nil
        syncMenuItem.isEnabled = client != nil && agentStatus?.hasAPIKey == true
        dashboardMenuItem.isEnabled = URL(string: agentStatus?.serverURL ?? "") != nil
    }

    @objc private func scanNow() {
        Task { await scanAndRefresh() }
    }

    @objc private func syncNow() {
        guard let client else { return }
        render(message: "Syncing…")
        Task {
            do {
                _ = try await client.syncNow()
                await refresh()
            } catch {
                render(error: error.localizedDescription)
            }
        }
    }

    @objc private func openDashboard() {
        guard let serverURL = agentStatus?.serverURL, let url = URL(string: serverURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private static func format(_ value: some BinaryInteger) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: Int64(value))) ?? "\(value)"
    }

    private static func truncate(_ value: String, to limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }
}
