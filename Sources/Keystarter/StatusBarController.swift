// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

/// Manages the status bar icon and menu.
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var currentTheme: String = "system"
    private var browserGrantButtons: [NSButton: String] = [:]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: 15)  // Width of status bar icon
        menu = NSMenu()
        currentTheme = UserDefaults.standard.string(forKey: "statusBar.theme") ?? "system"

        super.init()

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

    private var monitorMenuItem: NSMenuItem?
    private var clipboardMenuItem: NSMenuItem?

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

        // Monitor toggle
        let monitorEnabled = UserDefaults.standard.object(forKey: "status.monitor.enabled") as? Bool ?? true
        monitorMenuItem = NSMenuItem(
            title: "Monitor",
            action: #selector(toggleMonitor),
            keyEquivalent: "m"
        )
        monitorMenuItem?.keyEquivalentModifierMask = .command
        monitorMenuItem?.target = self
        monitorMenuItem?.state = monitorEnabled ? .on : .off
        menu.addItem(monitorMenuItem!)

        // Clipboard toggle
        let clipboardEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
        clipboardMenuItem = NSMenuItem(
            title: "Clipboard",
            action: #selector(toggleClipboard),
            keyEquivalent: "c"
        )
        clipboardMenuItem?.keyEquivalentModifierMask = .command
        clipboardMenuItem?.target = self
        clipboardMenuItem?.state = clipboardEnabled ? .on : .off
        menu.addItem(clipboardMenuItem!)

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
        menu.delegate = self
    }

    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh check state from UserDefaults
        let monitorEnabled = UserDefaults.standard.object(forKey: "status.monitor.enabled") as? Bool ?? true
        let clipboardEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
        monitorMenuItem?.state = monitorEnabled ? .on : .off
        clipboardMenuItem?.state = clipboardEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func openLauncher() {
        (NSApp.delegate as? AppDelegate)?.showLauncher()
    }

    @objc private func toggleMonitor(_ sender: NSMenuItem) {
        let currentEnabled = UserDefaults.standard.object(forKey: "status.monitor.enabled") as? Bool ?? true
        let newEnabled = !currentEnabled
        UserDefaults.standard.set(newEnabled, forKey: "status.monitor.enabled")
        sender.state = newEnabled ? .on : .off
        monitorMenuItem?.state = sender.state
        if newEnabled {
            StatusItemController.shared.startMonitoring()
        } else {
            StatusItemController.shared.stopMonitoring()
        }
    }

    @objc private func toggleClipboard(_ sender: NSMenuItem) {
        let currentEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
        let newEnabled = !currentEnabled
        UserDefaults.standard.set(newEnabled, forKey: "clipboard.enabled")
        sender.state = newEnabled ? .on : .off
        clipboardMenuItem?.state = sender.state
        if newEnabled {
            ClipboardManager.shared.start()
        } else {
            ClipboardManager.shared.stop()
        }
    }

    @objc private func checkUpdates() {
        (NSApp.delegate as? AppDelegate)?.hideLauncher()  // Hide launcher first
        DispatchQueue.main.async {
            UpdateManager.shared.checkForUpdates()
        }
    }

    @objc private func checkPermissions() {
        (NSApp.delegate as? AppDelegate)?.hideLauncher()  // Hide launcher first
        showPermissionsStatus()
    }

    private func showPermissionsStatus() {
        let alert = NSAlert()
        alert.messageText = L("permissions.status.title")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("permissions.status.close"))

        // Check permissions
        let hasAccessibility = PermissionManager.shared.hasAccessibilityPermission()

        // Check automation permissions for running browsers
        let browserPermissions = PermissionManager.shared.checkAllBrowserAutomationPermissions()

        // Build status text
        var statusText = ""
        if hasAccessibility && browserPermissions.contains(where: { $0.hasPermission }) {
            statusText = L("permissions.status.allGranted")
        } else if hasAccessibility {
            statusText = L("permissions.status.clickToGrant")
        } else {
            statusText = L("permissions.status.clickToGrant")
        }
        alert.informativeText = statusText

        // Calculate container height based on browser count
        let baseHeight: CGFloat = 60
        let browserHeight: CGFloat = 30
        let containerHeight = baseHeight + CGFloat(browserPermissions.count) * browserHeight + 20
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: containerHeight))

        // Accessibility permission
        let accessibilityIcon = NSImageView(frame: NSRect(x: 10, y: containerHeight - 30, width: 20, height: 20))
        accessibilityIcon.image = NSImage(named: hasAccessibility ? NSImage.statusAvailableName : NSImage.statusUnavailableName)
        containerView.addSubview(accessibilityIcon)

        let accessibilityLabel = NSTextField(labelWithString: L("permissions.status.accessibility"))
        accessibilityLabel.frame = NSRect(x: 35, y: containerHeight - 30, width: 170, height: 20)
        containerView.addSubview(accessibilityLabel)

        if !hasAccessibility {
            let accessibilityButton = NSButton(frame: NSRect(x: 270, y: containerHeight - 32, width: 100, height: 24))
            accessibilityButton.title = L("permissions.status.grant")
            accessibilityButton.bezelStyle = .rounded
            accessibilityButton.target = self
            accessibilityButton.action = #selector(grantAccessibilityPermission)
            containerView.addSubview(accessibilityButton)
        }

        // Automation permissions header
        let automationHeader = NSTextField(labelWithString: L("permissions.status.automation"))
        automationHeader.frame = NSRect(x: 10, y: containerHeight - 55, width: 200, height: 20)
        automationHeader.font = .boldSystemFont(ofSize: 12)
        containerView.addSubview(automationHeader)

        // Automation permission - show browser list
        var yOffset = containerHeight - 80
        for (name, hasPermission) in browserPermissions {
            let browserIcon = NSImageView(frame: NSRect(x: 25, y: yOffset, width: 16, height: 16))
            browserIcon.image = NSImage(named: hasPermission ? NSImage.statusAvailableName : NSImage.statusUnavailableName)
            containerView.addSubview(browserIcon)

            let browserLabel = NSTextField(labelWithString: name)
            browserLabel.frame = NSRect(x: 45, y: yOffset, width: 150, height: 18)
            containerView.addSubview(browserLabel)

            if !hasPermission {
                let grantButton = NSButton(frame: NSRect(x: 270, y: yOffset - 2, width: 100, height: 24))
                grantButton.title = L("permissions.status.grant")
                grantButton.bezelStyle = .rounded
                grantButton.target = self
                grantButton.action = #selector(grantBrowserAutomationPermission(_:))
                browserGrantButtons[grantButton] = name
                containerView.addSubview(grantButton)
            }

            yOffset -= 28
        }

        // Open Automation Settings button
        let openSettingsButton = NSButton(frame: NSRect(x: 10, y: 5, width: 180, height: 24))
        openSettingsButton.title = L("permissions.status.openAutomationSettings")
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.target = self
        openSettingsButton.action = #selector(openAutomationSettings)
        containerView.addSubview(openSettingsButton)

        // Reset permissions button
        let resetButton = NSButton(frame: NSRect(x: 200, y: 5, width: 170, height: 24))
        resetButton.title = L("permissions.status.resetAutomation")
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetAutomationPermissions)
        containerView.addSubview(resetButton)

        alert.accessoryView = containerView
        alert.runModal()
    }

    @objc private func resetAutomationPermissions() {
        PermissionManager.shared.resetAppleEventsPermission {
            DispatchQueue.main.async {
                // Refresh the permissions dialog after reset
                self.showPermissionsStatus()
            }
        }
    }

    @objc private func grantBrowserAutomationPermission(_ sender: NSButton) {
        guard let browserName = browserGrantButtons[sender] else { return }

        // Get bundle ID for browser
        let bundleId: String
        switch browserName {
        case "Safari":
            bundleId = "com.apple.Safari"
        case "Google Chrome":
            bundleId = "com.google.Chrome"
        case "Microsoft Edge":
            bundleId = "com.microsoft.edgemac"
        case "Arc":
            bundleId = "company.thebrowser.Browser"
        default:
            return
        }

        // Request automation permission
        PermissionManager.shared.requestAutomationPermission(for: bundleId) { [weak self] success in
            DispatchQueue.main.async {
                // Refresh the permissions dialog
                self?.showPermissionsStatus()
            }
        }
    }

    @objc private func openAutomationSettings() {
        PermissionManager.shared.openAutomationSettings()
    }

    @objc private func grantAccessibilityPermission() {
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
        ] as CFDictionary)
    }

    @objc private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.hideLauncher()  // Hide launcher first
        (NSApp.delegate as? AppDelegate)?.showSettings()
    }

    @objc private func showAbout() {
        (NSApp.delegate as? AppDelegate)?.hideLauncher()  // Hide launcher first

        // Check if settings window already exists and is open
        for window in NSApp.windows {
            if let settings = window as? SettingsWindow {
                settings.selectTab(withIdentifier: "about")
                settings.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        // No existing window, create new one
        let settings = SettingsWindow()
        settings.selectTab(withIdentifier: "about")
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
