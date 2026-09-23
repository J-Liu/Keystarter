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

/// Floating panel for clipboard history.
final class ClipboardPanel: NSPanel {

    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var emptyView: NSView!
    private var entries: [ClipboardEntry] = []
    private var groups: [[ClipboardEntry]] = []
    private var currentGroup: Int = 0
    private var previousApp: NSRunningApplication?
    private var eventMonitor: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 190, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupUI()
    }

    private func setupUI() {
        let container = NSVisualEffectView(frame: contentView!.bounds)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.autoresizingMask = [.width, .height]
        contentView = container

        // Empty view
        emptyView = NSView(frame: container.bounds)
        emptyView.autoresizingMask = [.width, .height]
        setupEmptyView()
        container.addSubview(emptyView)

        // Scroll view with table
        scrollView = NSScrollView(frame: container.bounds.insetBy(dx: 8, dy: 8))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.isHidden = true

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 36
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.allowsMultipleSelection = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = scrollView.bounds.width
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        container.addSubview(scrollView)
    }

    private func setupEmptyView() {
        let y: CGFloat = 100

        let label = NSTextField(labelWithString: "No clipboard history")
        label.frame = NSRect(x: 0, y: y, width: emptyView.bounds.width, height: 24)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        emptyView.addSubview(label)

        // Separator
        let separator = NSView(frame: NSRect(x: 16, y: y - 20, width: emptyView.bounds.width - 32, height: 1))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        emptyView.addSubview(separator)

        // Settings menu item
        let settingsItem = MenuItemView(title: "Settings...", action: #selector(openSettings))
        settingsItem.frame = NSRect(x: 8, y: y - 48, width: emptyView.bounds.width - 16, height: 24)
        emptyView.addSubview(settingsItem)

        // Clear history menu item
        let clearItem = MenuItemView(title: "Clear History", action: #selector(clearHistory))
        clearItem.frame = NSRect(x: 8, y: y - 72, width: emptyView.bounds.width - 16, height: 24)
        emptyView.addSubview(clearItem)
    }

    @objc private func openSettings() {
        orderOut(nil)
        (NSApp.delegate as? AppDelegate)?.showClipboardSettings()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will delete all clipboard entries."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            (NSApp.delegate as? AppDelegate)?.indexDB?.clearClipboard()
            loadEntries()
        }
    }

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        loadEntries()
        adjustHeight()
        centerOnMouse()
        previousApp = NSWorkspace.shared.frontmostApplication
        makeKeyAndOrderFront(nil)
        
        // Monitor for clicks outside the panel
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.orderOut(nil)
        }
    }

    private func adjustHeight() {
        let minWidth: CGFloat = 190
        let rowHeight: CGFloat = 36
        let padding: CGFloat = 16
        let maxHeight: CGFloat = 400

        let height: CGFloat
        if entries.isEmpty {
            height = 120
        } else {
            let contentHeight = CGFloat(entries.count) * rowHeight + padding * 2
            height = min(maxHeight, max(160, contentHeight))
        }

        var frame = self.frame
        frame.size.height = height
        frame.size.width = minWidth
        setFrame(frame, display: true)
    }

    override func orderOut(_ sender: Any?) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        super.orderOut(sender)
    }

    private func loadEntries() {
        guard let db = (NSApp.delegate as? AppDelegate)?.indexDB else {
            emptyView.isHidden = false
            scrollView.isHidden = true
            return
        }
        
        let maxCount = UserDefaults.standard.integer(forKey: "clipboard.maxCount")
        let limit = maxCount > 0 ? maxCount : 500
        entries = db.getClipboard(limit: limit).map {
            ClipboardEntry(id: $0.id, type: $0.type, content: $0.content, createdAt: $0.createdAt)
        }
        
        // Group by 10
        groups = stride(from: 0, to: entries.count, by: 10).map {
            Array(entries[$0..<min($0 + 10, entries.count)])
        }
        currentGroup = 0
        
        if entries.isEmpty {
            emptyView.isHidden = false
            scrollView.isHidden = true
        } else {
            emptyView.isHidden = true
            scrollView.isHidden = false
            tableView.reloadData()
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func centerOnMouse() {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }

        var x = mouseLoc.x - frame.width / 2
        var y = mouseLoc.y - frame.height

        if x < screenFrame.minX { x = screenFrame.minX + 10 }
        if x + frame.width > screenFrame.maxX { x = screenFrame.maxX - frame.width - 10 }
        if y < screenFrame.minY { y = screenFrame.minY + 10 }

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func rowClicked() {
        pasteSelected()
    }

    private func pasteSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]

        // Write to pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if entry.type == "text" {
            pasteboard.setString(entry.content, forType: .string)
        } else if entry.type == "image" {
            if let image = NSImage(contentsOfFile: entry.content) {
                pasteboard.writeObjects([image])
            }
        }

        orderOut(nil)

        // Activate previous app and simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.activateAndPaste()
        }
    }

    private func activateAndPaste() {
        guard PermissionManager.shared.hasAccessibilityPermission() else {
            // Request permission if not granted
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
        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            orderOut(nil)
        case 36, 76: // Enter
            pasteSelected()
        case 125: // Down
            moveSelection(by: 1)
        case 126: // Up
            moveSelection(by: -1)
        case 123: // Left
            switchGroup(by: -1)
        case 124: // Right
            switchGroup(by: 1)
        default:
            // Number keys 1-9, 0
            if let chars = event.characters, let char = chars.first {
                if char >= "1" && char <= "9" {
                    selectByNumber(Int(char.asciiValue!) - 49) // 1 -> 0
                } else if char == "0" {
                    selectByNumber(9)
                }
            }
        }
    }

    private func moveSelection(by offset: Int) {
        let current = tableView.selectedRow
        let next = max(0, min(entries.count - 1, current + offset))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private func switchGroup(by offset: Int) {
        let newGroup = max(0, min(groups.count - 1, currentGroup + offset))
        if newGroup != currentGroup {
            currentGroup = newGroup
            let startRow = newGroup * 10
            tableView.selectRowIndexes(IndexSet(integer: startRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(startRow)
        }
    }

    private func selectByNumber(_ index: Int) {
        let row = currentGroup * 10 + index
        if row < entries.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            pasteSelected()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - MenuItemView

class MenuItemView: NSView {
    private let title: String
    private let action: Selector

    init(title: String, action: Selector) {
        self.title = title
        self.action = action
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.sizeToFit()
        label.frame = NSRect(x: 16, y: (bounds.height - label.bounds.height) / 2, width: label.bounds.width, height: label.bounds.height)
        addSubview(label)

        let trackingArea = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func mouseDown(with event: NSEvent) {
        _ = (window as? ClipboardPanel)?.perform(action)
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension ClipboardPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let numberInGroup = row % 10 + 1

        let cell = NSTableCellView()

        // Number
        let numberField = NSTextField(frame: NSRect(x: 6, y: 8, width: 20, height: 20))
        numberField.stringValue = "\(numberInGroup)"
        numberField.isEditable = false
        numberField.isBordered = false
        numberField.drawsBackground = false
        numberField.font = .systemFont(ofSize: 12, weight: .medium)
        numberField.textColor = .secondaryLabelColor
        numberField.alignment = .center
        cell.addSubview(numberField)

        // Content
        let contentField = NSTextField(frame: NSRect(x: 28, y: 8, width: tableView.bounds.width - 36, height: 20))
        var content = entry.content
        if entry.type == "text" {
            if content.count > 30 {
                content = String(content.prefix(30)) + "..."
            }
        } else if entry.type == "image" {
            content = "📷 Image"
        }
        contentField.stringValue = content
        contentField.isEditable = false
        contentField.isBordered = false
        contentField.drawsBackground = false
        contentField.font = .systemFont(ofSize: 11)
        contentField.lineBreakMode = .byTruncatingTail
        cell.addSubview(contentField)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ClipboardRowView()
        if row > 0 && row % 10 == 0 {
            rowView.showTopSeparator = true
        }
        return rowView
    }
}

/// Custom row view with optional top separator.
class ClipboardRowView: NSTableRowView {
    var showTopSeparator = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if showTopSeparator {
            let sepRect = NSRect(x: 6, y: bounds.height - 1, width: bounds.width - 12, height: 1)
            NSColor.separatorColor.setFill()
            sepRect.fill()
        }
    }
}