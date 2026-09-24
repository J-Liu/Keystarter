// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Manages browser bookmarks from Safari and Chrome.
final class BrowserBookmarksManager {

    static let shared = BrowserBookmarksManager()

    private var bookmarks: [BookmarkItem] = []
    private let lock = NSLock()

    struct BookmarkItem {
        let title: String
        let url: String
        let browser: String // "Safari" or "Chrome"
    }

    private init() {
        loadBookmarks()
    }

    func loadBookmarks() {
        lock.lock()
        defer { lock.unlock() }

        bookmarks = []
        loadSafariBookmarks()
        loadChromeBookmarks()
    }

    private func loadSafariBookmarks() {
        let path = NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let children = plist["Children"] as? [[String: Any]] else {
            return
        }

        parseSafariBookmarkNodes(children)
    }

    private func parseSafariBookmarkNodes(_ nodes: [[String: Any]]) {
        for node in nodes {
            if let webBookmark = node["WebBookmarkType"] as? String, webBookmark == "WebBookmarkTypeLeaf" {
                if let title = node["TitleDict"] as? [String: Any],
                   let url = node["URLString"] as? String {
                    let name = title["en"] as? String ?? "Untitled"
                    bookmarks.append(BookmarkItem(title: name, url: url, browser: "Safari"))
                }
            } else if let children = node["Children"] as? [[String: Any]] {
                parseSafariBookmarkNodes(children)
            }
        }
    }

    private func loadChromeBookmarks() {
        let path = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Default/Bookmarks"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else {
            return
        }

        for (_, value) in roots {
            if let node = value as? [String: Any] {
                parseChromeBookmarkNode(node)
            }
        }
    }

    private func parseChromeBookmarkNode(_ node: [String: Any]) {
        if let type = node["type"] as? String {
            if type == "url", let name = node["name"] as? String, let url = node["url"] as? String {
                bookmarks.append(BookmarkItem(title: name, url: url, browser: "Chrome"))
            } else if type == "folder", let children = node["children"] as? [[String: Any]] {
                for child in children {
                    parseChromeBookmarkNode(child)
                }
            }
        }
    }

    func search(_ query: String) -> [BookmarkItem] {
        lock.lock()
        defer { lock.unlock() }

        let lowered = query.lowercased()
        return bookmarks.filter { item in
            item.title.lowercased().contains(lowered) ||
            item.url.lowercased().contains(lowered)
        }
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
