// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Scans directories and populates the index.
/// Skips noise directories (node_modules, target, .venv, etc.).
final class IndexScanner {

    private let db: IndexDatabase

    /// Directory names to skip entirely.
    private let ignoredDirs: Set<String> = [
        "node_modules", "target", ".venv", "venv", "env",
        "__pycache__", ".git", ".pytest_cache", ".mypy_cache",
        ".ruff_cache", "dist", "build", ".build", ".next", ".nuxt",
        "DerivedData", "Pods", "Carthage", ".Trash",
        "Library"
    ]

    init(db: IndexDatabase) {
        self.db = db
    }

    /// Full scan of the given roots.
    func scan(roots: [String]) {
        db.clear()
        db.beginTransaction()
        for root in roots {
            // scanDirectory(root)
            scanDirectory(root, depth: 0)
        }
        db.commitTransaction()
    }

    private func scanDirectory(_ path: String, depth: Int = 0) {
        if depth > 2 { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return }

        for name in contents {
            // Skip hidden files
            if name.hasPrefix(".") { continue }

            let fullPath = path + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                // Skip ignored directories
                if ignoredDirs.contains(name) { continue }
                db.upsert(path: fullPath, name: name, isDir: true)
                scanDirectory(fullPath, depth: depth + 1)
            } else {
                db.upsert(path: fullPath, name: name, isDir: false)
            }
        }
    }
}
