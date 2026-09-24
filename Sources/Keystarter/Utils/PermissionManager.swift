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
            // After accessibility permission, enable login item
            self?.setLoginItem(enabled: true)
            completion()
        }
    }

    /// Request Accessibility permission (for global hotkey).
    private func requestAccessibilityPermission(completion: @escaping () -> Void) {
        // Directly trigger system permission dialog
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
        ] as CFDictionary)

        completion()
    }

    /// Check if Accessibility permission is granted.
    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): false
        ] as CFDictionary)
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

    /// Open System Settings > Privacy & Security > Accessibility.
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}