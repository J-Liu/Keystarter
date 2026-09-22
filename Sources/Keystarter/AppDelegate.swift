// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var launcherWindow: LauncherWindow?
    private var hotkeyManager: HotkeyManager?
    var indexDB: IndexDatabase?
    private var indexScanner: IndexScanner?
    private var indexWatcher: IndexWatcher?
    var isIndexReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupIndex()

        // Create the launcher window (hidden initially)
        launcherWindow = LauncherWindow()

        // Register global hotkey: Cmd + Space
        hotkeyManager = HotkeyManager { [weak self] in
            self?.launcherWindow?.toggle()
        }
        hotkeyManager?.register()

        PluginManager.shared.register(DictionaryPlugin())
        PluginManager.shared.register(TranslatePlugin())

        // Load Alfred workflows
        AlfredWorkflowManager.shared.loadAll()
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
