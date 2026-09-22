// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var launcherWindow: LauncherWindow?
    private var hotkeyManager: HotkeyManager?
    private var statusBarController: StatusBarController?
    private var settingsWindow: SettingsWindow?
    var indexDB: IndexDatabase?
    private var indexScanner: IndexScanner?
    private var indexWatcher: IndexWatcher?
    var isIndexReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupStatusBar()
        setupIndex()

        // Create the launcher window (hidden initially)
        launcherWindow = LauncherWindow()

        // Register global hotkey with saved or default settings
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkey.keyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkey.modifiers")
        let keyCode = savedKeyCode > 0 ? UInt32(savedKeyCode) : UInt32(kVK_Space)
        let modifiers = savedModifiers > 0 ? UInt32(savedModifiers) : UInt32(cmdKey)

        hotkeyManager = HotkeyManager { [weak self] in
            self?.launcherWindow?.toggle()
        }
        hotkeyManager?.register(keyCode: keyCode, modifiers: modifiers)

        PluginManager.shared.register(DictionaryPlugin())
        PluginManager.shared.register(TranslatePlugin())

        // Load Alfred workflows
        AlfredWorkflowManager.shared.loadAll()

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
                self?.updateHotkey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
            }
        }
        wizard.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Update the global hotkey.
    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        hotkeyManager?.unregister()
        hotkeyManager?.register(keyCode: keyCode, modifiers: modifiers)
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkey.keyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotkey.modifiers")
    }

    /// Update the status bar icon theme.
    func updateStatusBarTheme(_ theme: String) {
        statusBarController?.updateTheme(theme)
    }

    /// Minimal menu so Cmd+Q works and the app behaves like a normal macOS app.
    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Keystarter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
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
        hotkeyManager?.unregister()
    }
}
