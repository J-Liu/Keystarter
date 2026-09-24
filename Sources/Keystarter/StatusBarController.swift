// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

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

        switch currentTheme {
        case "hidden":
            button.image = nil
        case "light":
            // Light theme: use dark icon
            if let imagePath = Bundle.main.path(forResource: "menubar-dark", ofType: "png"),
               let image = NSImage(contentsOfFile: imagePath) {
                image.isTemplate = true
                button.image = image
            }
        case "dark":
            // Dark theme: use light icon
            if let imagePath = Bundle.main.path(forResource: "menubar-light", ofType: "png"),
               let image = NSImage(contentsOfFile: imagePath) {
                image.isTemplate = true
                button.image = image
            }
        default:
            // System theme: detect current appearance
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let resourceName = isDarkMode ? "menubar-light" : "menubar-dark"
            if let imagePath = Bundle.main.path(forResource: resourceName, ofType: "png"),
               let image = NSImage(contentsOfFile: imagePath) {
                image.isTemplate = true
                button.image = image
            }
        }
        button.needsDisplay = true
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
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func checkPermissions() {
        let hasAccessibility = PermissionManager.shared.hasAccessibilityPermission()

        if !hasAccessibility {
            // 没有权限，直接弹系统对话框
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
            ] as CFDictionary)
        } else {
            // 有权限，显示权限状态界面
            showPermissionsStatus()
        }
    }

    private func showPermissionsStatus() {
        let alert = NSAlert()
        alert.messageText = L("permissions.status.title")
        alert.informativeText = L("permissions.status.allGranted")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("permissions.status.ok"))

        // 创建自定义视图显示权限列表
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))

        // Accessibility 权限
        let accessibilityIcon = NSImageView(frame: NSRect(x: 10, y: 45, width: 20, height: 20))
        accessibilityIcon.image = NSImage(named: NSImage.statusAvailableName)
        containerView.addSubview(accessibilityIcon)

        let accessibilityLabel = NSTextField(labelWithString: L("permissions.status.accessibility"))
        accessibilityLabel.frame = NSRect(x: 35, y: 45, width: 250, height: 20)
        containerView.addSubview(accessibilityLabel)

        // Input Monitoring 权限
        let inputIcon = NSImageView(frame: NSRect(x: 10, y: 15, width: 20, height: 20))
        inputIcon.image = NSImage(named: NSImage.statusAvailableName)
        containerView.addSubview(inputIcon)

        let inputLabel = NSTextField(labelWithString: L("permissions.status.inputMonitoring"))
        inputLabel.frame = NSRect(x: 35, y: 15, width: 250, height: 20)
        containerView.addSubview(inputLabel)

        alert.accessoryView = containerView
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