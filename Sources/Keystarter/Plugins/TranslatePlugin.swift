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

    /// Synchronous translation via MyMemory API.
    /// This is a placeholder backend; swap for a local model or another
    /// deterministic service later without touching the plugin interface.
    private func translate(_ text: String, to target: String) -> String? {
        // Source language: auto-detect is not supported by MyMemory the same way,
        // so we leave it empty and let the service guess.
        let source = ""

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(source)|\(target)")
        ]

        guard let url = components.url else { return nil }

        // Synchronous request with short timeout.
        // In production, move this off the main thread.
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let semaphore = DispatchSemaphore(value: 0)
        var translated: String?

        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["responseData"] as? [String: Any],
                  let text = responseData["translatedText"] as? String
            else { return }
            translated = text
        }.resume()

        _ = semaphore.wait(timeout: .now() + 6)
        return translated
    }
}
