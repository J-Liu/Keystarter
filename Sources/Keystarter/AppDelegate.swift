// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var launcherWindow: LauncherWindow?
    private var clipboardPanel: ClipboardPanel?
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindow?
    var indexDB: IndexDatabase?
    private var indexScanner: IndexScanner?
    private var indexWatcher: IndexWatcher?
    var isIndexReady = false

    // Hotkey key codes for tracking
    private var launcherKeyCode: UInt16 = 49
    private var launcherModifiers: NSEvent.ModifierFlags = .command
    private var clipboardKeyCode: UInt16 = 9
    private var clipboardModifiers: NSEvent.ModifierFlags = [.command, .shift]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupStatusBar()
        setupIndex()
        updateDockIconVisibility()

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

        // Load Alfred workflows
        AlfredWorkflowManager.shared.loadAll()

        // Start clipboard manager (has its own database)
        ClipboardManager.shared.start()

        // Start update manager
        UpdateManager.shared.startUpdater()

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
            self?.clipboardPanel?.toggle()
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
            self?.clipboardPanel?.toggle()
        }
        UserDefaults.standard.set(Int(keyCode), forKey: "clipboard.hotkey.keyCode")
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "clipboard.hotkey.modifiers")
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
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.selectTab(withIdentifier: "about")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func checkPermissionsFromMenu() {
        PermissionManager.shared.requestAllPermissions {
            // Permissions granted
        }
    }

    @objc private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController()
    }

    func showLauncher() {
        launcherWindow?.show()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showClipboardSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.selectTab(withIdentifier: "clipboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    func rebuildIndex() {
        guard let db = indexDB else { return }
        indexWatcher?.stop()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scanner = IndexScanner(db: db)
            let roots = [
                NSHomeDirectory() + "/Documents",
                NSHomeDirectory() + "/Desktop",
                NSHomeDirectory() + "/Downloads"
            ]
            print("[Index] Rebuilding...")
            scanner.scan(roots: roots)
            print("[Index] Rebuild complete.")

            DispatchQueue.main.async {
                self?.indexWatcher?.start(roots: roots)
            }
        }
    }

    private func setupIndex() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let db = IndexDatabase()
            guard db.open() else { return }

            DispatchQueue.main.async {
                self?.indexDB = db
            }

            let scanner = IndexScanner(db: db)
            let roots = [
                NSHomeDirectory() + "/Documents",
                NSHomeDirectory() + "/Desktop",
                NSHomeDirectory() + "/Downloads"
            ]
            print("[Index] Starting scan...")
            scanner.scan(roots: roots)
            print("[Index] Scan complete.")

            // Start watching for changes
            let watcher = IndexWatcher(db: db)
            watcher.start(roots: roots)
            DispatchQueue.main.async {
                self?.indexWatcher = watcher
            }

            DispatchQueue.main.async {
                self?.isIndexReady = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
        ClipboardManager.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // Window is visible, hide it
            launcherWindow?.hide()
        } else {
            // Window is hidden, show it
            launcherWindow?.show()
        }
        return true
    }
}
