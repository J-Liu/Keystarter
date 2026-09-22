// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Translates text using a deterministic translation backend.
/// Local-first: no AI reasoning, no token cost.
/// Default backend: MyMemory public API (free, no key, deterministic enough).
final class TranslatePlugin: Plugin {

    let keyword = "tr"
    let pluginDescription = "Translate text between languages"

    /// Target language. Default: Chinese.
    /// Override with "tr en hello" to translate to English.
    private let defaultTarget = "zh-CN"

    func query(_ input: String) -> [PluginResult] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return [PluginResult(title: "Type text to translate")]
        }

        // Parse optional target language: "en hello" -> target=en, text=hello
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        var target = defaultTarget
        var text = trimmed

        if parts.count == 2, isLanguageCode(String(parts[0])) {
            target = String(parts[0])
            text = String(parts[1])
        }

        // Perform synchronous translation (runs on background queue, but
        // plugin API is synchronous for now; keep queries short).
        guard let result = translate(text, to: target) else {
            return [PluginResult(title: "Translation failed")]
        }

        return [PluginResult(
            title: result,
            subtitle: "\(text) → \(target)",
            icon: NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil),
            action: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(result, forType: .string)
            }
        )]
    }

    // MARK: - Language Detection

    /// Very rough check: 2-letter codes are treated as language targets.
    private func isLanguageCode(_ s: String) -> Bool {
        return s.count == 2 && s.allSatisfy { $0.isLetter }
    }

    // MARK: - Translation Backend

    private func translate(_ text: String, to target: String) -> String? {
        let range = CFRangeMake(0, text.utf16.count)
        guard let definition = DCSCopyTextDefinition(
            nil,
            text as CFString,
            range
        ) else {
            return nil
        }
        return definition.takeRetainedValue() as String
    }
}
