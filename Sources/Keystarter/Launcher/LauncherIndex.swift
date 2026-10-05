// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Pre-computed searchable alias for an entry.
struct SearchAlias: Hashable {
    enum Role: Int {
        case name = 0
        case acronym = 1
        case pinyinInitials = 2
        case pinyinFull = 3
        case bundleID = 4
        case path = 5
    }
    
    let text: String
    let role: Role
    
    init(_ text: String, _ role: Role) {
        self.text = text
        self.role = role
    }
}

/// Index entry with pre-built search aliases.
struct IndexEntry: Hashable {
    let name: String
    let path: String
    let aliases: [SearchAlias]
    
    /// Pre-built alias texts for fast matching.
    let aliasTexts: [String]
    
    init(name: String, path: String, bundleID: String? = nil) {
        self.name = name
        self.path = path
        
        var aliases: [SearchAlias] = []
        
        // 1. Name (primary)
        let nameLower = name.lowercased()
        aliases.append(SearchAlias(nameLower, .name))
        
        // 2. Acronym (e.g., "Visual Studio Code" -> "vsc")
        let acronym = name.components(separatedBy: " ")
            .compactMap { $0.first?.lowercased() }
            .joined()
        if !acronym.isEmpty && acronym != nameLower {
            aliases.append(SearchAlias(acronym, .acronym))
        }
        
        // 3. Pinyin initials (e.g., "微信" -> "wx")
        let pinyinInitials = PinyinConverter.shared.initials(name)
        if !pinyinInitials.isEmpty && pinyinInitials != nameLower {
            aliases.append(SearchAlias(pinyinInitials, .pinyinInitials))
        }
        
        // 4. Full pinyin (e.g., "微信" -> "weixin")
        let pinyinFull = PinyinConverter.shared.fullPinyin(name)
        if !pinyinFull.isEmpty && pinyinFull != nameLower && pinyinFull != pinyinInitials {
            aliases.append(SearchAlias(pinyinFull, .pinyinFull))
        }
        
        // 5. Bundle ID (if available)
        if let bundleID = bundleID {
            let bundleLower = bundleID.lowercased()
            // Extract app name from bundle ID (e.g., "com.apple.Safari" -> "safari")
            if let lastPart = bundleLower.split(separator: ".").last {
                aliases.append(SearchAlias(String(lastPart), .bundleID))
            }
            aliases.append(SearchAlias(bundleLower, .bundleID))
        }
        
        // 6. Path (file name without extension)
        let pathName = (path as NSString).lastPathComponent
        let pathBase = (pathName as NSString).deletingPathExtension.lowercased()
        if !pathBase.isEmpty && pathBase != nameLower {
            aliases.append(SearchAlias(pathBase, .path))
        }
        
        self.aliases = aliases
        self.aliasTexts = aliases.map(\.text)
    }
}

/// Memoization cache for search results.
final class SearchMemo {
    struct Key: Hashable {
        let query: String
        let revision: Int
    }
    
    private var cache: [Key: [IndexEntry]] = [:]
    private var lock = NSLock()
    
    func get(query: String, revision: Int) -> [IndexEntry]? {
        lock.lock()
        defer { lock.unlock() }
        return cache[Key(query: query, revision: revision)]
    }
    
    func set(query: String, revision: Int, results: [IndexEntry]) {
        lock.lock()
        defer { lock.unlock() }
        cache[Key(query: query, revision: revision)] = results
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

/// Launcher index with pre-built aliases and memoization.
@MainActor
final class LauncherIndex {
    static let shared = LauncherIndex()
    
    private(set) var entries: [IndexEntry] = []
    private var revision = 0
    private let memo = SearchMemo()
    
    private init() {}
    
    /// Update index with app entries.
    func update(apps: [(name: String, path: String, bundleID: String?)]) {
        let newEntries = apps.map { IndexEntry(name: $0.name, path: $0.path, bundleID: $0.bundleID) }
        guard newEntries != entries else { return }
        entries = newEntries
        revision &+= 1
        memo.clear()
    }
    
    /// Search entries matching query. Results are memoized.
    func search(_ query: String, limit: Int = 100) -> [IndexEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        
        // Check memo
        if let cached = memo.get(query: q, revision: revision) {
            return cached
        }
        
        // Fuzzy match query (pre-fold)
        let queryChars = Array(q)
        
        var scored: [(entry: IndexEntry, score: Int)] = []
        scored.reserveCapacity(min(entries.count, limit * 2))
        
        for entry in entries {
            guard let score = match(queryChars: queryChars, aliases: entry.aliasTexts) else { continue }
            scored.append((entry, score))
        }
        
        // Sort by score
        let results = scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.entry)
        
        // Cache results
        memo.set(query: q, revision: revision, results: Array(results))
        
        return Array(results)
    }
    
    /// Match query against alias texts, return score or nil if no match.
    private nonisolated func match(queryChars: [Character], aliases: [String]) -> Int? {
        var best: Int?
        
        for alias in aliases {
            guard let score = fuzzyMatch(query: queryChars, candidate: alias) else { continue }
            best = max(best ?? Int.min, score)
        }
        
        return best
    }
    
    /// Fuzzy match with scoring. Returns nil if no match.
    private nonisolated func fuzzyMatch(query: [Character], candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        
        let candidateChars = Array(candidate)
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        
        for (ci, ch) in candidateChars.enumerated() {
            guard qi < query.count else { break }
            
            if ch == query[qi] {
                var bonus = 1
                
                // Consecutive bonus
                if ci == prev + 1 {
                    run += 1
                    bonus += run * 3
                } else {
                    run = 0
                }
                
                // Start bonus
                if ci == 0 {
                    bonus += 12
                } else if !candidateChars[ci - 1].isLetter && !candidateChars[ci - 1].isNumber {
                    // Word boundary bonus
                    bonus += 8
                }
                
                score += bonus
                prev = ci
                qi += 1
            }
        }
        
        guard qi == query.count else { return nil }
        return score
    }
}