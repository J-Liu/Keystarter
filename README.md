# Keystarter

A fast, native macOS launcher app - alternative to Alfred/Spotlight.

## Features

- **Cmd+Space** - Global hotkey to toggle launcher
- **App Search** - Fuzzy search across installed applications
- **File Search** - SQLite FTS5 powered file indexing
- **Dictionary** - `dict <word>` to look up in macOS Dictionary
- **Translate** - `tr <text>` to translate via Google Translate
- **Alfred Workflows** - Import and run Alfred workflows (experimental)
- **Multi-monitor** - Opens on the screen with your cursor
- **Frequency Ranking** - Frequently used items appear first

## Installation

### Build from Source

```bash
git clone https://github.com/YOUR_USERNAME/Keystarter.git
cd Keystarter
./scripts/build-app.sh
open build/Keystarter.app
```

### Requirements

- macOS 13.0+
- Xcode 15+ (for building from source)

## Usage

1. Press `Cmd + Space` to open the launcher
2. Type to search apps, files, or use commands
3. Use arrow keys to navigate, Enter to select, Esc to close

### Built-in Commands

| Command | Description |
|---------|-------------|
| `dict <word>` | Look up word in macOS Dictionary |
| `tr <text>` | Translate text via Google Translate |

### Alfred Workflows

Place `.alfredworkflow` files in:
```
~/Library/Application Support/Keystarter/Workflows/
```

## Configuration

Settings are stored in `~/Library/Application Support/Keystarter/`:
- `history.plist` - Launch frequency data
- `index.db` - File search index

Appearance can be customized via UserDefaults:
```bash
defaults write com.keystarter.app appearance.cornerRadius -float 16
defaults write com.keystarter.app appearance.opacity -float 0.9
defaults write com.keystarter.app appearance.material -string "popover"
```

## Development

```
Sources/Keystarter/
├── AppDelegate.swift      # App lifecycle
├── LauncherWindow.swift   # Main UI
├── HotkeyManager.swift    # Global hotkey
├── LaunchItem.swift       # Result item model
├── Index/                 # File indexing
│   ├── IndexDatabase.swift
│   ├── IndexScanner.swift
│   └── IndexWatcher.swift
├── Plugins/               # Plugin system
│   ├── Plugin.swift
│   ├── PluginManager.swift
│   ├── DictionaryPlugin.swift
│   └── TranslatePlugin.swift
├── Workflows/             # Alfred compatibility
│   ├── AlfredWorkflow.swift
│   ├── AlfredExecutor.swift
│   ├── AlfredWorkflowPlugin.swift
│   └── AlfredWorkflowManager.swift
└── Utils/                 # Utilities
    ├── LaunchHistory.swift
    └── AppearanceSettings.swift
```

## License

AGPL-3.0-or-later

## Acknowledgments

Inspired by [Alfred](https://www.alfredapp.com/), [Spotlight](https://support.apple.com/guide/mac-help/spotlight-mhlp9a2b0b3a/mac), and [Raycast](https://www.raycast.com/).