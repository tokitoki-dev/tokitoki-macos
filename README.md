# TokiToki Menu Bar (macOS MVP)

A native macOS status-bar app that calls the stateless Go agent CLI and renders
its JSON results.

## Architecture

```
┌─────────────────────────┐       Process + stdout JSON        ┌──────────────────┐
│  TokiToki (Swift, menu   │  ── tokitoki scan ───────────────▶ │  tokitoki CLI    │
│  bar, NSStatusItem)      │  ── tokitoki daily --provider all  │  (Go scanner +   │
│                          │  ── tokitoki sync ───────────────▶ │   uploader)      │
└─────────────────────────┘                                     └──────────────────┘
                                                              ~/.tokitoki/
```

- **Protocol:** the app launches `tokitoki` for each operation and decodes JSON
  from stdout. Errors stay on stderr and are displayed in the menu.
- **Lifecycle:** the app runs `scan` once on launch, refreshes `status` and
  `daily` every minute, and only calls `sync` when the user selects it.
- **Packaging:** the Xcode target compiles the Go module and copies `tokitoki`
  into `TokiToki.app/Contents/Resources`, so the app does not depend on an
  externally running daemon or an old binary in the repository.

## Run (dev)

```sh
# Build and run from Xcode, or use xcodebuild:
cd tracklm-macos
xcodebuild -project tracklm-macos.xcodeproj -scheme tracklm-macos \
  -configuration Debug -derivedDataPath /tmp/tracklm-derived build
open /tmp/tracklm-derived/Build/Products/Debug/tracklm-macos.app
```

A chart icon appears in the menu bar. The menu shows agent status and today's
token total, with **Scan Now**, **Sync Now**, **Open Dashboard**, and **Quit**.

During development, `TOKITOKI_AGENT_BIN` can override the bundled executable.
It must point at the current CLI binary (`tracklm-goagent/bin/tokitoki`), not a
legacy HTTP daemon.

## MVP scope

Implemented: invoke the bundled Go CLI, scan on launch, show today's indexed
tokens and event count, manual Scan/Sync, open the configured server URL, quit.

Not yet: code signing/notarization, API-key configuration UI, a `launchd`
schedule for background sync, launch-at-login.
