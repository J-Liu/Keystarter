// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CoreServices

/// Queries the macOS system dictionary via Dictionary Services.
/// Returns the definition as plain text, shown directly in the launcher.
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

        // Split definition into lines for readability
        let lines = definition
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return [PluginResult(title: "No definition found for \"\(word)\"")]
        }

        // First line as title, rest as subtitle
        let title = lines[0]
        let subtitle = lines.dropFirst().joined(separator: "\n")

        return [PluginResult(
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            icon: NSImage(systemSymbolName: "book", accessibilityDescription: nil),
            action: {
                // Copy full definition to clipboard on Enter
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(definition, forType: .string)
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
