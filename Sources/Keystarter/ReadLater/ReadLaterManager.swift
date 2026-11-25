// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

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

    private init() {
        load()
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

    /// Get current browser URL via AppleScript.
    func getCurrentBrowserURL() -> (url: String, title: String)? {
        // Try Safari first
        if let result = getSafariURL() {
            return result
        }
        // Try Chrome
        if let result = getChromeURL() {
            return result
        }
        // Try Edge
        if let result = getEdgeURL() {
            return result
        }
        // Try Firefox
        if let result = getFirefoxURL() {
            return result
        }
        return nil
    }

    private func getSafariURL() -> (url: String, title: String)? {
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

    private func getFirefoxURL() -> (url: String, title: String)? {
        // Firefox doesn't support AppleScript for tabs
        // We can try using Accessibility API, but it's complex
        // For now, return nil
        return nil
    }

    private func runAppleScript(_ script: String) -> (url: String, title: String)? {
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
                    return (url, title.isEmpty ? url : title)
                }
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