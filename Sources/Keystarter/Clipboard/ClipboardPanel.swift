// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

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
    private var entries: [ClipboardEntry] = []
    private var groups: [[ClipboardEntry]] = []
    private var currentGroup: Int = 0
    private var previousApp: NSRunningApplication?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = true

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

        scrollView = NSScrollView(frame: container.bounds.insetBy(dx: 8, dy: 8))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 40
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

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        loadEntries()
        centerOnMouse()
        previousApp = NSWorkspace.shared.frontmostApplication
        makeKeyAndOrderFront(nil)
    }

    private func loadEntries() {
        guard let db = (NSApp.delegate as? AppDelegate)?.indexDB else { return }
        entries = db.getClipboard(limit: 30).map {
            ClipboardEntry(id: $0.id, type: $0.type, content: $0.content, createdAt: $0.createdAt)
        }
        // Group by 10
        groups = stride(from: 0, to: entries.count, by: 10).map {
            Array(entries[$0..<min($0 + 10, entries.count)])
        }
        currentGroup = 0
        tableView.reloadData()
        if !entries.isEmpty {
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
        let numberField = NSTextField(frame: NSRect(x: 8, y: 10, width: 24, height: 20))
        numberField.stringValue = "\(numberInGroup)"
        numberField.isEditable = false
        numberField.isBordered = false
        numberField.drawsBackground = false
        numberField.font = .systemFont(ofSize: 14, weight: .medium)
        numberField.textColor = .secondaryLabelColor
        numberField.alignment = .center
        cell.addSubview(numberField)

        // Content
        let contentField = NSTextField(frame: NSRect(x: 36, y: 10, width: tableView.bounds.width - 52, height: 20))
        var content = entry.content
        if entry.type == "text" {
            // Truncate text
            if content.count > 50 {
                content = String(content.prefix(50)) + "..."
            }
        } else if entry.type == "image" {
            content = "📷 Image"
        }
        contentField.stringValue = content
        contentField.isEditable = false
        contentField.isBordered = false
        contentField.drawsBackground = false
        contentField.font = .systemFont(ofSize: 13)
        contentField.lineBreakMode = .byTruncatingTail
        cell.addSubview(contentField)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ClipboardRowView()
        // Add separator between groups
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
            let sepRect = NSRect(x: 8, y: bounds.height - 1, width: bounds.width - 16, height: 1)
            NSColor.separatorColor.setFill()
            sepRect.fill()
        }
    }
}