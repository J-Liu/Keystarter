# Keystarter

**Lightweight, open-source macOS launcher. Local-first, AI optional. Clipboard history + Alfred workflow compatibility.**

---

## What is this

Keystarter is a fast, local-first launcher for macOS. It was built out of a simple frustration: existing launchers are either slow, bloated, or force AI into places it doesn't belong.

I use it every day. It launches apps, looks up words in the system dictionary, translates text, and manages clipboard history. No accounts, no telemetry, no cloud dependency.

## Features

- **App launcher** — `Cmd+Space` to summon, type to filter, Enter to launch
- **Dictionary lookup** — `dict <word>` queries the macOS system dictionary directly in the launcher
- **Translation** — `tr <text>` translates without opening another app
- **Clipboard history** — `Cmd+Shift+V` opens a grouped panel at the cursor, select to paste
- **Local-first** — everything runs on your machine, no network required for core features
- **No AI** — deterministic operations stay deterministic

## Status

**Early development.** Core features work, but things are still moving. Alfred workflow compatibility is planned but not yet implemented.

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

You'll only need to do this once. Subsequent auto-updates (once implemented) won't trigger the warning again.

## Build from source

```bash
git clone https://github.com/J-Liu/Keystarter.git
cd Keystarter
./scripts/build-app.sh
open build/Keystarter.app
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
- [ ] SQLite file index
- [ ] Alfred workflow compatibility
- [ ] Auto-update via Sparkle

## License

AGPL v3. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
