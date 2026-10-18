// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Manages the list of hidden apps that should not appear in launcher grid (but searchable).
final class HiddenAppsManager {

    static let shared = HiddenAppsManager()

    private let storageKey = "launcher.hiddenApps"
    private var hiddenApps: Set<String> = []

    private init() {
        load()
    }

    private func load() {
        if let saved = UserDefaults.standard.array(forKey: storageKey) as? [String] {
            hiddenApps = Set(saved)
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(hiddenApps), forKey: storageKey)
    }

    /// Check if an app is hidden.
    func isHidden(path: String) -> Bool {
        return hiddenApps.contains(path)
    }

    /// Add an app to the hidden list.
    func hide(path: String) {
        hiddenApps.insert(path)
        save()
    }

    /// Remove an app from the hidden list.
    func unhide(path: String) {
        hiddenApps.remove(path)
        save()
    }

    /// Get all hidden app paths.
    func getAllHidden() -> [String] {
        return Array(hiddenApps).sorted()
    }

    /// Get app name from path.
    func appName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingPathExtension().lastPathComponent
    }
}
