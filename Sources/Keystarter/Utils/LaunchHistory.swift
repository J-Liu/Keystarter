// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Tracks launch frequency and recency for items to improve ranking.
final class LaunchHistory {

    static let shared = LaunchHistory()

    private let historyPath: String
    private var entries: [String: LaunchEntry] = [:]
    private let lock = NSLock()

    private struct LaunchEntry {
        var count: Int
        var lastLaunched: Date
    }

    private init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        historyPath = dir + "/history.plist"
        load()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: historyPath) else { return }
        if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            for (key, value) in dict {
                if let entryDict = value as? [String: Any],
                   let count = entryDict["count"] as? Int,
                   let lastLaunched = entryDict["lastLaunched"] as? Date {
                    entries[key] = LaunchEntry(count: count, lastLaunched: lastLaunched)
                } else if let count = value as? Int {
                    // Legacy format: just count
                    entries[key] = LaunchEntry(count: count, lastLaunched: Date())
                }
            }
        }
    }

    private func save() {
        var dict: [String: Any] = [:]
        for (key, entry) in entries {
            dict[key] = ["count": entry.count, "lastLaunched": entry.lastLaunched]
        }
        let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: historyPath))
    }

    /// Record a launch for the given identifier (path or name).
    func record(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        if var entry = entries[identifier] {
            entry.count += 1
            entry.lastLaunched = Date()
            entries[identifier] = entry
        } else {
            entries[identifier] = LaunchEntry(count: 1, lastLaunched: Date())
        }
        save()
    }

    /// Get the launch count for an identifier.
    func count(for identifier: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries[identifier]?.count ?? 0
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
}
