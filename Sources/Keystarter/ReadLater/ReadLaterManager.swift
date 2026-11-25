// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

/// Represents a saved URL item.
struct ReadLaterItem: Codable {
    let url: String
    let title: String
    let createdAt: Date
}

/// Manages the list of saved URLs.
final class ReadLaterManager {
    static let shared = ReadLaterManager()

    private let storageKey = "readLater.items"
    private var items: [ReadLaterItem] = []
    private(set) var lastError: String?

    private init() {
        load()
    }

    private func log(_ message: String) {
        guard LogSettings.shared.readlaterLogEnabled else { return }
        LogSettings.write("[ReadLater] \(message)", to: LogSettings.shared.readlaterLogPath)
    }

    /// Load items from storage.
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ReadLaterItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    /// Save items to storage.
    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Get all items (most recent first).
    func getAll() -> [ReadLaterItem] {
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    /// Add a new item.
    func add(url: String, title: String) {
        let item = ReadLaterItem(url: url, title: title, createdAt: Date())
        items.append(item)
        save()
    }

    /// Remove an item by URL.
    func remove(url: String) {
        items.removeAll { $0.url == url }
        save()
    }

    /// Remove an item by index.
    func remove(at index: Int) {
        let sorted = getAll()
        guard index >= 0 && index < sorted.count else { return }
        let item = sorted[index]
        items.removeAll { $0.url == item.url }
        save()
    }

    /// Get current browser URL via AppleScript or Accessibility API.
    func getCurrentBrowserURL() -> (url: String, title: String)? {
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            log("No frontmost application")
            return nil
        }
        let bundleId = frontmostApp.bundleIdentifier ?? ""
        log("Frontmost app: \(bundleId)")

        // Only try the browser that is currently frontmost
        switch bundleId {
        case "com.apple.Safari":
            return getSafariURL()
        case "com.google.Chrome":
            return getChromeURL()
        case "com.microsoft.edgemac":
            return getEdgeURL()
        case "org.mozilla.firefox":
            return getFirefoxURL()
        case "company.thebrowser.Browser":
            return getArcURL()
        default:
            log("Not a supported browser: \(bundleId)")
            return nil
        }
    }

    private func getSafariURL() -> (url: String, title: String)? {
        // Check if Safari is running
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first != nil else {
            return nil
        }
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                set currentTab to current tab of front window
                return {URL of currentTab, name of currentTab}
            end if
        end tell
        """
        return runAppleScript(script)
    }

    private func getChromeURL() -> (url: String, title: String)? {
        // Check if Chrome is running
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first != nil else {
            return nil
        }
        let script = """
        tell application "Google Chrome"
            if (count of windows) > 0 then
                set currentTab to active tab of front window
                return {URL of currentTab, title of currentTab}
            end if
        end tell
        """
        return runAppleScript(script)
    }

    private func getEdgeURL() -> (url: String, title: String)? {
        // Check if Edge is running
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.edgemac").first != nil else {
            return nil
        }
        let script = """
        tell application "Microsoft Edge"
            if (count of windows) > 0 then
                set currentTab to active tab of front window
                return {URL of currentTab, title of currentTab}
            end if
        end tell
        """
        return runAppleScript(script)
    }

    private func getArcURL() -> (url: String, title: String)? {
        // Check if Arc is running
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "company.thebrowser.Browser").first != nil else {
            return nil
        }
        let script = """
        tell application "Arc"
            if (count of windows) > 0 then
                set currentTab to active tab of front window
                return {URL of currentTab, title of currentTab}
            end if
        end tell
        """
        return runAppleScript(script)
    }

    private func getFirefoxURL() -> (url: String, title: String)? {
        // Firefox doesn't support AppleScript for tabs
        // Use Accessibility API to get URL from address bar
        let firefoxBundleId = "org.mozilla.firefox"

        // Find Firefox app
        guard let firefoxApp = NSRunningApplication.runningApplications(withBundleIdentifier: firefoxBundleId).first else {
            return nil
        }

        // Get the frontmost Firefox window using Accessibility API
        let pid = firefoxApp.processIdentifier
        let app = AXUIElementCreateApplication(pid)

        // Get windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first else {
            return nil
        }

        // Find the URL bar (search for a text field with URL)
        var url: String?
        var title: String?

        // Get window title
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success {
            title = (titleRef as? String)?.trimmingCharacters(in: .whitespaces)
        }

        // Search for URL text field in the window
        func findURLField(element: AXUIElement) {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            // Check if this is a text field that might be the URL bar
            if role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole {
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
                    let value = valueRef as? String ?? ""
                    // Check if value looks like a URL
                    if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("moz-extension://") {
                        if url == nil || (value.hasPrefix("http") && !value.contains("moz-extension")) {
                            url = value
                        }
                    }
                }
            }

            // Recursively search children
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    findURLField(element: child)
                }
            }
        }

        findURLField(element: window)

        if let url = url, !url.isEmpty {
            // Filter out internal Firefox URLs
            if url.hasPrefix("moz-extension://") || url.hasPrefix("about:") {
                return nil
            }
            return (url, title ?? url)
        }

        return nil
    }

    private func runAppleScript(_ script: String) -> (url: String, title: String)? {
        lastError = nil
        var errorInfo: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        if let result = appleScript?.executeAndReturnError(&errorInfo) {
            // Result is a list: {URL, title}
            let list = result.coerce(toDescriptorType: typeAEList)
            if let urlDesc = list?.atIndex(1),
               let titleDesc = list?.atIndex(2) {
                let url = urlDesc.stringValue ?? ""
                let title = titleDesc.stringValue ?? ""
                if !url.isEmpty {
                    log("Got URL: \(url) title: \(title)")
                    return (url, title.isEmpty ? url : title)
                }
            }
        } else if let error = errorInfo {
            // Log error for debugging
            if let errorMsg = error[NSAppleScript.errorMessage] as? String {
                log("AppleScript error: \(errorMsg)")
                lastError = errorMsg
            }
        }
        return nil
    }

    /// Open URL in default browser.
    func openURL(_ url: String) {
        if let urlObj = URL(string: url) {
            NSWorkspace.shared.open(urlObj)
        }
    }
}