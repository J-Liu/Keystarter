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
        case "light":
            // Light theme: use dark icon (black)
            if let image = loadAndTintIcon(color: .black) {
                button.image = image
            }
        case "dark":
            // Dark theme: use light icon (white)
            if let image = loadAndTintIcon(color: .white) {
                button.image = image
            }
        default: // system
            // System theme: detect current appearance
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color: NSColor = isDarkMode ? .white : .black
            if let image = loadAndTintIcon(color: color) {
                button.image = image
            } else {
                // Fallback to system icon
                let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keystarter")
                image?.isTemplate = true
                button.image = image
            }
        }
        button.needsDisplay = true
    }

    private func loadAndTintIcon(color: NSColor) -> NSImage? {
        guard let imagePath = Bundle.main.path(forResource: "statusbar-icon", ofType: "png"),
              let originalImage = NSImage(contentsOfFile: imagePath),
              let tiffData = originalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        // Create a new image with the same size
        let size = originalImage.size
        let newImage = NSImage(size: size)

        newImage.lockFocus()

        // Draw the original image
        bitmap.draw(in: NSRect(origin: .zero, size: size))

        // Apply color tint using composite operation
        color.setFill()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)

        newImage.unlockFocus()

        return newImage
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