// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Converts Chinese characters to pinyin for search matching.
final class PinyinConverter {

    static let shared = PinyinConverter()

    private init() {}

    /// Get pinyin initials for a string (e.g., "你好" -> "nh")
    func initials(_ text: String) -> String {
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        let pinyin = mutableString as String
        return pinyin
            .split(separator: " ")
            .compactMap { $0.first?.lowercased() }
            .joined()
    }

    /// Get full pinyin for a string (e.g., "你好" -> "nihao")
    func fullPinyin(_ text: String) -> String {
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return (mutableString as String)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// Check if query matches text using pinyin initials.
    func matchesInitials(query: String, text: String) -> Bool {
        let queryLower = query.lowercased()
        let initials = self.initials(text)
        return initials.hasPrefix(queryLower) || initials.contains(queryLower)
    }

    /// Check if query matches text using full pinyin.
    func matchesFullPinyin(query: String, text: String) -> Bool {
        let queryLower = query.lowercased()
        let pinyin = fullPinyin(text)
        return pinyin.hasPrefix(queryLower) || pinyin.contains(queryLower)
    }
}