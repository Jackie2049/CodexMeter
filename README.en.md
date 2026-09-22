<div align="center">

# CodexMeter

**A lightweight macOS menu bar app for Codex quota monitoring**

[简体中文](README.md) | [English](README.en.md)

[![CI](https://github.com/Jackie2049/CodexMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/Jackie2049/CodexMeter/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Jackie2049/CodexMeter)](https://github.com/Jackie2049/CodexMeter/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

</div>

CodexMeter puts your Codex quota in the macOS menu bar — two lines of live text showing the remaining quota and reset time for both the 5-hour and weekly windows. Hover to peek, click to pin, zero interruptions.

<!-- TODO: screenshot from the real app with personal info redacted, to be added by the maintainer -->

## Features

- **Two-line status item**: `⚡ 5h 84% · ↻ in 3h 12m` / `⚡ Weekly 81% · ↻ in 6d 8h` — one line per window, quota and reset time side by side
- **Hover to peek**: the detail panel (progress bars, large percentages, reset times) pops up after 0.15s of hovering and dismisses when you move away; click to pin
- **Threshold alerts**: notified when the 5-hour/weekly quota drops below the threshold (80%/90% by default, once per window), and immediately when the limit is hit
- **Recovery reminder**: after a limit episode, a notification confirms once fresh data shows the quota is back (independent toggle)
- **Data freshness**: ⚠️ appears in the menu bar on refresh failure or stale data — old numbers never pose as live ones
- **Trilingual UI**: 简体中文 / English / 繁體中文, switchable in settings
- **Quiet**: fully local, no Dock icon, adjustable polling (30s/1m/5m), pauses with system sleep

## Install

1. Download `CodexMeter-vX.Y.Z.zip` from [Releases](https://github.com/Jackie2049/CodexMeter/releases) and unzip
2. Move `CodexMeter.app` to `/Applications`
3. Run `xattr -cr /Applications/CodexMeter.app` — the build is unsigned and un-notarized, so Gatekeeper would block it otherwise
4. Launch CodexMeter — you need to have logged in via `codex login` first (the app reads `~/.codex/auth.json`)

> ⚠️ This project is **not notarized** (requires a paid Apple Developer ID). Removing the quarantine attribute is enough; build from source if you prefer.

## Usage

| Interaction | Behavior |
|---|---|
| Hover the status item | Detail panel pops up after 0.15s |
| Move the mouse away | Panel auto-dismisses |
| Click the icon | Panel pops up and **pins** (click again or click outside to dismiss) |
| Gear menu | Poll interval / threshold alerts / recovery reminder / UI language / launch at login |

Login and token refresh reuse the Codex CLI credential flow — the tool never interferes with the Codex client itself.

## Data & Privacy

CodexMeter runs entirely locally: it reads the OAuth credentials in `~/.codex/auth.json` (shared with the Codex CLI) and queries OpenAI's usage endpoint. **It connects to no other server and collects or uploads nothing.** Refreshed tokens are written back to `auth.json`, matching the official client's behavior.

## Build

Requires the Swift 6 toolchain (Xcode 16 or Command Line Tools — full Xcode not needed).

```bash
git clone https://github.com/Jackie2049/CodexMeter.git
cd CodexMeter
swift build
bash Scripts/test.sh     # 49 tests
bash Scripts/make_app.sh # assemble CodexMeter.app into build/
```

## Architecture

See [docs/architecture.md](docs/architecture.md) — module map, data flow, and the key design decisions (why the status item doesn't use MenuBarExtra, the recovery semantics, the custom test harness, and more).

## Notice & Acknowledgments

- This is an **unofficial** personal tool, not affiliated with OpenAI. OpenAI, Codex, ChatGPT and their marks belong to their respective owners
- Design and implementation draw inspiration from [steipete/CodexBar](https://github.com/steipete/CodexBar), a more complete open-source app in the same space
- Issues welcome; see the repository's evolution notes for where the project is heading

## License

[MIT](LICENSE) © 2025 Jackie2049
