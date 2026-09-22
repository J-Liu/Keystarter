// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var launcherWindow: LauncherWindow?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        // Create the launcher window (hidden initially)
        launcherWindow = LauncherWindow()

        // Register global hotkey: Cmd + Space
        hotkeyManager = HotkeyManager { [weak self] in
            self?.launcherWindow?.toggle()
        }
        hotkeyManager?.register()

        PluginManager.shared.register(DictionaryPlugin())
        PluginManager.shared.register(TranslatePlugin())
    }

    /// Minimal menu so Cmd+Q works and the app behaves like a normal macOS app.
    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        appMenu.addItem(
            withTitle: "Quit Keystarter",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
    }
}
