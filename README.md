# Keystarter

**Lightweight, open-source macOS system utility. Local-first, AI optional. Launcher + Status bar monitor + Clipboard history.**

---

## What is this

Keystarter is a fast, local-first macOS utility. It was built out of a simple frustration: existing tools are either slow, bloated, or force AI into places it doesn't belong.

I use it every day. It combines three things I need in the menu bar: an app launcher, a system monitor (CPU/GPU/memory/disk/network/sensors), and clipboard history. No accounts, no telemetry, no cloud dependency.

## Features

- **App launcher** — `Cmd+Space` to summon, type to filter, Enter to launch
- **Status bar monitor** — Real-time CPU, GPU, memory, disk, network, and sensor (temperature/fan/power) stats in the menu bar
- **Clipboard history** — `Cmd+Shift+V` opens a grouped panel at the cursor, select to paste
- **Dictionary lookup** — `dict <word>` queries the macOS system dictionary directly in the launcher
- **Translation** — `tr <text>` translates without opening another app
- **Local-first** — everything runs on your machine, no network required for core features
- **No AI** — deterministic operations stay deterministic

## Status

**Early development.** Core features work, but things are still moving.

Feedback and feature requests are welcome. Open an issue if something is broken or missing.

## Install

Download the latest `.app` from [GitHub Releases](../../releases).

Since this project has no Apple Developer certificate, macOS will warn you on first launch. Two ways to allow it:

**Option 1: Right-click to open**

1. Drag `Keystarter.app` to `/Applications`
2. Right-click the app → **Open**
3. Click **Open** again in the dialog

**Option 2: Remove quarantine attribute**

```bash
xattr -cr /Applications/Keystarter.app
```

Then open normally.

You'll only need to do this once. Subsequent auto-updates (via Sparkle) won't trigger the warning again.

## Build from source

```bash
git clone https://github.com/J-Liu/Keystarter.git
cd Keystarter
./build.sh
open Keystarter.app
```

Requires Xcode command line tools and macOS 13+.

## Usage

| Action | Shortcut |
|--------|----------|
| Open launcher | `Cmd+Space` |
| Open clipboard history | `Cmd+Shift+V` |
| Launch selected app | `Enter` |
| Close panel | `Esc` |
| Dictionary lookup | `dict <word>` |
| Translation | `tr <text>` |

## Roadmap

- [x] App launcher
- [x] System dictionary lookup
- [x] Translation
- [x] Clipboard history
- [x] Status bar monitor (CPU/GPU/Memory/Disk/Network/Sensors)
- [x] File search via Spotlight
- [ ] Alfred workflow compatibility (implemented, untested)
- [x] Auto-update via Sparkle

## License

AGPL v3. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
