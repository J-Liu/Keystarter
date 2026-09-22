// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

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
            self?.requestClipboardPermission {
                self?.requestFileAccessPermission {
                    completion()
                }
            }
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
        You may need to restart Keystarter after granting.
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

    /// Request Clipboard permission (for paste functionality).
    private func requestClipboardPermission(completion: @escaping () -> Void) {
        // On macOS 13+, clipboard access may require permission
        // We'll request it by trying to access
        let pasteboard = NSPasteboard.general
        _ = pasteboard.string(forType: .string)

        // Check if we need to request
        if #available(macOS 14.0, *) {
            // Clipboard permission is handled by the system
            completion()
        } else {
            completion()
        }
    }

    /// Request File Access permission (for file search).
    private func requestFileAccessPermission(completion: @escaping () -> Void) {
        // Try to access a common directory
        let testPath = NSHomeDirectory() + "/Documents"
        if FileManager.default.isReadableFile(atPath: testPath) {
            completion()
            return
        }

        let alert = NSAlert()
        alert.messageText = "File Access Permission Required"
        alert.informativeText = """
        Keystarter needs Full Disk Access to:
        
        • Search files in Documents, Desktop, Downloads
        • Open files and applications
        
        Click "Open System Settings" to grant permission.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Skip")

        if alert.runModal() == .alertFirstButtonReturn {
            openFullDiskAccessSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                completion()
            }
        } else {
            completion()
        }
    }

    /// Open System Settings > Privacy & Security > Accessibility.
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings > Privacy & Security > Full Disk Access.
    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}