// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// A plugin responds to a trigger keyword and returns results for the launcher.
protocol Plugin {
    /// The trigger keyword, e.g. "dict", "tr".
    var keyword: String { get }

    /// Human-readable description shown in help / settings.
    var pluginDescription: String { get }

    /// Given the query after the keyword, return a list of results.
    func query(_ input: String) -> [PluginResult]
}

/// A single result produced by a plugin.
struct PluginResult {
    let title: String
    let subtitle: String?
    let icon: NSImage?
    /// Called when the user presses Enter.
    let action: () -> Void

    init(title: String,
         subtitle: String? = nil,
         icon: NSImage? = nil,
         action: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }
}
