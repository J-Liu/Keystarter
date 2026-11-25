// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Plugin to display and manage saved URLs.
/// Usage: "rl" or "readlater" shows all saved items.
final class ReadLaterPlugin: Plugin {

    let keyword = "rl"
    let pluginDescription = "View and open saved URLs (稍后再看)"

    init() {}

    func query(_ input: String) -> [PluginResult] {
        let items = ReadLaterManager.shared.getAll()

        if items.isEmpty {
            return [PluginResult(
                title: "No saved URLs",
                subtitle: "Press Cmd+Shift+S to save current browser tab",
                icon: NSImage(systemSymbolName: "bookmark.slash", accessibilityDescription: nil)
            )]
        }

        // Filter by input if provided
        let filtered = input.isEmpty ? items : items.filter { item in
            item.title.localizedCaseInsensitiveContains(input) ||
            item.url.localizedCaseInsensitiveContains(input)
        }

        return filtered.enumerated().map { index, item in
            PluginResult(
                title: item.title,
                subtitle: item.url,
                icon: NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil),
                detailText: "\(item.title)\n\n\(item.url)\n\nSaved: \(formatDate(item.createdAt))",
                action: {
                    // Open URL and remove from list
                    ReadLaterManager.shared.openURL(item.url)
                    ReadLaterManager.shared.remove(url: item.url)
                }
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}