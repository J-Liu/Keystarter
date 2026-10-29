// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Manages the list of hidden apps that should not appear in launcher grid (but searchable).
final class HiddenAppsManager {

    static let shared = HiddenAppsManager()

    private let storagePath: String
    private var hiddenApps: Set<String> = []

    private init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        storagePath = dir + "/hidden_apps.plist"
        
        // Migrate from UserDefaults (run once, then clear old data)
        migrateFromUserDefaults()
        load()
    }

    private func migrateFromUserDefaults() {
        let oldKey = "launcher.hiddenApps"
        if let oldData = UserDefaults.standard.array(forKey: oldKey) as? [String] {
            // Save to new location
            let data = try? PropertyListSerialization.data(fromPropertyList: oldData, format: .xml, options: 0)
            try? data?.write(to: URL(fileURLWithPath: storagePath))
            // Clear old UserDefaults
            UserDefaults.standard.removeObject(forKey: oldKey)
        }
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: storagePath) else { return }
        if let saved = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
            hiddenApps = Set(saved)
        }
    }

    private func save() {
        let data = try? PropertyListSerialization.data(fromPropertyList: Array(hiddenApps).sorted(), format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: storagePath))
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
