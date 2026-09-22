// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CoreServices

/// Queries the macOS system dictionary via Dictionary Services.
/// Returns the brief definition; provides option to open full dictionary.
final class DictionaryPlugin: Plugin {

    let keyword = "dict"
    let pluginDescription = "Look up a word in the macOS system dictionary"

    func query(_ input: String) -> [PluginResult] {
        let word = input.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else {
            return [PluginResult(title: "Type a word to look up")]
        }

        guard let definition = lookup(word) else {
            return [PluginResult(title: "No definition found for \"\(word)\"")]
        }

        // Show first line as title, full definition in preview
        let lines = definition
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return [PluginResult(title: "No definition found for \"\(word)\"")]
        }

        // Create result with option to open in Dictionary.app
        let detail = """
        \(definition)
        
        ────────────────────────
        Press Enter to open in Dictionary.app
        """

        return [PluginResult(
            title: lines[0],
            subtitle: lines.count > 1 ? "\(lines.count - 1) more lines" : nil,
            icon: NSImage(systemSymbolName: "book", accessibilityDescription: nil),
            detailText: detail,
            action: {
                // Open in Dictionary.app
                if let url = URL(string: "dict://\(word)") {
                    NSWorkspace.shared.open(url)
                }
            }
        )]
    }

    /// Look up a word using Dictionary Services.
    private func lookup(_ word: String) -> String? {
        let range = CFRangeMake(0, word.utf16.count)
        guard let definition = DCSCopyTextDefinition(
            nil,
            word as CFString,
            range
        ) else {
            return nil
        }
        return definition.takeRetainedValue() as String
    }
}