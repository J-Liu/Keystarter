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

    override init() {
        super.init()
    }

    func toggle() {
        if menu != nil {
            hide()
        } else {
            show()
        }
    }

    func show() {
        loadEntries()
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
        let maxCount = UserDefaults.standard.integer(forKey: "clipboard.maxCount")
        let limit = maxCount > 0 ? maxCount : 500
        entries = ClipboardManager.shared.db.getClipboard(limit: limit).map {
            ClipboardEntry(id: $0.id, type: $0.type, content: $0.content, createdAt: $0.createdAt)
        }
    }

    private func buildMenu() {
        menu = NSMenu()
        menu?.delegate = self

        if entries.isEmpty {
            let item = NSMenuItem(title: "No clipboard history", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu?.addItem(item)
            menu?.addItem(NSMenuItem.separator())

            let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
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

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu?.addItem(clearItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
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

        hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.activateAndPaste()
        }
    }

    private func activateAndPaste() {
        guard PermissionManager.shared.hasAccessibilityPermission() else {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Keystarter needs Accessibility permission to paste content."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Grant Permission")
            alert.addButton(withTitle: "Cancel")
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
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will delete all clipboard entries."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
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

        return NSImage(cgImage: cgImage, size: .zero)
    }
}

// MARK: - NSMenuDelegate

extension ClipboardPanel: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        self.menu = nil
    }
}