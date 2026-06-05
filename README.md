# TokiToki Menu Bar (macOS MVP)

A native macOS status-bar app that supervises the Go agent as a sidecar child
process and talks to it over HTTP loopback.

## Architecture

```
┌─────────────────────────┐         HTTP 127.0.0.1:39391        ┌──────────────────┐
│  TokiToki (Swift, menu    │  ── GET /health (no auth) ───────▶  │  tokitoki-agent  │
│  bar, NSStatusItem)      │  ── GET /usage/daily (Bearer) ───▶  │  (Go HTTP server │
│                          │  ── POST /sync (Bearer) ─────────▶  │   + log scanner) │
│  spawns as child ───────────────────────────────────────────▶ │                  │
└─────────────────────────┘                                     └──────────────────┘
        reads token from ~/.goagent/agent.token
```

- **Protocol: HTTP over loopback.** The agent already runs a REST API
  (`internal/httpapi`), so the app is just a client + process supervisor.
- **Auth:** protected endpoints need `Authorization: Bearer <token>`. The agent
  writes the token to a shared file on first run; the app reads it. No extra IPC.
- **Lifecycle:** the app starts the agent on launch and terminates it on quit.

## Run (dev)

```sh
# 1. Build the agent
cd ../tracklm-goagent && make build

# 2. Build + run the menu bar app, pointing it at the agent binary
cd ../tracklm-macos
export TOKITOKI_AGENT_BIN="$PWD/../tracklm-goagent/bin/tokitoki-agent"
swift run
```

A chart icon appears in the menu bar. The menu shows agent status and today's
token total, with **Sync Now**, **Open Dashboard**, and **Quit**.

## MVP scope

Implemented: spawn agent, show running/offline status, show today's tokens,
manual Sync Now, open the cloud dashboard, quit (stops the agent too).

Not yet: packaged `.app` bundle / code signing, API-key configuration UI,
auto-restart if the agent crashes, launch-at-login.
