// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import CoreServices
import Foundation

/// Spotlight-based file search service.
final class SpotlightService {

    static let shared = SpotlightService()

    private init() {}

    // MARK: - File Name Search

    /// Search files by name using Spotlight.
    func searchFiles(query: String, limit: Int = 100) -> [(path: String, name: String, isDir: Bool)] {
        guard !query.isEmpty else { return [] }

        let escaped = query
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // 'cd' = case-insensitive, diacritic-insensitive
        // '*' at end = prefix match
        let expression = "kMDItemFSName == '*\(escaped)*'cd"

        var results: [(path: String, name: String, isDir: Bool)] = []

        guard let queryRef = MDQueryCreate(nil, expression as CFString, nil, nil) else {
            return results
        }

        // Set search scope to user-specified directories
        let scopes = getSearchScopes()
        MDQuerySetSearchScope(queryRef, scopes as CFArray, 0)
        MDQuerySetMaxCount(queryRef, CFIndex(limit))

        guard MDQueryExecute(queryRef, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            return results
        }

        let count = MDQueryGetResultCount(queryRef)
        for i in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(queryRef, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let name = (path as NSString).lastPathComponent
            let kindString = MDItemCopyAttribute(item, kMDItemKind) as? String
            let isDir = kindString?.lowercased().contains("folder") ?? false

            results.append((path: path, name: name, isDir: isDir))
        }

        return results
    }

    // MARK: - File Content Search

    /// Search files by content using Spotlight.
    func searchContent(query: String, limit: Int = 100) -> [(path: String, name: String)] {
        guard !query.isEmpty else { return [] }

        let escaped = query
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // kMDItemTextContent searches file contents
        let expression = "kMDItemTextContent == '*\(escaped)*'cd"

        var results: [(path: String, name: String)] = []

        guard let queryRef = MDQueryCreate(nil, expression as CFString, nil, nil) else {
            return results
        }

        let scopes = getSearchScopes()
        MDQuerySetSearchScope(queryRef, scopes as CFArray, 0)
        MDQuerySetMaxCount(queryRef, CFIndex(limit))

        guard MDQueryExecute(queryRef, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            return results
        }

        let count = MDQueryGetResultCount(queryRef)
        for i in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(queryRef, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let name = (path as NSString).lastPathComponent

            results.append((path: path, name: name))
        }

        return results
    }

    // MARK: - Combined Search

    /// Search both filename and content, ranked.
    func search(query: String, limit: Int = 100) -> [(path: String, name: String, isDir: Bool)] {
        guard !query.isEmpty else { return [] }

        var results: [(path: String, name: String, isDir: Bool, score: Double)] = []
        var seenPaths = Set<String>()

        // 1. Filename matches (higher score)
        let fileMatches = searchFiles(query: query, limit: limit)
        for match in fileMatches {
            guard seenPaths.insert(match.path).inserted else { continue }
            let score = scoreFor(path: match.path, name: match.name, isFileName: true)
            results.append((match.path, match.name, match.isDir, score))
        }

        // 2. Content matches (lower score) - enabled by default
        let contentEnabled = UserDefaults.standard.object(forKey: "index.fileContent") as? Bool ?? true
        if contentEnabled {
            let contentMatches = searchContent(query: query, limit: limit)
            for match in contentMatches {
                guard seenPaths.insert(match.path).inserted else { continue }
                let score = scoreFor(path: match.path, name: match.name, isFileName: false)
                results.append((match.path, match.name, false, score))
            }
        }

        // Sort by score and return
        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { ($0.path, $0.name, $0.isDir) }
    }

    // MARK: - Helpers

    private func getSearchScopes() -> [URL] {
        // Search entire home directory
        return [URL(fileURLWithPath: NSHomeDirectory())]
    }

    private func scoreFor(path: String, name: String, isFileName: Bool) -> Double {
        var score: Double = 0

        // Filename matches score higher
        if isFileName {
            score += 100
        } else {
            score += 10
        }

        // Prefer shorter paths (less nested)
        let depth = path.split(separator: "/").count
        score += Double(max(0, 20 - depth))

        // Boost recently used files
        let usageCount = LaunchHistory.shared.count(for: path)
        score += Double(usageCount) * 2

        return score
    }

    /// Check if Spotlight is enabled for search.
    static func isSpotlightEnabled() -> Bool {
        // Try a simple query to test if Spotlight is working
        guard let query = MDQueryCreate(nil, "kMDItemFSName == '.DS_Store'cd" as CFString, nil, nil) else {
            return false
        }
        MDQuerySetSearchScope(query, [URL(fileURLWithPath: NSHomeDirectory())] as CFArray, 0)
        MDQuerySetMaxCount(query, 1)

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            return false
        }

        // If we got any results, Spotlight is working
        return MDQueryGetResultCount(query) >= 0
    }
}