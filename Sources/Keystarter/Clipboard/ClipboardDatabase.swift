// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import SQLite3

/// SQLite database for clipboard history.
final class ClipboardDatabase {

    private var db: OpaquePointer?
    private let lock = NSLock()

    init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dbPath = dir + "/clipboard.db"

        lock.lock()
        defer { lock.unlock() }
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            return
        }
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            hash TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    func insertClipboard(type: String, content: String, hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "INSERT OR IGNORE INTO clipboard (type, content, hash, created_at) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, (type as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (hash as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970))
        sqlite3_step(stmt)
        let changes = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        return changes > 0
    }

    func getClipboard(limit: Int = 30) -> [(id: Int64, type: String, content: String, createdAt: Date)] {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT id, type, content, created_at FROM clipboard ORDER BY created_at DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var results: [(Int64, String, String, Date)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let type = String(cString: sqlite3_column_text(stmt, 1))
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let createdAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 3)))
            results.append((id, type, content, createdAt))
        }
        sqlite3_finalize(stmt)
        return results
    }

    func clearClipboard() {
        lock.lock()
        defer { lock.unlock() }
        sqlite3_exec(db, "DELETE FROM clipboard;", nil, nil, nil)
    }
}