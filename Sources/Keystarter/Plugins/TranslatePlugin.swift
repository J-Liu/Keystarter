// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Translates text using MyMemory free API (1000 words/day, no key required).
/// Usage: "tr hello" or "tr en hello" (specify target language).
final class TranslatePlugin: Plugin {

    let keyword = "tr"
    let pluginDescription = "Translate text between languages"

    private let defaultTarget = "zh-CN"
    private let session = URLSession(configuration: .ephemeral)

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

        // MyMemory uses "zh-CN" format, but also accepts "zh"
        let apiTarget = target == "zh" ? "zh-CN" : target

        // Perform synchronous translation
        guard let result = translateSync(text, to: apiTarget) else {
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

    private func isLanguageCode(_ s: String) -> Bool {
        return (s.count == 2 || s.count == 5) && s.allSatisfy { $0.isLetter || $0 == "-" }
    }

    // MARK: - MyMemory API

    private func translateSync(_ text: String, to target: String) -> String? {
        // MyMemory API: https://mymemory.translated.net/api/spec
        // GET https://api.mymemory.translated.net/get?q=hello&langpair=en|zh-CN
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let source = detectSource(text)
        let urlString = "https://api.mymemory.translated.net/get?q=\(encodedText)&langpair=\(source)|\(target)"

        guard let url = URL(string: urlString) else { return nil }

        var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: url) { data, _, _ in
            if let data = data {
                result = self.parseMyMemoryResponse(data)
            }
            semaphore.signal()
        }
        task.resume()

        semaphore.wait()
        return result
    }

    private func parseMyMemoryResponse(_ data: Data) -> String? {
        // Response: {"responseData":{"translatedText":"你好"},"responseStatus":200}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["responseData"] as? [String: Any],
              let translatedText = responseData["translatedText"] as? String else {
            return nil
        }
        return translatedText
    }

    /// Detect source language by checking for CJK characters.
    private func detectSource(_ text: String) -> String {
        for char in text {
            if char.isCJKCharacter {
                return "zh-CN"
            }
        }
        return "en"
    }
}

private extension Character {
    var isCJKCharacter: Bool {
        for scalar in self.unicodeScalars {
            let value = scalar.value
            // CJK Unified Ideographs ranges
            if (0x4E00...0x9FFF).contains(value) ||
               (0x3400...0x4DBF).contains(value) ||
               (0x20000...0x2A6DF).contains(value) ||
               (0x2A700...0x2B73F).contains(value) {
                return true
            }
        }
        return false
    }
}