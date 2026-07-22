# Tokitoki Menu Bar for macOS

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
- **Packaging:** the Xcode target compiles the Go CLI for the same architecture
  as the app and copies it into `Tokitoki.app/Contents/Resources`. Release
  builds strip Go debug metadata and local paths. At launch the app atomically
  seeds or upgrades the shared `~/.tokitoki/bin/tokitoki` copy used by every
  client.

## Run (dev)

```sh
# Build and run from Xcode, or use xcodebuild:
cd tokitoki-macos
xcodebuild -project tokitoki-macos.xcodeproj -scheme tokitoki-macos \
  -configuration Debug -derivedDataPath /tmp/tokitoki-derived build
open /tmp/tokitoki-derived/Build/Products/Debug/Tokitoki.app
```

All server access uses `TOKITOKI_BASE_URL`. Without it, the native app and the
CLI it launches both use `https://tokitoki.dev`. To run the app executable
against a local server:

```sh
TOKITOKI_BASE_URL=http://localhost:9093 \
  /tmp/tokitoki-derived/Build/Products/Debug/Tokitoki.app/Contents/MacOS/Tokitoki
```

The status bar uses the Tokitoki icon. Its menu provides **Dashboard**,
**Settings**, tracking control, and **Quit Tokitoki**. Settings provides API
key verification, launch-at-login, version, and Sparkle update controls.

The app prefers the shared CLI and uses the bundled copy as its trusted seed and
fallback. It never requires a long-running local daemon.

Developer ID signing, Apple notarization, native Intel/Apple Silicon DMGs, and
Sparkle signing are automated by the tag release workflow. See
[RELEASING.md](RELEASING.md) for the protected release process.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
