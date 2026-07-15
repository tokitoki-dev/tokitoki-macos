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
    private lazy var usageMonitor = AIUsageMonitor { [weak self] in
        self?.scheduleAutomaticSync()
    }

    private let updater = Updater()

    private let enabledSwitch = NSSwitch()
    private let dashboardMenuItem = NSMenuItem(title: "Dashboard", action: #selector(openDashboard), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")

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
            startMonitoringIfEnabled()
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
        menu.addItem(makeEnabledMenuItem())
        menu.addItem(dashboardMenuItem)
        menu.addItem(settingsMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: ""))

        for item in menu.items where item.action != nil {
            item.target = self
            item.image = nil
        }
        statusItem.menu = menu
    }

    private func makeEnabledMenuItem() -> NSMenuItem {
        let label = NSTextField(labelWithString: "Enabled")
        label.font = .menuFont(ofSize: NSFont.systemFontSize(for: .regular))
        label.translatesAutoresizingMaskIntoConstraints = false

        enabledSwitch.controlSize = .small
        enabledSwitch.state = AgentPreferences.trackingEnabled ? .on : .off
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledToggled)
        enabledSwitch.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        container.addSubview(enabledSwitch)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            enabledSwitch.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            enabledSwitch.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func enabledToggled() {
        AgentPreferences.trackingEnabled = enabledSwitch.state == .on
        if AgentPreferences.trackingEnabled {
            startMonitoringIfEnabled()
            scheduleAutomaticSync()
        } else {
            usageMonitor.stop()
        }
    }

    private func startMonitoringIfEnabled() {
        guard AgentPreferences.trackingEnabled else { return }
        usageMonitor.start()
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
        guard AgentPreferences.trackingEnabled, let client else { return }

        do {
            guard !(try await client.getAPIKey()).isEmpty else { return }
            try await client.sync()
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
            guard let self else { return }
            settingsWindowController.show(
                apiKey: apiKey,
                canCheckForUpdates: updater.canCheckForUpdates,
                checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }
            ) { [weak self] apiKey in
                self?.saveAPIKey(apiKey)
            }
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
        case #selector(openSettings):
            return client != nil
        default:
            return true
        }
    }

    @objc private func openDashboard() {
        Task { [weak self] in
            // Signed-in when possible, plain dashboard when not: no API key,
            // no network, or an old server all land on the login page — which
            // is exactly what this menu item did before.
            if let client = self?.client, let url = try? await client.dashboardURL() {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(AppConfig.serverURL)
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private static func menuMessage(for error: Error) -> String {
        (error as? AgentClient.AgentError)?.menuMessage ?? "Agent unavailable"
    }
}

private enum AgentPreferences {
    private static let trackingEnabledKey = "tracking_enabled"

    static var trackingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: trackingEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: trackingEnabledKey) }
    }
}
