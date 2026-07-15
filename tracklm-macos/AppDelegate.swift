import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var cliUpgradeTimer: Timer?
    private var syncTask: Task<Void, Never>?
    private var syncQueued = false
    private var client: AgentClient?
    private let settingsWindowController = SettingsWindowController()
    private let monitoredAgentsWindowController = MonitoredAgentsWindowController()
    private lazy var usageMonitor = AIUsageMonitor { [weak self] in
        self?.scheduleAutomaticSync()
    }

    private let updater = Updater()

    private let dashboardMenuItem = NSMenuItem(title: "Dashboard", action: #selector(openDashboard), keyEquivalent: "")
    private let monitoredAgentsMenuItem = NSMenuItem(title: "Agents", action: #selector(openMonitoredAgents), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
    private let updatesMenuItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItemIcon()

        buildMenu()
        Task { [weak self] in
            // Seed the shared CLI before the first resolution, so the client
            // binds to the shared copy rather than the bundled fallback.
            await AgentProcess.bootstrap()
            guard let self else { return }
            client = AgentClient()
            usageMonitor.start(providers: AgentPreferences.enabledProviders)
            scheduleAutomaticSync()
            // Silent, and fully owned by the CLI itself — the app only asks.
            await AgentProcess.upgradeSharedCLI()
        }
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 30 * 60,
            target: self,
            selector: #selector(triggerAutomaticSync),
            userInfo: nil,
            repeats: true
        )
        cliUpgradeTimer = Timer.scheduledTimer(
            timeInterval: 24 * 60 * 60,
            target: self,
            selector: #selector(triggerCLIUpgrade),
            userInfo: nil,
            repeats: true
        )
    }

    private func configureStatusItemIcon() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(named: "TrackLMLogo")?.copy() as? NSImage {
            image.isTemplate = true
            image.size = NSSize(width: 15, height: 15)
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.title = "T"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        cliUpgradeTimer?.invalidate()
        syncTask?.cancel()
        usageMonitor.stop()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = 175
        menu.addItem(dashboardMenuItem)
        menu.addItem(monitoredAgentsMenuItem)
        menu.addItem(settingsMenuItem)
        menu.addItem(.separator())
        menu.addItem(updatesMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""))

        for item in menu.items where item.action != nil {
            item.target = self
            item.image = nil
        }
        statusItem.menu = menu
    }

    private func scheduleAutomaticSync() {
        guard syncTask == nil else {
            syncQueued = true
            return
        }
        syncTask = Task { [weak self] in
            guard let self else { return }
            await syncAutomatically()
            syncTask = nil
            if syncQueued {
                syncQueued = false
                scheduleAutomaticSync()
            }
        }
    }

    @objc private func triggerAutomaticSync() {
        scheduleAutomaticSync()
    }

    @objc private func triggerCLIUpgrade() {
        Task { await AgentProcess.upgradeSharedCLI() }
    }

    private func syncAutomatically() async {
        guard let client else { return }

        do {
            guard !(try await client.getAPIKey()).isEmpty else { return }
            try await client.sync(providers: AgentPreferences.enabledProviders)
        } catch let error as AgentClient.AgentError where error.isMissingAPIKey {
            return
        } catch {
            NSLog("TokiToki: %@", Self.menuMessage(for: error))
        }
    }

    @objc private func openSettings() {
        guard let client else { return }
        Task { [weak self] in
            let apiKey: String?
            do {
                apiKey = try await client.getAPIKey()
            } catch let error as AgentClient.AgentError where error.isMissingAPIKey {
                apiKey = nil
            } catch {
                apiKey = nil
                NSLog("TokiToki: %@", Self.menuMessage(for: error))
            }
            self?.settingsWindowController.show(
                apiKey: apiKey
            ) { [weak self] apiKey in
                self?.saveAPIKey(apiKey)
            }
        }
    }

    @objc private func openMonitoredAgents() {
        monitoredAgentsWindowController.show(enabledProviders: AgentPreferences.enabledProviders) { [weak self] providers in
            guard let self else { return }
            AgentPreferences.enabledProviders = providers
            usageMonitor.start(providers: providers)
            scheduleAutomaticSync()
        }
    }

    private func saveAPIKey(_ apiKey: String?) {
        guard let client else { return }
        guard let apiKey else { return }
        Task {
            do {
                try await client.setAPIKey(apiKey)
                scheduleAutomaticSync()
            } catch {
                NSLog("TokiToki: %@", Self.menuMessage(for: error))
            }
        }
    }

    /// AppKit asks every time the menu opens, so the state cannot go stale —
    /// which a one-shot `isEnabled` set at launch certainly would.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(checkForUpdates):
            // Sparkle refuses a check while one is running or an install is
            // staged. Say so, rather than offering a click that does nothing.
            return updater.canCheckForUpdates
        case #selector(openSettings), #selector(openMonitoredAgents):
            return client != nil
        default:
            return true
        }
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func openDashboard() {
        NSWorkspace.shared.open(AppConfig.serverURL)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private static func menuMessage(for error: Error) -> String {
        (error as? AgentClient.AgentError)?.menuMessage ?? "Agent unavailable"
    }
}

private enum AgentPreferences {
    private static let enabledProvidersKey = "enabled_providers"

    static var enabledProviders: [String] {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: enabledProvidersKey) ?? []
            let normalized = AgentProvider.normalize(saved)
            return normalized.isEmpty ? AgentProvider.defaultIDs : normalized
        }
        set { UserDefaults.standard.set(AgentProvider.normalize(newValue), forKey: enabledProvidersKey) }
    }
}
