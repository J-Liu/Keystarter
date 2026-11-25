// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Plugin to display and manage saved URLs.
/// Usage: "rl" or "readlater" shows all saved items.
final class ReadLaterPlugin: Plugin {

    let keyword = "rl"
    var pluginDescription: String { L("readlater.pluginDescription") }

    init() {}

    func query(_ input: String) -> [PluginResult] {
        let items = ReadLaterManager.shared.getAll()

        if items.isEmpty {
            return [PluginResult(
                title: L("readlater.empty"),
                subtitle: L("readlater.empty.hint"),
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
                detailText: "\(item.title)\n\n\(item.url)\n\n\(L("readlater.saved")): \(formatDate(item.createdAt))",
                action: {
                    // Open URL
                    ReadLaterManager.shared.openURL(item.url)
                    // Remove from list if autoDelete is enabled (default: true)
                    let autoDelete = UserDefaults.standard.object(forKey: "readlater.autoDelete") as? Bool ?? true
                    if autoDelete {
                        ReadLaterManager.shared.remove(url: item.url)
                    }
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