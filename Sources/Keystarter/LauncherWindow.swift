// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// A borderless, centered, floating window that hosts the launcher UI.
/// Hides automatically when it loses focus.
final class LauncherWindow: NSWindow {

    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var previewScrollView: NSScrollView!
    private var previewTextView: NSTextView!

    /// Data source for the result list.
    private var results: [LaunchItem] = []
    private var filteredResults: [LaunchItem] = []

    init() {
        // Initial frame: centered, fixed size
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 800
        let height: CGFloat = 400
        let x = screenFrame.midX - width / 2
        let y = screenFrame.midY - height / 2 + 100
        let frame = NSRect(x: x, y: y, width: width, height: height)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Window appearance
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        setupUI()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if event.keyCode == 53 { // Esc
                self.hide()
                return nil
            }
            return event
        }

        // Listen for translation completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshResults),
            name: .translationComplete,
            object: nil
        )

        loadApplications()
    }

    @objc private func refreshResults() {
        // Re-filter to pick up async results
        filterResults(with: searchField.stringValue)
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Load appearance settings
        AppearanceSettings.load()

        // Container view with rounded corners
        let container = NSVisualEffectView(frame: contentView!.bounds)
        container.material = AppearanceSettings.material.nsMaterial
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = AppearanceSettings.cornerRadius
        container.layer?.opacity = Float(AppearanceSettings.opacity)
        container.autoresizingMask = [.width, .height]
        contentView = container

        // Search field
        searchField = NSSearchField(frame: NSRect(
            x: 16,
            y: container.bounds.height - 56,
            width: container.bounds.width - 32,
            height: 40
        ))
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.font = .systemFont(ofSize: 20)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        // Listen for every keystroke
        searchField.sendsSearchStringImmediately = true
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.sendsWholeSearchString = false
            cell.sendsSearchStringImmediately = true
        }
        container.addSubview(searchField)

        // Results list (left side)
        let listWidth: CGFloat = 300
        scrollView = NSScrollView(frame: NSRect(
            x: 16,
            y: 16,
            width: listWidth,
            height: container.bounds.height - 80
        ))
        scrollView.autoresizingMask = [.maxXMargin, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 48
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = scrollView.bounds.width
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        // Preview panel (right side)
        previewScrollView = NSScrollView(frame: NSRect(
            x: listWidth + 32,
            y: 16,
            width: container.bounds.width - listWidth - 48,
            height: container.bounds.height - 80
        ))
        previewScrollView.autoresizingMask = [.width, .height]
        previewScrollView.hasVerticalScroller = true
        previewScrollView.drawsBackground = false
        previewScrollView.borderType = .noBorder

        previewTextView = NSTextView(frame: previewScrollView.bounds)
        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.font = .systemFont(ofSize: 14)
        previewTextView.textContainerInset = NSSize(width: 8, height: 8)

        previewScrollView.documentView = previewTextView
        container.addSubview(previewScrollView)
    }

    // MARK: - Show / Hide

    /// Toggle visibility. If visible, hide. If hidden, show and focus.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Reset search
        searchField.stringValue = ""
        filteredResults = results
        tableView.reloadData()
        updatePreview()

        // Center on the screen with mouse cursor (multi-monitor support)
        centerOnMouseScreen()

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(searchField)

        // Select first row
        if !filteredResults.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    /// Center the window on the screen where the mouse cursor is located.
    private func centerOnMouseScreen() {
        let mouseLoc = NSEvent.mouseLocation
        let screens = NSScreen.screens

        // Find the screen containing the mouse
        let targetScreen = screens.first { screen in
            let frame = screen.frame
            return mouseLoc.x >= frame.minX && mouseLoc.x <= frame.maxX &&
                   mouseLoc.y >= frame.minY && mouseLoc.y <= frame.maxY
        } ?? NSScreen.main

        guard let screen = targetScreen else { return }
        let screenFrame = screen.visibleFrame

        let width = AppearanceSettings.windowWidth
        let height = AppearanceSettings.windowHeight
        let x = screenFrame.minX + (screenFrame.width - width) / 2
        let y = screenFrame.minY + (screenFrame.height - height) / 2 + 100

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        orderOut(nil)
    }

    // MARK: - Focus Handling

    override func resignKey() {
        super.resignKey()
        hide()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Actions

    @objc private func searchFieldChanged() {
        filterResults(with: searchField.stringValue)
    }

    @objc private func tableDoubleClicked() {
        executeSelected()
    }

    /// Execute the currently selected result.
    private func executeSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredResults.count else { return }
        let item = filteredResults[row]
        // Record launch history
        LaunchHistory.shared.record(identifier: item.path)
        hide()
        item.execute()
    }

    private func updatePreview() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredResults.count else {
            previewTextView.string = ""
            return
        }

        let item = filteredResults[row]
        if let detail = item.detailText, !detail.isEmpty {
            previewTextView.string = detail
        } else {
            previewTextView.string = item.name
        }
    }

    // MARK: - Filtering

    private func filterResults(with query: String) {
        var merged: [LaunchItem] = []

        // 1. Plugin results (if any)
        if let pluginResults = PluginManager.shared.dispatch(query) {
            merged += pluginResults.map { result in
                LaunchItem(
                    name: result.title,
                    path: result.subtitle ?? "",
                    type: .command,
                    pluginAction: result.action,
                    pluginIcon: result.icon,
                    detailText: result.detailText
                )
            }
        }

        // 2. App filtering (always runs)
        let lowered = query.lowercased()
        var appResults: [LaunchItem] = []
        if query.isEmpty {
            appResults = results
            // Sort by frequency when showing all
            appResults.sort { a, b in
                let aCount = LaunchHistory.shared.count(for: a.path)
                let bCount = LaunchHistory.shared.count(for: b.path)
                if aCount != bCount { return aCount > bCount }
                return a.name.lowercased() < b.name.lowercased()
            }
        } else {
            appResults = results.filter { item in
                item.name.lowercased().contains(lowered)
            }
            appResults.sort { a, b in
                // Frequency weight
                let aFreq = LaunchHistory.shared.count(for: a.path)
                let bFreq = LaunchHistory.shared.count(for: b.path)
                // Prefix match
                let aPrefix = a.name.lowercased().hasPrefix(lowered)
                let bPrefix = b.name.lowercased().hasPrefix(lowered)
                // Sort: prefix > frequency > name length
                if aPrefix != bPrefix { return aPrefix }
                if aFreq != bFreq { return aFreq > bFreq }
                return a.name.count < b.name.count
            }
        }

        var fileResults: [LaunchItem] = []
        if !query.isEmpty, let db = (NSApp.delegate as? AppDelegate)?.indexDB {
            let files = db.search(query)
            fileResults = files.map { file in
                LaunchItem(
                    name: file.name,
                    path: file.path,
                    type: .file
                )
            }
        }

        // 3. Merge: plugin results first, then apps
        merged += appResults
        merged += fileResults

        filteredResults = merged
        tableView.reloadData()
        if !filteredResults.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updatePreview()
    }

    // MARK: - Load Applications

    private func loadApplications() {
        let fileManager = FileManager.default
        let appDirs = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]

        var items: [LaunchItem] = []

        for dir in appDirs {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for name in contents where name.hasSuffix(".app") {
                let path = dir + "/" + name
                let displayName = (name as NSString).deletingPathExtension
                items.append(LaunchItem(name: displayName, path: path, type: .application))
            }
        }

        // Sort alphabetically
        items.sort { $0.name.lowercased() < $1.name.lowercased() }
        results = items
        filteredResults = items
    }
}

