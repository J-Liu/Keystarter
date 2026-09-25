// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import SQLite3

/// SQLite-backed file index with FTS5 full-text search.
/// Replaces Spotlight / mdfind for file search.
final class IndexDatabase {

    private var db: OpaquePointer?
    private let dbPath: String
    private let lock = NSLock()  // Serialize all DB access

    init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        dbPath = dir + "/index.db"
    }

    deinit {
        sqlite3_close(db)
    }

    /// Open the database and create tables if needed.
    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            return false
        }
        createTables()
        return true
    }
    
    /// Check if index has any entries.
    func hasIndex() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM files LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        var count: Int = 0
        if sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int(stmt, 0))
        }
        sqlite3_finalize(stmt)
        return count > 0
    }

    private func createTables() {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            is_dir INTEGER NOT NULL DEFAULT 0
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            name,
            path,
            content='files',
            content_rowid='id'
        );
        CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, name, path) VALUES (new.id, new.name, new.path);
        END;
        CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, name, path) VALUES('delete', old.id, old.name, old.path);
        END;
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

    /// Insert or replace a file entry.
    func upsert(path: String, name: String, isDir: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "INSERT OR REPLACE INTO files (path, name, is_dir) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, isDir ? 1 : 0)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// Clear the entire index.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        sqlite3_exec(db, "DELETE FROM files;", nil, nil, nil)
    }

    /// Delete a file entry by path.
    func delete(path: String) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "DELETE FROM files WHERE path = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// Search by name using FTS5.
    func search(_ query: String, limit: Int = 50) -> [(path: String, name: String, isDir: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.isEmpty else { return [] }
        let sql = """
        SELECT f.path, f.name, f.is_dir
        FROM files_fts fts
        JOIN files f ON f.id = fts.rowid
        WHERE files_fts MATCH ?
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        // FTS5 prefix match: "key*"
        let matchQuery = query + "*"
        sqlite3_bind_text(stmt, 1, (matchQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [(String, String, Bool)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let isDir = sqlite3_column_int(stmt, 2) == 1
            results.append((path, name, isDir))
        }
        sqlite3_finalize(stmt)
        return results
    }

    func beginTransaction() {
        lock.lock()
        sqlite3_exec(db, "BEGIN;", nil, nil, nil)
    }

    func commitTransaction() {
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        lock.unlock()
    }

    // MARK: - Clipboard

    /// Insert a clipboard entry. Returns true if inserted, false if duplicate.
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

    /// Get recent clipboard entries.
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

    /// Delete clipboard entries older than days or exceeding max count.
    func cleanClipboard(maxCount: Int, maxDays: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Delete by age
        let cutoff = Date().addingTimeInterval(-Double(maxDays * 86400)).timeIntervalSince1970
        var sql = "DELETE FROM clipboard WHERE created_at < ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(cutoff))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        // Delete by count (keep most recent)
        sql = "DELETE FROM clipboard WHERE id NOT IN (SELECT id FROM clipboard ORDER BY created_at DESC LIMIT ?);"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(maxCount))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Clear all clipboard history.
    func clearClipboard() {
        lock.lock()
        defer { lock.unlock() }
        sqlite3_exec(db, "DELETE FROM clipboard;", nil, nil, nil)
    }
}
