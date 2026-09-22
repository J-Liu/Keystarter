// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Tracks launch frequency for items to improve ranking.
final class LaunchHistory {

    static let shared = LaunchHistory()

    private let historyPath: String
    private var counts: [String: Int] = [:]
    private let lock = NSLock()

    private init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        historyPath = dir + "/history.plist"
        load()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: historyPath) else { return }
        counts = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Int]) ?? [:]
    }

    private func save() {
        let data = try? PropertyListSerialization.data(fromPropertyList: counts, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: historyPath))
    }

    /// Record a launch for the given identifier (path or name).
    func record(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[identifier, default: 0] += 1
        save()
    }

    /// Get the launch count for an identifier.
    func count(for identifier: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[identifier] ?? 0
    }

    /// Get all identifiers sorted by frequency.
    func topIdentifiers(limit: Int = 10) -> [(String, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }
}