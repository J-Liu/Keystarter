// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon
import ServiceManagement

/// Manages permission requests with clear explanations.
final class PermissionManager {

    static let shared = PermissionManager()

    private init() {}

    /// Check if this is the first launch.
    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }

    /// Mark first launch as complete.
    func markLaunched() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }

    /// Request all necessary permissions with explanations.
    func requestAllPermissions(completion: @escaping () -> Void) {
        requestAccessibilityPermission { [weak self] in
            // After accessibility permission, enable login item and restart
            self?.setLoginItem(enabled: true)
            self?.restartApp()
        }
    }

    /// Request Accessibility permission (for global hotkey).
    private func requestAccessibilityPermission(completion: @escaping () -> Void) {
        let trusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
        ] as CFDictionary)

        if trusted {
            completion()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Keystarter needs Accessibility permission to:
        
        • Listen for the global hotkey (⌘ Space)
        • Capture keyboard shortcuts for navigation
        
        Click "Open System Settings" to grant permission.
        After granting, the app will restart automatically.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Skip")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
            // Wait a bit for user to grant permission
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                completion()
            }
        } else {
            completion()
        }
    }

    /// Enable or disable login item (start at login).
    func setLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
            }
        } else {
            // For older macOS versions
            let bundleID = Bundle.main.bundleIdentifier! as CFString
            SMLoginItemSetEnabled(bundleID, enabled)
        }
        UserDefaults.standard.set(enabled, forKey: "startAtLogin")
    }

    /// Restart the application.
    private func restartApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Open System Settings > Privacy & Security > Accessibility.
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}