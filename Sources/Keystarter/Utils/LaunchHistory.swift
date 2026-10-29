// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Tracks launch frequency and recency for items to improve ranking.
final class LaunchHistory {

    static let shared = LaunchHistory()

    private let historyPath: String
    private let cleanupKey = "keystarter.lastHistoryCleanup"
    private var entries: [String: LaunchEntry] = [:]
    private let lock = NSLock()

    private struct LaunchEntry {
        var count: Int
        var lastLaunched: Date
        var manualScore: Int?  // User-defined score override
    }

    private init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        historyPath = dir + "/history.plist"
        load()

        // Run cleanup once per day
        let lastCleanup = UserDefaults.standard.object(forKey: cleanupKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(lastCleanup) > 86400 {  // 24 hours
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.cleanupDeletedApps()
            }
            UserDefaults.standard.set(Date(), forKey: cleanupKey)
        }
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: historyPath) else { return }
        if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            for (key, value) in dict {
                if let entryDict = value as? [String: Any],
                   let count = entryDict["count"] as? Int,
                   let lastLaunched = entryDict["lastLaunched"] as? Date {
                    let manualScore = entryDict["manualScore"] as? Int
                    entries[key] = LaunchEntry(count: count, lastLaunched: lastLaunched, manualScore: manualScore)
                } else if let count = value as? Int {
                    // Legacy format: just count
                    entries[key] = LaunchEntry(count: count, lastLaunched: Date(), manualScore: nil)
                }
            }
        }
    }

    private func save() {
        var dict: [String: Any] = [:]
        for (key, entry) in entries {
            var entryDict: [String: Any] = ["count": entry.count, "lastLaunched": entry.lastLaunched]
            if let manualScore = entry.manualScore {
                entryDict["manualScore"] = manualScore
            }
            dict[key] = entryDict
        }
        let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: historyPath))
    }

    /// Record a launch for the given identifier (path or name).
    func record(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[identifier] {
            // Don't modify count if user has set a manual score
            if entry.manualScore == nil {
                entry.count += 1
            }
            entry.lastLaunched = Date()
            entries[identifier] = entry
        } else {
            entries[identifier] = LaunchEntry(count: 1, lastLaunched: Date(), manualScore: nil)
        }
        save()
    }

    /// Get the launch count for an identifier.
    func count(for identifier: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries[identifier]?.count ?? 0
    }

    /// Get the manual score for an identifier (if user has set one).
    func manualScore(for identifier: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return entries[identifier]?.manualScore
    }

    /// Set a manual score for an identifier. Use nil to clear.
    func setManualScore(for identifier: String, score: Int?) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[identifier] {
            entry.manualScore = score
            entries[identifier] = entry
        } else {
            entries[identifier] = LaunchEntry(count: 0, lastLaunched: Date(), manualScore: score)
        }
        save()
    }

    /// Get the effective score for an identifier (manual or calculated).
    func effectiveScore(for identifier: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[identifier] else { return 0 }
        if let manual = entry.manualScore {
            return manual
        }
        // Calculated score: count * 10 + recency bonus
        let daysSinceLaunch = Date().timeIntervalSince(entry.lastLaunched) / 86400
        return entry.count * 10 + Int(100 / (1 + daysSinceLaunch))
    }

    /// Get the last launched date for an identifier.
    func lastLaunched(for identifier: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return entries[identifier]?.lastLaunched
    }

    /// Get all identifiers sorted by frequency.
    func topIdentifiers(limit: Int = 10) -> [(String, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.value.count > $1.value.count }
            .prefix(limit)
            .map { ($0.key, $0.value.count) }
    }

    /// Get all identifiers sorted by a combined score (frequency + recency).
    func topIdentifiersByScore(limit: Int = 100) -> [(String, Int, Date)] {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        return entries.map { (key, entry) in
            let daysSinceLaunch = now.timeIntervalSince(entry.lastLaunched) / 86400
            let score = Double(entry.count) * 10 + 100 / (1 + daysSinceLaunch)
            return (key, entry.count, entry.lastLaunched, score)
        }.sorted { $0.3 > $1.3 }
         .prefix(limit)
         .map { ($0.0, $0.1, $0.2) }
    }

    /// Remove entries for apps that no longer exist on disk.
    /// Returns the number of entries removed.
    @discardableResult
    func cleanupDeletedApps() -> Int {
        lock.lock()
        defer { lock.unlock() }

        var removed = 0
        for (path, _) in entries {
            // Check if the path still exists
            if !FileManager.default.fileExists(atPath: path) {
                entries.removeValue(forKey: path)
                removed += 1
            }
        }

        if removed > 0 {
            save()
        }
        return removed
    }
}
