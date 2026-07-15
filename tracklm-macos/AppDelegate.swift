import AppKit
import Combine
import SwiftUI

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

    private let enabledModel = EnabledMenuModel(isOn: AgentPreferences.trackingEnabled)
    private let dashboardMenuItem = NSMenuItem(title: "Dashboard", action: #selector(openDashboard), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItemIcon()

        enabledModel.onChange = { [weak self] isOn in
            guard let self else { return }
            AgentPreferences.trackingEnabled = isOn
            if isOn {
                startMonitoringIfEnabled()
                scheduleAutomaticSync()
            } else {
                usageMonitor.stop()
            }
        }
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
        // NSMenu sizes a custom item by the view's frame, so the hosting view
        // needs a real one; width tracks the menu via autoresizing.
        let hosting = NSHostingView(rootView: EnabledMenuRow(model: enabledModel))
        hosting.frame = NSRect(x: 0, y: 0, width: 175, height: 28)
        hosting.autoresizingMask = [.width]

        let item = NSMenuItem()
        item.view = hosting
        return item
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

@MainActor
private final class EnabledMenuModel: ObservableObject {
    @Published var isOn: Bool {
        didSet { onChange?(isOn) }
    }
    var onChange: ((Bool) -> Void)?

    init(isOn: Bool) {
        self.isOn = isOn
    }
}

private struct EnabledMenuRow: View {
    @ObservedObject var model: EnabledMenuModel

    var body: some View {
        HStack {
            Text("Enabled")
                .font(.system(size: 13))
            Spacer()
            Toggle("Enabled", isOn: $model.isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        // The menu of a status-bar app never belongs to the key window, and an
        // inactive-looking NSSwitch draws gray instead of the accent color.
        .environment(\.appearsActive, true)
    }
}

private enum AgentPreferences {
    private static let trackingEnabledKey = "tracking_enabled"

    static var trackingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: trackingEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: trackingEnabledKey) }
    }
}
