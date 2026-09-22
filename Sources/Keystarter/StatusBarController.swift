// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Manages the status bar icon and menu.
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let menu: NSMenu

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        setupIcon()
        setupMenu()
    }

    private func setupIcon() {
        // Use a simple keyboard-like icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keystarter")
            button.image?.isTemplate = true
        }
    }

    private func setupMenu() {
        // Open Launcher
        let openItem = NSMenuItem(
            title: "Open Keystarter",
            action: #selector(openLauncher),
            keyEquivalent: " "
        )
        openItem.keyEquivalentModifierMask = .command
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Check for Updates (placeholder)
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkUpdates),
            keyEquivalent: ""
        )
        menu.addItem(updateItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About Keystarter",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Keystarter",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openLauncher() {
        (NSApp.delegate as? AppDelegate)?.showLauncher()
    }

    @objc private func checkUpdates() {
        // Placeholder - would call UpdateManager when Sparkle is integrated
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = "Auto-update is not configured yet.\nSee docs/SPARKLE_SETUP.md for instructions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.showSettings()
    }

    @objc private func showAbout() {
        let settings = SettingsWindow()
        settings.selectTab(withIdentifier: "about")
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}