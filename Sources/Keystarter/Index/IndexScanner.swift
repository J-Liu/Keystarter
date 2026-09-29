// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Scans directories and populates the index.
/// Skips noise directories (node_modules, target, .venv, etc.).
final class IndexScanner {

    private let db: IndexDatabase

    /// Directory names to skip entirely.
    private var ignoredDirs: Set<String> {
        let defaults: Set<String> = [
            // Build outputs
            "node_modules", "target", "dist", "build", ".build", "out",
            // Python
            ".venv", "venv", "env", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
            // Git/VCS
            ".git", ".hg", ".svn",
            // IDE
            ".idea", ".vscode", "*.xcodeproj", "*.xcworkspace",
            // iOS/macOS build
            "DerivedData", "Build", "Intermediates", "Archives",
            // Cocoa package managers
            "Pods", "Carthage", "Build", ".swiftpm",
            // JS/TS
            ".next", ".nuxt", ".output", "bower_components",
            // Java/Kotlin
            ".gradle", "gradle", ".mvn",
            // Rust
            "target",
            // Go
            "vendor",
            // System
            "Library", ".Trash", "Trash", "Caches"
        ]
        if let custom = UserDefaults.standard.stringArray(forKey: "index.ignoredDirs") {
            return defaults.union(custom)
        }
        return defaults
    }

    /// Max recursion depth (0 = unlimited).
    private var maxDepth: Int {
        let depth = UserDefaults.standard.integer(forKey: "index.maxDepth")
        return depth > 0 ? depth : Int.max
    }

    /// File extensions to index content for.
    private var contentExtensions: Set<String> {
        let defaults: Set<String> = ["md", "txt", "swift", "py", "js", "json"]
        if let custom = UserDefaults.standard.stringArray(forKey: "index.contentExtensions") {
            return defaults.union(custom)
        }
        return defaults
    }

    /// Max file size for content indexing (100KB).
    private let maxContentFileSize: UInt64 = 100 * 1024

    init(db: IndexDatabase) {
        self.db = db
    }

    /// Max file count (100k).
    private let maxFileCount: Int = 100_000

    /// Callback when file count exceeds limit.
    var onLimitExceeded: ((Int) -> Void)?

    /// Full scan of the given roots.
    func scan(roots: [String]) {
        db.clear()
        db.beginTransaction()
        let indexContent = UserDefaults.standard.bool(forKey: "index.fileContent")
        var totalCount = 0
        for root in roots {
            scanDirectory(root, depth: 0, indexContent: indexContent, count: &totalCount)
            if totalCount > maxFileCount {
                break
            }
        }
        db.commitTransaction()

        if totalCount > maxFileCount {
            DispatchQueue.main.async { [weak self] in
                self?.onLimitExceeded?(totalCount)
            }
        }
    }

    private func scanDirectory(_ path: String, depth: Int = 0, indexContent: Bool, count: inout Int) {
        if depth > maxDepth { return }
        if count > maxFileCount { return }

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

                // Get directory modification time
                let modifiedAt = (try? fm.attributesOfItem(atPath: fullPath)[.modificationDate] as? Date)
                db.upsert(path: fullPath, name: name, isDir: true, modifiedAt: modifiedAt)
                count += 1
                scanDirectory(fullPath, depth: depth + 1, indexContent: indexContent, count: &count)
            } else {
                // Get file modification time
                let modifiedAt = (try? fm.attributesOfItem(atPath: fullPath)[.modificationDate] as? Date)
                db.upsert(path: fullPath, name: name, isDir: false, modifiedAt: modifiedAt)
                count += 1

                // Index file content if enabled
                if indexContent {
                    indexFileContent(path: fullPath)
                }
            }
        }
    }

    private func indexFileContent(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        guard contentExtensions.contains(ext) else { return }

        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size <= maxContentFileSize else { return }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.isEmpty else { return }

        db.upsertContent(path: path, content: content)
    }
}
