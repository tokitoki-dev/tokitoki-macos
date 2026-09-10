# Architecture

The app is a thin native shell around the stateless
[tokitoki-cli](https://github.com/tokitoki-dev/tokitoki-cli). It never
uploads anything itself.

```
┌─────────────────────────┐       Process + stdout JSON        ┌──────────────────┐
│  Tokitoki (Swift, menu   │  ── tokitoki ────────────────────▶ │  tokitoki CLI    │
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
  those files change. No long-running local daemon is ever required.
- **Packaging:** CI and production builds download the reviewed CLI release
  pinned in `scripts/cli-release-pins.sh`, verify its SHA-256, version, and
  architecture, then copy the matching binary into
  `Tokitoki.app/Contents/Resources`. Local builds fall back to compiling the
  sibling `../tokitoki-cli` checkout so app and CLI changes can be developed
  together.
- **Shared CLI:** at launch the app atomically seeds or upgrades the shared
  `~/.tokitoki/bin/tokitoki` copy used by every Tokitoki client on the
  machine. The app prefers that shared CLI and keeps the bundled copy as its
  trusted seed and fallback.
- **Server:** all access goes through `TOKITOKI_BASE_URL`; without it the app
  and the CLI it launches both use `https://tokitoki.dev`.

Signing, notarization, DMG creation and Sparkle are covered in
[RELEASING.md](RELEASING.md).
