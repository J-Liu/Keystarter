// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var launcherWindow: LauncherWindow?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the launcher window (hidden initially)
        launcherWindow = LauncherWindow()

        // Register global hotkey: Cmd + Space
        hotkeyManager = HotkeyManager { [weak self] in
            self?.launcherWindow?.toggle()
        }
        hotkeyManager?.register()

        PluginManager.shared.register(DictionaryPlugin())
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
    }
}