// MARK: - NSSearchFieldDelegate

extension LauncherWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        filterResults(with: searchField.stringValue)
    }

    /// Handle keyboard shortcuts while search field is focused
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            executeSelected()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension LauncherWindow: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredResults.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filteredResults[row]

        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("cell")

        // Icon
        let imageView = NSImageView(frame: NSRect(x: 8, y: 8, width: 32, height: 32))
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        cell.addSubview(imageView)

        // Title
        let titleField = NSTextField(frame: NSRect(x: 48, y: 26, width: tableView.bounds.width - 64, height: 18))
        titleField.stringValue = item.name
        titleField.isEditable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        cell.addSubview(titleField)

        // Subtitle
        if !item.path.isEmpty && item.type == .command {
            let subtitleField = NSTextField(frame: NSRect(x: 48, y: 6, width: tableView.bounds.width - 64, height: 18))
            subtitleField.stringValue = item.path
            subtitleField.isEditable = false
            subtitleField.isBordered = false
            subtitleField.drawsBackground = false
            subtitleField.font = .systemFont(ofSize: 12)
            subtitleField.textColor = .secondaryLabelColor
            subtitleField.lineBreakMode = .byTruncatingTail
            cell.addSubview(subtitleField)
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }
}

// MARK: - Keyboard Handling

extension LauncherWindow {
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            hide()
        case 36, 76: // Enter / Return
            executeSelected()
        case 125: // Down arrow
            moveSelection(by: 1)
        case 126: // Up arrow
            moveSelection(by: -1)
        default:
            super.keyDown(with: event)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredResults.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(filteredResults.count - 1, current + offset))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}