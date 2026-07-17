//
//  tokitoki_macosApp.swift
//  tokitoki-macos
//
//  Menu bar app entry. SwiftUI owns @main but hands off to the AppKit
//  AppDelegate, which manages the NSStatusItem and the Go sidecar agent.
//

import SwiftUI

@main
struct tokitoki_macosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Tahoe auto-decorates common actions (Settings, Quit, …) with SF
        // Symbols, which indents every other item. AppKit reads this flag
        // during framework setup, so it must be registered before the
        // application object finishes launching — not in the app delegate.
        UserDefaults.standard.register(defaults: ["NSMenuEnableActionImages": false])
    }

    var body: some Scene {
        // No window — this is a menu bar (LSUIElement) app. Settings provides an
        // empty scene so SwiftUI is satisfied without showing UI on launch.
        Settings {
            EmptyView()
        }
    }
}
