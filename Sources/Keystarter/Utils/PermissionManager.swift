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

    /// Open System Settings > Privacy & Security > Automation.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reset AppleEvents permission using tccutil.
    func resetAppleEventsPermission(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            // Only reset for this app, not all apps
            process.arguments = ["reset", "AppleEvents", "com.jialiu.keystarter"]

            var success = false
            do {
                try process.run()
                process.waitUntilExit()
                success = process.terminationStatus == 0
            } catch {
                // Ignore error
            }

            DispatchQueue.main.async {
                // Log result
                if LogSettings.shared.readlaterLogEnabled {
                    LogSettings.write("[ReadLater] tccutil reset result: \(success)", to: LogSettings.shared.readlaterLogPath)
                }
                completion()
            }
        }
    }

    /// Request automation permission for a browser.
    /// This will trigger the system authorization dialog.
    func requestAutomationPermission(for bundleId: String, completion: @escaping (Bool) -> Void) {
        guard let targetApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            completion(false)
            return
        }

        // Get the app name for AppleScript
        let appName = targetApp.deletingPathExtension().lastPathComponent

        // Execute AppleScript to trigger permission request
        let script = "tell application \"\(appName)\" to get name"
        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&errorInfo)

        if result != nil {
            completion(true)
        } else if let error = errorInfo, let errorMsg = error[NSAppleScript.errorMessage] as? String {
            if errorMsg.contains("Not authorized") {
                completion(false)
            } else {
                completion(false)
            }
        } else {
            completion(false)
        }
    }

    /// Check if we have automation permission for a browser by trying a simple AppleScript.
    /// Returns nil if permission is granted, or the error message if denied.
    func checkBrowserAutomationPermission() -> String? {
        // Try a simple AppleScript to check if we have permission
        let script = "tell application \"Safari\" to get name"
        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        _ = appleScript?.executeAndReturnError(&errorInfo)

        if let error = errorInfo, let errorMsg = error[NSAppleScript.errorMessage] as? String {
            if errorMsg.contains("Not authorized") {
                return errorMsg
            }
        }
        return nil
    }

    /// List of supported browsers for automation.
    static let supportedBrowsers = [
        (name: "Safari", bundleId: "com.apple.Safari"),
        (name: "Google Chrome", bundleId: "com.google.Chrome"),
        (name: "Microsoft Edge", bundleId: "com.microsoft.edgemac"),
        (name: "Arc", bundleId: "company.thebrowser.Browser")
    ]

    /// Check automation permission status for each supported browser.
    /// Only checks browsers that are currently running.
    func checkAllBrowserAutomationPermissions() -> [(name: String, hasPermission: Bool)] {
        var results: [(name: String, hasPermission: Bool)] = []

        for browser in PermissionManager.supportedBrowsers {
            // Only check if browser is running
            let isRunning = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleId).first != nil
            if isRunning {
                let hasPermission = checkAutomationPermission(for: browser.name)
                results.append((name: browser.name, hasPermission: hasPermission))
            }
        }

        return results
    }

    /// Check automation permission for a specific browser.
    /// Returns true only if the AppleScript executed successfully without authorization error.
    private func checkAutomationPermission(for browserName: String) -> Bool {
        let script = "tell application \"\(browserName)\" to get name"
        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&errorInfo)

        // Only return true if we got a valid result (app name) and no error
        if let result = result, result.stringValue != nil, errorInfo == nil {
            return true
        }

        // Check for authorization error
        if let error = errorInfo, let errorMsg = error[NSAppleScript.errorMessage] as? String {
            if errorMsg.contains("Not authorized") {
                return false
            }
        }

        // Any other error (app not running, etc.) - permission status unknown
        return false
    }
}