// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Translates text using MyMemory free API (1000 words/day, no key required).
/// Usage: "tr hello" or "tr en hello" (specify target language).
final class TranslatePlugin: Plugin {

    let keyword = "tr"
    let pluginDescription = "Translate text between languages"

    private let defaultTarget = "zh-CN"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    // Cache for async results
    private var cachedResult: String?
    private var cachedInput: String?
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 1.0

    func query(_ input: String) -> [PluginResult] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return [PluginResult(title: "Type text to translate")]
        }

        // Return cached result if available
        if let cached = cachedResult, cachedInput == trimmed {
            return makeResult(text: trimmed, translation: cached, target: defaultTarget)
        }

        // Parse optional target language
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        var target = defaultTarget
        var text = trimmed

        if parts.count == 2, isLanguageCode(String(parts[0])) {
            target = String(parts[0])
            text = String(parts[1])
        }

        // Throttle requests - don't spam the API
        if let last = lastRequestTime, Date().timeIntervalSince(last) < minRequestInterval {
            return [PluginResult(title: "Translating...", subtitle: text)]
        }

        // Async translation
        translateAsync(text, to: target) { [weak self] result in
            DispatchQueue.main.async {
                self?.cachedResult = result
                self?.cachedInput = trimmed
                self?.lastRequestTime = Date()
                // Trigger UI refresh
                NotificationCenter.default.post(name: .translationComplete, object: nil)
            }
        }

        return [PluginResult(title: "Translating...", subtitle: text)]
    }

    private func makeResult(text: String, translation: String, target: String) -> [PluginResult] {
        // Build URL for MyMemory website
        let source = detectSource(text)
        let webURL = "https://mymemory.translated.net/en/\(source)/\(target)/\(text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text)"
        
        return [PluginResult(
            title: translation,
            subtitle: "\(text) → \(target)",
            icon: NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil),
            detailText: "\(text)\n\n\(translation)\n\n────────────────────────\nDouble-click to open in browser",
            action: {
                // Copy to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(translation, forType: .string)
                
                // Open in browser
                if let url = URL(string: webURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        )]
    }

    private func isLanguageCode(_ s: String) -> Bool {
        return (s.count == 2 || s.count == 5) && s.allSatisfy { $0.isLetter || $0 == "-" }
    }

    private func translateAsync(_ text: String, to target: String, completion: @escaping (String?) -> Void) {
        let source = detectSource(text)
        let apiTarget = target == "zh" ? "zh-CN" : target

        // Build URL with proper encoding
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(source)|\(apiTarget)")
        ]

        guard let url = components?.url else {
            completion(nil)
            return
        }

        session.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            let result = self.parseMyMemoryResponse(data)
            completion(result)
        }.resume()
    }

    private func parseMyMemoryResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["responseData"] as? [String: Any],
              let translatedText = responseData["translatedText"] as? String else {
            return nil
        }
        return translatedText
    }

    private func detectSource(_ text: String) -> String {
        for char in text {
            if char.isCJKCharacter {
                return "zh-CN"
            }
        }
        return "en"
    }
}

extension Notification.Name {
    static let translationComplete = Notification.Name("translationComplete")
}

private extension Character {
    var isCJKCharacter: Bool {
        for scalar in self.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value) ||
               (0x3400...0x4DBF).contains(value) ||
               (0x20000...0x2A6DF).contains(value) {
                return true
            }
        }
        return false
    }
}