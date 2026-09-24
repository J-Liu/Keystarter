// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Manages the list of ignored apps that should not appear in launcher.
final class IgnoredAppsManager {

    static let shared = IgnoredAppsManager()

    private let storageKey = "launcher.ignoredApps"
    private var ignoredApps: Set<String> = []

    private init() {
        load()
    }

    private func load() {
        if let saved = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            ignoredApps = Set(saved)
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(ignoredApps), forKey: storageKey)
    }

    /// Check if an app is ignored.
    func isIgnored(path: String) -> Bool {
        return ignoredApps.contains(path)
    }

    /// Add an app to the ignored list.
    func ignore(path: String) {
        ignoredApps.insert(path)
        save()
    }

    /// Remove an app from the ignored list.
    func unignore(path: String) {
        ignoredApps.remove(path)
        save()
    }

    /// Get all ignored app paths.
    func getAllIgnored() -> [String] {
        return Array(ignoredApps).sorted()
    }

    /// Get app name from path.
    func appName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingPathExtension().lastPathComponent
    }
}
