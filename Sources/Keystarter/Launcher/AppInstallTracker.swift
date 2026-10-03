// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Tracks app installation times for "newly installed" ranking.
final class AppInstallTracker {

    static let shared = AppInstallTracker()

    private let key = "app.installTimes"
    private var installTimes: [String: Date] = [:]
    private let lock = NSLock()

    /// Apps installed within this many days are considered "new".
    let newAppDays: Double = 7.0

    init() {
        load()
    }

    // MARK: - Public API

    /// Check if app is newly installed (within last 7 days).
    func isNewlyInstalled(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let installDate = installTimes[path] else {
            // No record = treat as new (newly discovered)
            return true
        }

        let daysSinceInstall = Date().timeIntervalSince(installDate) / 86400
        return daysSinceInstall < newAppDays
    }

    /// Get days since installation (for sorting).
    func daysSinceInstall(path: String) -> Double {
        lock.lock()
        defer { lock.unlock() }

        guard let installDate = installTimes[path] else {
            return 0 // Unknown = treat as new
        }
        return Date().timeIntervalSince(installDate) / 86400
    }

    /// Record installation time for an app (if not already recorded).
    func recordInstall(path: String) {
        lock.lock()
        defer { lock.unlock() }

        // Only record if not already present
        if installTimes[path] == nil {
            installTimes[path] = Date()
            save()
        }
    }

    /// Remove installation record (app was uninstalled).
    func removeInstall(path: String) {
        lock.lock()
        defer { lock.unlock() }

        if installTimes.removeValue(forKey: path) != nil {
            save()
        }
    }

    /// Update installation records for current app set.
    /// Returns list of newly discovered apps.
    func syncWithApps(paths: [String]) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var newApps: [String] = []
        var changed = false

        // Record new apps
        for path in paths {
            if installTimes[path] == nil {
                installTimes[path] = Date()
                newApps.append(path)
                changed = true
            }
        }

        // Remove uninstalled apps
        let pathSet = Set(paths)
        let removedPaths = installTimes.keys.filter { !pathSet.contains($0) }
        for path in removedPaths {
            installTimes.removeValue(forKey: path)
            changed = true
        }

        if changed {
            save()
        }

        return newApps
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            installTimes = [:]
            return
        }
        installTimes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(installTimes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
