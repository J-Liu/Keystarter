// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Manages the status bar icon and menu.
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var currentTheme: String = "system"

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        currentTheme = UserDefaults.standard.string(forKey: "statusBar.theme") ?? "system"

        setupIcon()
        setupMenu()
    }

    private func setupIcon() {
        guard let button = statusItem.button else { return }

        // Clear previous tint
        button.contentTintColor = nil

        switch currentTheme {
        case "hidden":
            button.image = nil
        default:
            // Load custom icon from bundle
            if let image = NSImage(named: "Keystarter") {
                let resizedImage = resizeImage(image, to: NSSize(width: 18, height: 18))
                resizedImage.isTemplate = true
                button.image = resizedImage
            } else {
                // Fallback to system icon
                let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keystarter")
                image?.isTemplate = true
                button.image = image
            }
        }
        button.needsDisplay = true
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        return resizedImage
    }

    /// Update the status bar icon theme.
    func updateTheme(_ theme: String) {
        currentTheme = theme
        if theme == "hidden" {
            statusItem.isVisible = false
        } else {
            statusItem.isVisible = true
            setupIcon()
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
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Check for Updates (placeholder)
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        // Check Permissions
        let permissionsItem = NSMenuItem(
            title: "Check Permissions...",
            action: #selector(checkPermissions),
            keyEquivalent: ""
        )
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About Keystarter",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Keystarter",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
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

    @objc private func checkPermissions() {
        PermissionManager.shared.requestAllPermissions {
            // Permissions granted
        }
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