import AppKit
import ApplicationServices

struct ActivitySnapshot: Equatable {
    let bundleIdentifier: String
    let appName: String
    let windowTitle: String?
    let timestamp: Date

    var entity: String {
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return appName }
        return title
    }

    var displayTitle: String {
        if entity == appName { return appName }
        return "\(appName): \(entity)"
    }
}

@MainActor
protocol ActivityMonitorDelegate: AnyObject {
    func activityMonitor(_ monitor: ActivityMonitor, didUpdate snapshot: ActivitySnapshot)
    func activityMonitor(_ monitor: ActivityMonitor, accessibilityChanged isTrusted: Bool)
}

@MainActor
final class ActivityMonitor: NSObject {
    weak var delegate: ActivityMonitorDelegate?

    private var pollTimer: Timer?
    private var lastSnapshot: ActivitySnapshot?

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleFrontmostApplication()
            }
        }

        delegate?.activityMonitor(self, accessibilityChanged: isAccessibilityTrusted)
        sampleFrontmostApplication()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        delegate?.activityMonitor(self, accessibilityChanged: trusted)
        return trusted
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        sampleFrontmostApplication()
    }

    private func sampleFrontmostApplication() {
        let trusted = isAccessibilityTrusted
        delegate?.activityMonitor(self, accessibilityChanged: trusted)

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }

        let snapshot = ActivitySnapshot(
            bundleIdentifier: bundleIdentifier,
            appName: app.localizedName ?? bundleIdentifier,
            windowTitle: trusted ? Self.windowTitle(for: app.processIdentifier) : nil,
            timestamp: Date()
        )

        if let previous = lastSnapshot,
           previous.bundleIdentifier == snapshot.bundleIdentifier,
           previous.entity == snapshot.entity,
           snapshot.timestamp.timeIntervalSince(previous.timestamp) < 120 {
            return
        }

        lastSnapshot = snapshot
        delegate?.activityMonitor(self, didUpdate: snapshot)
    }

    private static func windowTitle(for processIdentifier: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &rawWindow
        ) == .success else {
            return nil
        }

        guard let window = rawWindow, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }

        var rawTitle: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &rawTitle
        ) == .success else {
            return nil
        }

        return rawTitle as? String
    }
}
