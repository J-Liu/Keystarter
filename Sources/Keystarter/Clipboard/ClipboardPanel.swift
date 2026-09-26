// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

struct ClipboardEntry {
    let id: Int64
    let type: String
    let content: String
    let createdAt: Date
}

/// Clipboard panel using NSMenu.
final class ClipboardPanel: NSObject {

    private var menu: NSMenu?
    private var entries: [ClipboardEntry] = []
    private var previousApp: NSRunningApplication?

    /// Cached entries for instant display
    private var cachedEntries: [ClipboardEntry] = []
    private let cacheQueue = DispatchQueue(label: "com.keystarter.clipboard.cache", qos: .utility)
    
    /// Thumbnail cache [path: image]
    private var thumbnailCache: [String: NSImage] = [:]
    private let thumbnailCacheQueue = DispatchQueue(label: "com.keystarter.clipboard.thumbnails", qos: .utility)

    override init() {
        super.init()
        refreshCache()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshCache),
            name: .clipboardChanged,
            object: nil
        )
    }

    @objc private func refreshCache() {
        cacheQueue.async { [weak self] in
            let maxCount = UserDefaults.standard.integer(forKey: "clipboard.maxCount")
            let limit = maxCount > 0 ? maxCount : 500
            let entries = ClipboardManager.shared.db.getClipboard(limit: limit).map {
                ClipboardEntry(id: $0.id, type: $0.type, content: $0.content, createdAt: $0.createdAt)
            }
            DispatchQueue.main.async {
                self?.cachedEntries = entries
            }
            
            // Pre-cache thumbnails in background
            for entry in entries where entry.type == "image" {
                _ = self?.createThumbnailFromFile(entry.content, maxSize: 32)
            }
        }
    }

    func toggle() {
        if menu != nil {
            hide()
        } else {
            show()
        }
    }

    func show() {
        entries = cachedEntries
        buildMenu()

        previousApp = NSWorkspace.shared.frontmostApplication

        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }

        var x = mouseLoc.x
        var y = mouseLoc.y

        if x < screenFrame.minX + 50 { x = screenFrame.minX + 50 }
        if x > screenFrame.maxX - 50 { x = screenFrame.maxX - 50 }
        if y < screenFrame.minY + 100 { y = screenFrame.minY + 100 }
        if y > screenFrame.maxY - 50 { y = screenFrame.maxY - 50 }

        menu?.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: nil)
    }

    func hide() {
        menu?.cancelTracking()
        menu = nil
    }

    private func loadEntries() {
        entries = cachedEntries
    }

    private func buildMenu() {
        menu = NSMenu()
        menu?.delegate = self

        if entries.isEmpty {
            let item = NSMenuItem(title: L("clipboard.empty"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu?.addItem(item)
            menu?.addItem(NSMenuItem.separator())

            let settingsItem = NSMenuItem(title: L("clipboard.settings"), action: #selector(openSettings), keyEquivalent: "")
            settingsItem.target = self
            menu?.addItem(settingsItem)
            return
        }

        // Group by 10
        let groups = stride(from: 0, to: entries.count, by: 10).map {
            Array(entries[$0..<min($0 + 10, entries.count)])
        }

        for (groupIndex, group) in groups.enumerated() {
            let startNum = groupIndex * 10 + 1
            let endNum = startNum + group.count - 1
            let groupTitle = "\(startNum)-\(endNum)"

            // Create submenu for this group
            let groupMenu = NSMenu()

            for (index, entry) in group.enumerated() {
                let number = index + 1
                var title = entry.content
                var image: NSImage? = nil

                if entry.type == "text" {
                    if title.count > 40 {
                        title = String(title.prefix(40)) + "..."
                    }
                } else {
                    // Use ImageIO for efficient thumbnail generation
                    if let thumbnail = createThumbnailFromFile(entry.content, maxSize: 32) {
                        image = thumbnail
                        title = ""
                    }
                }

                let item = NSMenuItem(title: "\(number). \(title)", action: #selector(pasteEntry(_:)), keyEquivalent: number == 10 ? "0" : "\(number)")
                item.representedObject = entry
                item.keyEquivalentModifierMask = .command
                item.target = self
                if let img = image {
                    item.image = img
                }
                groupMenu.addItem(item)
            }

            // Add group item with submenu directly to main menu
            let groupItem = NSMenuItem(title: groupTitle, action: nil, keyEquivalent: "")
            groupItem.submenu = groupMenu
            menu?.addItem(groupItem)
        }

        menu?.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: L("clipboard.clear"), action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu?.addItem(clearItem)

        let settingsItem = NSMenuItem(title: L("clipboard.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu?.addItem(settingsItem)
    }

    @objc private func pasteEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipboardEntry else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if entry.type == "text" {
            pasteboard.setString(entry.content, forType: .string)
        } else if entry.type == "image" {
            // Write raw data directly, avoid NSImage decoding
            if let data = try? Data(contentsOf: URL(fileURLWithPath: entry.content)) {
                pasteboard.setData(data, forType: .png)
            }
        }

        // Move to front (update created_at)
        ClipboardManager.shared.db.touchEntry(id: entry.id)

        hide()

        DispatchQueue.main.async { [weak self] in
            self?.activateAndPaste()
        }
    }

    private func activateAndPaste() {
        guard PermissionManager.shared.hasAccessibilityPermission() else {
            let alert = NSAlert()
            alert.messageText = L("alert.permissions.title")
            alert.informativeText = L("alert.permissions.message")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("alert.grant"))
            alert.addButton(withTitle: L("alert.cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                _ = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
                ] as CFDictionary)
            }
            return
        }

        if let app = previousApp {
            app.activate()
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L("alert.clearHistory.title")
        alert.informativeText = L("alert.clearHistory.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("alert.clear"))
        alert.addButton(withTitle: L("alert.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            ClipboardManager.shared.db.clearClipboard()
        }
    }

    @objc private func openSettings() {
        hide()
        (NSApp.delegate as? AppDelegate)?.showClipboardSettings()
    }

    private func createThumbnail(from image: NSImage, maxSize: CGFloat) -> NSImage {
        let srcSize = image.size
        let aspectRatio = srcSize.width / srcSize.height

        var thumbnailSize: NSSize
        if aspectRatio > 1 {
            // Landscape
            thumbnailSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            // Portrait
            thumbnailSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()

        let srcRect = NSRect(origin: .zero, size: srcSize)
        let dstRect = NSRect(origin: .zero, size: thumbnailSize)

        image.draw(in: dstRect, from: srcRect, operation: .sourceOver, fraction: 1.0)

        thumbnail.unlockFocus()
        return thumbnail
    }

    private func createThumbnailFromFile(_ path: String, maxSize: CGFloat) -> NSImage? {
        // Check cache first
        if let cached = thumbnailCacheQueue.sync(execute: { thumbnailCache[path] }) {
            return cached
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        
        // Cache for future use
        thumbnailCacheQueue.async { [weak self] in
            self?.thumbnailCache[path] = image
        }
        
        return image
    }
}

// MARK: - NSMenuDelegate

extension ClipboardPanel: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        self.menu = nil
    }
}