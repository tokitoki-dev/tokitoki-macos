# TokiToki Menu Bar (macOS MVP)

A native macOS status-bar app that calls the stateless Go agent CLI and renders
its JSON results.

## Architecture

```
┌─────────────────────────┐       Process + stdout JSON        ┌──────────────────┐
│  TokiToki (Swift, menu   │  ── tokitoki ────────────────────▶ │  tokitoki CLI    │
│  bar, NSStatusItem)      │                                     │  (Go scanner +   │
│                          │                                     │   uploader)      │
└─────────────────────────┘                                     └──────────────────┘
                                                              ~/.tokitoki/
```

- **Protocol:** the app launches `tokitoki` for each automatic upload and
  decodes its minimal success response. Detailed diagnostics stay on stderr;
  the menu shows a short, actionable status only.
- **Lifecycle:** on launch and every 30 minutes, the app invokes the CLI when
  an API key is configured. It also recursively watches the selected Claude
  Code/Codex data folders and invokes the CLI after a short debounce whenever
  those files change.
- **Packaging:** the Xcode target compiles the Go module and copies `tokitoki`
  into `TokiToki.app/Contents/Resources`, so the app does not depend on an
  externally running daemon or an old binary in the repository.

## Run (dev)

```sh
# Build and run from Xcode, or use xcodebuild:
cd tokitoki-macos
xcodebuild -project tokitoki-macos.xcodeproj -scheme tokitoki-macos \
  -configuration Debug -derivedDataPath /tmp/tokitoki-derived build
open /tmp/tokitoki-derived/Build/Products/Debug/tokitoki-macos.app
```

The status bar uses a neutral text affordance rather than an app icon. Its menu
shows a short sync status, with **Open Dashboard**, **Settings**, and **Quit**.
Settings provides API key and launch-at-login controls. Agents chooses the local
clients to read (**Claude Code** and/or **Codex**).

The app always invokes the bundled CLI at
`TokiToki.app/Contents/Resources/tokitoki`.

## MVP scope

Implemented: invoke the bundled Go CLI, automatically upload selected local
clients, configure the API key and enabled clients, register launch-at-login,
show the app version, open the local dashboard, and quit.

Not yet: code signing/notarization and a `launchd` schedule that can sync while
the app is not running.
