// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Fuzzy string matching for search.
final class FuzzyMatcher {

    static let shared = FuzzyMatcher()

    private init() {}

    /// Check if query fuzzy matches text.
    /// Returns true if all characters in query appear in text in order.
    /// E.g., "rdme" matches "readme.md"
    func matches(query: String, text: String) -> Bool {
        let queryLower = query.lowercased()
        let textLower = text.lowercased()

        var queryIndex = queryLower.startIndex
        var textIndex = textLower.startIndex

        while queryIndex < queryLower.endIndex && textIndex < textLower.endIndex {
            if queryLower[queryIndex] == textLower[textIndex] {
                queryIndex = queryLower.index(after: queryIndex)
            }
            textIndex = textLower.index(after: textIndex)
        }

        return queryIndex == queryLower.endIndex
    }

    /// Calculate fuzzy match score (higher = better match).
    /// Prefers consecutive matches and matches near the start.
    func score(query: String, text: String) -> Double {
        let queryLower = query.lowercased()
        let textLower = text.lowercased()

        guard !queryLower.isEmpty else { return 0 }

        var score = 0.0
        var queryIndex = queryLower.startIndex
        var textIndex = textLower.startIndex
        var lastMatchIndex: String.Index?
        var consecutiveCount = 0

        while queryIndex < queryLower.endIndex && textIndex < textLower.endIndex {
            if queryLower[queryIndex] == textLower[textIndex] {
                // Bonus for match at start
                if textIndex == textLower.startIndex {
                    score += 10
                }

                // Bonus for consecutive matches
                if let last = lastMatchIndex,
                   textLower.index(after: last) == textIndex {
                    consecutiveCount += 1
                    score += Double(consecutiveCount) * 2
                } else {
                    consecutiveCount = 0
                }

                lastMatchIndex = textIndex
                queryIndex = queryLower.index(after: queryIndex)
            }
            textIndex = textLower.index(after: textIndex)
        }

        // Query not fully matched
        if queryIndex < queryLower.endIndex {
            return 0
        }

        // Penalty for early non-matches
        let distanceFromStart = Double(textLower.distance(from: textLower.startIndex, to: lastMatchIndex ?? textLower.startIndex))
        score -= distanceFromStart * 0.5

        return max(0, score)
    }
}