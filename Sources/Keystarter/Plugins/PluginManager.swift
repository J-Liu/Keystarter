// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Owns all registered plugins and dispatches queries to them.
final class PluginManager {

    static let shared = PluginManager()

    private var plugins: [Plugin] = []

    private init() {}

    /// Register a plugin. Call this at app launch.
    func register(_ plugin: Plugin) {
        plugins.append(plugin)
    }

    /// Try to match the input against a plugin keyword.
    /// Returns nil if no plugin matches.
    func dispatch(_ input: String) -> [PluginResult]? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Split into keyword + rest
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let keyword = String(first).lowercased()
        let rest = parts.count > 1 ? String(parts[1]) : ""

        guard let plugin = plugins.first(where: { $0.keyword == keyword }) else {
            return nil
        }
        return plugin.query(rest)
    }
}
