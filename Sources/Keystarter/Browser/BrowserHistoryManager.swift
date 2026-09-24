// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import SQLite3

/// Manages browser history from Safari and Chrome.
final class BrowserHistoryManager {

    static let shared = BrowserHistoryManager()

    private var history: [HistoryItem] = []
    private let lock = NSLock()

    struct HistoryItem {
        let title: String
        let url: String
        let browser: String
        let visitCount: Int
        let lastVisit: Date
    }

    private init() {
        loadHistory()
    }

    func loadHistory() {
        lock.lock()
        defer { lock.unlock() }

        history = []
        loadSafariHistory()
        loadChromeHistory()
    }

    private func loadSafariHistory() {
        let path = NSHomeDirectory() + "/Library/Safari/History.db"
        var db: OpaquePointer?

        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT hi.title, hi.url, hv.visit_count, hv.visit_time
        FROM history_items hi
        JOIN history_visits hv ON hi.id = hv.history_item
        ORDER BY hv.visit_time DESC
        LIMIT 500;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let title = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let url = String(cString: sqlite3_column_text(stmt, 1))
            let visitCount = Int(sqlite3_column_int(stmt, 2))
            let visitTime = sqlite3_column_double(stmt, 3)
            let lastVisit = Date(timeIntervalSinceReferenceDate: visitTime)

            history.append(HistoryItem(
                title: title,
                url: url,
                browser: "Safari",
                visitCount: visitCount,
                lastVisit: lastVisit
            ))
        }
    }

    private func loadChromeHistory() {
        let path = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/History"
        var db: OpaquePointer?

        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT url, title, visit_count, last_visit_time
        FROM urls
        ORDER BY last_visit_time DESC
        LIMIT 500;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let url = String(cString: sqlite3_column_text(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let visitCount = Int(sqlite3_column_int(stmt, 2))
            let lastVisitTime = sqlite3_column_int64(stmt, 3)
            // Chrome uses microseconds since 1601-01-01, convert to Unix timestamp
            let unixTimestamp = Double(lastVisitTime) / 1000000.0 - 11644473600.0
            let lastVisit = Date(timeIntervalSince1970: unixTimestamp)

            history.append(HistoryItem(
                title: title,
                url: url,
                browser: "Chrome",
                visitCount: visitCount,
                lastVisit: lastVisit
            ))
        }
    }

    func search(_ query: String, limit: Int = 20) -> [HistoryItem] {
        lock.lock()
        defer { lock.unlock() }

        let lowered = query.lowercased()
        let filtered = history.filter { item in
            item.title.lowercased().contains(lowered) ||
            item.url.lowercased().contains(lowered)
        }

        // Sort by visit count and recency
        return Array(filtered.sorted { a, b in
            if a.visitCount != b.visitCount {
                return a.visitCount > b.visitCount
            }
            return a.lastVisit > b.lastVisit
        }.prefix(limit))
    }

    func getIcon(for browser: String) -> NSImage? {
        if browser == "Safari" {
            return NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
        } else if browser == "Chrome" {
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        }
        return nil
    }
}
