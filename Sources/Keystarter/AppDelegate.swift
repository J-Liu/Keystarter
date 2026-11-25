// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var launcherWindow: LauncherWindow?
    private var clipboardPanel: ClipboardPanel?
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindow?
    var isIndexReady = false
    private var browserGrantButtons: [NSButton: String] = [:]

    // Hotkey key codes for tracking
    private var launcherKeyCode: UInt16 = 49
    private var launcherModifiers: NSEvent.ModifierFlags = .command
    private var clipboardKeyCode: UInt16 = 9
    private var clipboardModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var readlaterKeyCode: UInt16 = 1
    private var readlaterModifiers: NSEvent.ModifierFlags = [.command, .option]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        applyInitialTheme()
        setupStatusBar()
        setupIndex()
        updateDockIconVisibility()
        
        // Initialize status bar modules (must be done before settings window)
        _ = StatusItemController.shared
        
        // Start running app monitoring (every hour)
        startRunningAppMonitoring()

        // Create the launcher window (hidden initially)
        launcherWindow = LauncherWindow()

        // Register global hotkey with saved or default settings
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkey.keyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkey.modifiers")
        launcherKeyCode = savedKeyCode > 0 ? UInt16(savedKeyCode) : UInt16(49) // Space
        if savedModifiers > 0 {
            launcherModifiers = NSEvent.ModifierFlags(rawValue: UInt(savedModifiers))
        }

        HotkeyManager.shared.register(keyCode: launcherKeyCode, modifiers: launcherModifiers) { [weak self] in
            self?.launcherWindow?.toggle()
        }

        PluginManager.shared.register(DictionaryPlugin())
        PluginManager.shared.register(TranslatePlugin())
        PluginManager.shared.register(CalculatorPlugin())
        PluginManager.shared.register(KillPlugin())
        PluginManager.shared.register(SystemCommandPlugin())
        PluginManager.shared.register(IPPlugin())
        PluginManager.shared.register(ColorPlugin())
        PluginManager.shared.register(ConvertPlugin())
        PluginManager.shared.register(StockPlugin())
        PluginManager.shared.register(ReadLaterPlugin())

        // Load Alfred workflows
        AlfredWorkflowManager.shared.loadAll()

        // Start clipboard manager if enabled (default true)
        let clipboardEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
        if clipboardEnabled {
            ClipboardManager.shared.start()
        }

        // Start monitor if enabled (default true)
        let monitorEnabled = UserDefaults.standard.object(forKey: "status.monitor.enabled") as? Bool ?? true
        if !monitorEnabled {
            StatusItemController.shared.stopMonitoring()
        }

        // Start update manager
        UpdateManager.shared.startUpdater()
        UpdateManager.shared.checkForUpdatesOnLaunch()

        // Load power management settings
        PowerManager.shared.loadSettings()

        // Setup clipboard panel and hotkey
        clipboardPanel = ClipboardPanel()
        
        // Load saved clipboard hotkey
        let savedClipboardKeyCode = UserDefaults.standard.integer(forKey: "clipboard.hotkey.keyCode")
        let savedClipboardModifiers = UserDefaults.standard.integer(forKey: "clipboard.hotkey.modifiers")
        if savedClipboardKeyCode > 0 {
            clipboardKeyCode = UInt16(savedClipboardKeyCode)
        }
        if savedClipboardModifiers > 0 {
            clipboardModifiers = NSEvent.ModifierFlags(rawValue: UInt(savedClipboardModifiers))
        }

        HotkeyManager.shared.register(keyCode: clipboardKeyCode, modifiers: clipboardModifiers) { [weak self] in
            let clipboardEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
            if clipboardEnabled {
                self?.clipboardPanel?.toggle()
            }
        }

        // Register read later hotkey with saved or default settings
        let savedReadlaterKeyCode = UserDefaults.standard.integer(forKey: "readlater.hotkey.keyCode")
        let savedReadlaterModifiers = UserDefaults.standard.integer(forKey: "readlater.hotkey.modifiers")
        if savedReadlaterKeyCode > 0 {
            readlaterKeyCode = UInt16(savedReadlaterKeyCode)
        }
        if savedReadlaterModifiers > 0 {
            readlaterModifiers = NSEvent.ModifierFlags(rawValue: UInt(savedReadlaterModifiers))
        }

        HotkeyManager.shared.register(keyCode: readlaterKeyCode, modifiers: readlaterModifiers) { [weak self] in
            if let result = ReadLaterManager.shared.getCurrentBrowserURL() {
                ReadLaterManager.shared.add(url: result.url, title: result.title)
                // Show confirmation notification
                DispatchQueue.main.async {
                    let content = UNMutableNotificationContent()
                    content.title = L("readlater.saved")
                    content.body = result.title
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
            } else {
                DispatchQueue.main.async {
                    // Check if it's a permission error
                    if let error = ReadLaterManager.shared.lastError, error.contains("Not authorized") {
                        self?.showAutomationPermissionDialog()
                    } else {
                        // Show other errors as notification
                        let content = UNMutableNotificationContent()
                        content.title = L("readlater.error.title")
                        content.body = ReadLaterManager.shared.lastError ?? L("readlater.error.noBrowser")
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request)
                    }
                }
            }
        }

        // Show setup wizard on first launch
        if PermissionManager.shared.isFirstLaunch {
            showSetupWizard()
        }
    }

    /// Show the first-time setup wizard.
    private func showSetupWizard() {
        let wizard = SetupWizardWindow()
        wizard.onComplete = { [weak self] in
            // Reload hotkey settings after wizard
            let keyCode = UserDefaults.standard.integer(forKey: "hotkey.keyCode")
            let modifiers = UserDefaults.standard.integer(forKey: "hotkey.modifiers")
            if keyCode > 0 {
                self?.updateHotkey(keyCode: UInt16(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
            }
        }
        wizard.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Update the global hotkey.
    func updateHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        HotkeyManager.shared.unregister(keyCode: launcherKeyCode)
        launcherKeyCode = keyCode
        launcherModifiers = modifiers
        HotkeyManager.shared.register(keyCode: launcherKeyCode, modifiers: launcherModifiers) { [weak self] in
            self?.launcherWindow?.toggle()
        }
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkey.keyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkey.modifiers")
    }

    /// Update the clipboard hotkey.
    func updateClipboardHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        HotkeyManager.shared.unregister(keyCode: clipboardKeyCode)
        clipboardKeyCode = keyCode
        clipboardModifiers = modifiers
        HotkeyManager.shared.register(keyCode: clipboardKeyCode, modifiers: clipboardModifiers) { [weak self] in
            let clipboardEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
            if clipboardEnabled {
                self?.clipboardPanel?.toggle()
            }
        }
        UserDefaults.standard.set(Int(keyCode), forKey: "clipboard.hotkey.keyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "clipboard.hotkey.modifiers")
    }

    /// Update the read later hotkey.
    func updateReadLaterHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        HotkeyManager.shared.unregister(keyCode: readlaterKeyCode)
        readlaterKeyCode = keyCode
        readlaterModifiers = modifiers
        HotkeyManager.shared.register(keyCode: readlaterKeyCode, modifiers: readlaterModifiers) {
            if let result = ReadLaterManager.shared.getCurrentBrowserURL() {
                ReadLaterManager.shared.add(url: result.url, title: result.title)
                DispatchQueue.main.async {
                    let content = UNMutableNotificationContent()
                    content.title = L("readlater.saved")
                    content.body = result.title
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }

    /// Update the status bar icon theme.
    func updateStatusBarTheme(_ theme: String) {
        statusBarController?.updateTheme(theme)
    }

    func updateDockIconVisibility() {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        if showDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func applyInitialTheme() {
        let theme = UserDefaults.standard.string(forKey: "app.theme") ?? "system"
        let appearance: NSAppearance?
        switch theme {
        case "light":
            appearance = NSAppearance(named: .aqua)
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil  // System default
        }
        NSApp.appearance = appearance
    }

    /// Full menu for Dock icon and system menu bar.
    private func setupMenu() {
        updateMenu()
        // Listen for language changes
        NotificationCenter.default.addObserver(self, selector: #selector(updateMenu), name: .languageChanged, object: nil)
    }

    @objc private func updateMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L("menu.about"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L("menu.settings"),
            action: #selector(showSettingsFromMenu),
            keyEquivalent: ","
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Open Keystarter",
            action: #selector(openLauncherFromMenu),
            keyEquivalent: " "
        )

        // Monitor toggle
        let monitorEnabled = UserDefaults.standard.object(forKey: "status.monitor.enabled") as? Bool ?? true
        let monitorItem = NSMenuItem(
            title: "Monitor",
            action: #selector(toggleMonitorFromMenu),
            keyEquivalent: "m"
        )
        monitorItem.target = self
        monitorItem.state = monitorEnabled ? .on : .off
        appMenu.addItem(monitorItem)

        // Clipboard toggle
        let clipboardEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
        let clipboardItem = NSMenuItem(
            title: "Clipboard",
            action: #selector(toggleClipboardFromMenu),
            keyEquivalent: "c"
        )
        clipboardItem.target = self
        clipboardItem.state = clipboardEnabled ? .on : .off
        appMenu.addItem(clipboardItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L("menu.checkUpdates"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        appMenu.addItem(
            withTitle: L("menu.checkPermissions"),
            action: #selector(checkPermissionsFromMenu),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L("menu.closeWindow"),
            action: #selector(closeWindow),
            keyEquivalent: "w"
        )
        appMenu.addItem(
            withTitle: L("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        launcherWindow?.hide()  // Hide launcher first
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.selectTab(withIdentifier: "about")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsFromMenu() {
        launcherWindow?.hide()  // Hide launcher first
        showSettings()
    }

    @objc private func openLauncherFromMenu() {
        showLauncher()
    }

    @objc private func checkForUpdates() {
        launcherWindow?.hide()  // Hide launcher first
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func checkPermissionsFromMenu() {
        launcherWindow?.hide()  // Hide launcher first
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

    @objc private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    @objc private func toggleMonitorFromMenu(_ sender: NSMenuItem) {
        let currentEnabled = UserDefaults.standard.object(forKey: "status.monitor.enabled") as? Bool ?? true
        let newEnabled = !currentEnabled
        UserDefaults.standard.set(newEnabled, forKey: "status.monitor.enabled")
        sender.state = newEnabled ? .on : .off
        if newEnabled {
            StatusItemController.shared.startMonitoring()
        } else {
            StatusItemController.shared.stopMonitoring()
        }
    }

    @objc private func toggleClipboardFromMenu(_ sender: NSMenuItem) {
        let currentEnabled = UserDefaults.standard.object(forKey: "clipboard.enabled") as? Bool ?? true
        let newEnabled = !currentEnabled
        UserDefaults.standard.set(newEnabled, forKey: "clipboard.enabled")
        sender.state = newEnabled ? .on : .off
        if newEnabled {
            ClipboardManager.shared.start()
        } else {
            ClipboardManager.shared.stop()
        }
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController()
    }

    private func showAutomationPermissionDialog() {
        // Get the frontmost browser
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return
        }

        // Save the browser bundle ID for later use (after dialog, frontmost app will be Keystarter)
        let savedBundleId = bundleId

        // Find browser name
        let browserName: String
        switch bundleId {
        case "com.apple.Safari":
            browserName = "Safari"
        case "com.google.Chrome":
            browserName = "Google Chrome"
        case "com.microsoft.edgemac":
            browserName = "Microsoft Edge"
        case "company.thebrowser.Browser":
            browserName = "Arc"
        default:
            return
        }

        let alert = NSAlert()
        alert.messageText = L("automation.permission.title")
        alert.informativeText = String(format: L("automation.permission.howto"), browserName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("automation.permission.grant"))
        alert.addButton(withTitle: L("automation.permission.adjust"))
        alert.addButton(withTitle: L("permissions.status.close"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Grant: use osascript to trigger permission dialog (no reset)
            if LogSettings.shared.readlaterLogEnabled {
                LogSettings.write("[ReadLater] Attempting to get URL from \(savedBundleId) via osascript", to: LogSettings.shared.readlaterLogPath)
            }

            // Build AppleScript for the specific browser
            let script: String
            switch savedBundleId {
            case "com.apple.Safari":
                script = "tell application \"Safari\" to get {URL, name} of current tab of front window"
            case "com.google.Chrome":
                script = "tell application \"Google Chrome\" to get {URL, title} of active tab of front window"
            case "com.microsoft.edgemac":
                script = "tell application \"Microsoft Edge\" to get {URL, title} of active tab of front window"
            case "company.thebrowser.Browser":
                script = "tell application \"Arc\" to get {URL, title} of active tab of front window"
            default:
                return
            }

            ReadLaterManager.shared.runAppleScriptViaOSA(script: script) { result in
                if let result = result {
                    ReadLaterManager.shared.add(url: result.url, title: result.title)
                    let content = UNMutableNotificationContent()
                    content.title = L("readlater.saved")
                    content.body = result.title
                    content.sound = .default
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                } else {
                    if let error = ReadLaterManager.shared.lastError, error.contains("Not authorized") {
                        let content = UNMutableNotificationContent()
                        content.title = L("readlater.error.title")
                        content.body = L("automation.permission.retryHint")
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                        UNUserNotificationCenter.current().add(request)
                    }
                    if LogSettings.shared.readlaterLogEnabled {
                        LogSettings.write("[ReadLater] osascript failed: \(ReadLaterManager.shared.lastError ?? "no error")", to: LogSettings.shared.readlaterLogPath)
                    }
                }
            }
        } else if response == .alertSecondButtonReturn {
            // Adjust permissions: open System Settings
            PermissionManager.shared.openAutomationSettings()
        }
    }

    func showLauncher() {
        launcherWindow?.show()
    }
    
    func hideLauncher() {
        launcherWindow?.hide()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.selectTab(withIdentifier: "general")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showIndexLimitWarning(count: Int) {
        let alert = NSAlert()
        alert.messageText = L("alert.indexLimit.title")
        alert.informativeText = String(format: L("alert.indexLimit.message"), count, 100000)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("alert.ok"))
        alert.runModal()
    }

    func showClipboardSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.selectTab(withIdentifier: "clipboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupIndex() {
        // Check if Spotlight is enabled
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let enabled = SpotlightService.isSpotlightEnabled()
            DispatchQueue.main.async {
                self?.isIndexReady = enabled
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
        ClipboardManager.shared.stop()
    }
    
    // MARK: - Running App Monitoring
    
    private var runningAppTimer: Timer?
    
    private func startRunningAppMonitoring() {
        // Check running apps every hour
        runningAppTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.recordRunningApps()
        }
        
        // Also check immediately on launch
        recordRunningApps()
    }
    
    private func recordRunningApps() {
        let workspace = NSWorkspace.shared
        let fileManager = FileManager.default

        for app in workspace.runningApplications {
            // Skip our own app only
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }

            // Only record apps that appear in UI (not background daemons)
            guard app.activationPolicy == .regular else { continue }

            // Record the app path to boost its frequency
            if let url = app.bundleURL {
                var pathsToRecord: [String] = []
                pathsToRecord.append(url.path)

                // Also record common symlink locations
                let appName = url.lastPathComponent

                // Check /Applications
                let appPath = "/Applications/\(appName)"
                if fileManager.fileExists(atPath: appPath) {
                    pathsToRecord.append(appPath)
                }

                // Check ~/Applications
                let homeAppPath = NSHomeDirectory() + "/Applications/\(appName)"
                if fileManager.fileExists(atPath: homeAppPath) {
                    pathsToRecord.append(homeAppPath)
                }

                // Check /System/Applications
                let systemAppPath = "/System/Applications/\(appName)"
                if fileManager.fileExists(atPath: systemAppPath) {
                    pathsToRecord.append(systemAppPath)
                }

                // Record all possible paths
                for path in pathsToRecord {
                    LaunchHistory.shared.record(identifier: path)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If hide() was just called from global monitor (clicking our Dock icon),
        // don't re-open the window
        if launcherWindow?.isHandlingDockClick == true {
            return false
        }
        
        if launcherWindow?.isVisible == true {
            launcherWindow?.hide()
        } else {
            launcherWindow?.show()
        }
        return false  // We handled it, don't let system do anything else
    }
}
