# Tokitoki for macOS

Menu bar app that syncs the token usage and cost of your local AI coding
agents to your [Tokitoki](https://tokitoki.dev) dashboard: Claude Code,
Codex, GitHub Copilot, Gemini CLI and
[a dozen more](https://github.com/tokitoki-dev/tokitoki-cli#supported-tools).
Every AI session shows up next to your coding time, grouped by project, so
you can see what a feature actually cost.

Developer ID signed, notarized by Apple, native on Apple Silicon and Intel.
Updates itself through Sparkle.

## Install

1. Download the DMG from the
   [latest release](https://github.com/tokitoki-dev/tokitoki-macos/releases/latest):
   `arm64` for Apple Silicon, `amd64` for Intel Macs.
2. Drag **Tokitoki** into Applications and open it.
3. Click the menu bar icon, open **Settings**, and paste the API key from
   [tokitoki.dev/settings](https://tokitoki.dev/settings).

That is the whole setup. Turn on **Launch at login** in Settings and forget
about it.

## What it does

- Syncs on launch, every 30 minutes, and shortly after your agents write new
  session data. It watches their data folders, so a Claude Code session is on
  the dashboard before you get back to it.
- Menu: **Dashboard**, **Settings**, tracking on/off, **Quit Tokitoki**.
- Settings: API key with a **Verify Key** check, launch at login, automatic
  updates, version.
- Bundles [tokitoki-cli](https://github.com/tokitoki-dev/tokitoki-cli) and
  keeps a shared copy in `~/.tokitoki/bin` that the VS Code extension and
  other Tokitoki clients reuse. Nothing runs in the background between syncs.

## Privacy

The app reads token counts, model names and timestamps from your agents'
local data and uploads that metadata over HTTPS with your API key. Never
your code. Delete your data anytime from the dashboard.

## Other clients

[VS Code](https://github.com/tokitoki-dev/tokitoki-vscode) ·
[Windows](https://github.com/tokitoki-dev/tokitoki-windows) ·
[CLI](https://github.com/tokitoki-dev/tokitoki-cli) for servers and scripts.
The overview lives at [github.com/tokitoki-dev](https://github.com/tokitoki-dev).

## Development

```sh
xcodebuild -project tokitoki-macos.xcodeproj -scheme tokitoki-macos \
  -configuration Debug -derivedDataPath /tmp/tokitoki-derived build
open /tmp/tokitoki-derived/Build/Products/Debug/Tokitoki.app
```

Local builds compile the sibling `../tokitoki-cli` checkout so app and CLI
changes can be developed together. Point the app at a local server with
`TOKITOKI_BASE_URL`:

```sh
TOKITOKI_BASE_URL=http://localhost:9093 \
  /tmp/tokitoki-derived/Build/Products/Debug/Tokitoki.app/Contents/MacOS/Tokitoki
```

Work on `dev`; releases are tagged from `main`. How the app drives the CLI
and how the CLI is pinned and verified is in
[ARCHITECTURE.md](ARCHITECTURE.md). Signing, notarization and the tag
release workflow are in [RELEASING.md](RELEASING.md).

## License

[Apache License 2.0](LICENSE)
