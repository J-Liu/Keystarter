// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// A plugin responds to a trigger keyword and returns results for the launcher.
protocol Plugin {
    /// The trigger keyword, e.g. "dict", "tr". Empty string for direct-match plugins.
    var keyword: String { get }

    /// Human-readable description shown in help / settings.
    var pluginDescription: String { get }

    /// Given the query after the keyword, return a list of results.
    func query(_ input: String) -> [PluginResult]

    /// Check if this plugin should handle the input directly (without keyword).
    func matchesDirect(_ input: String) -> Bool

    /// Handle direct input (without keyword).
    func queryDirect(_ input: String) -> [PluginResult]
}

extension Plugin {
    func matchesDirect(_ input: String) -> Bool { return false }
    func queryDirect(_ input: String) -> [PluginResult] { return [] }
}

/// A single result produced by a plugin.
struct PluginResult {
    let title: String
    let subtitle: String?
    let icon: NSImage?
    /// Full detail text shown in preview panel.
    let detailText: String?
    /// Called when the user presses Enter.
    let action: () -> Void

    init(title: String,
         subtitle: String? = nil,
         icon: NSImage? = nil,
         detailText: String? = nil,
         action: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.detailText = detailText
        self.action = action
    }
}
