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
    private var gridView: NSView!
    private var gridScrollView: NSScrollView!
    private var isSearchMode = false

    /// Data source for the result list.
    private var results: [LaunchItem] = []
    private var filteredResults: [LaunchItem] = []
    private var recentApps: [LaunchItem] = []

    init() {
        // Initial frame: centered, fixed size
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 800
        let height: CGFloat = screenFrame.height * 0.6
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

    @objc private func openSettings() {
        hide()
        (NSApp.delegate as? AppDelegate)?.showSettings()
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
            width: container.bounds.width - 64,
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

        // Settings button (gear icon)
        let settingsButton = NSButton(frame: NSRect(
            x: container.bounds.width - 48,
            y: container.bounds.height - 52,
            width: 32,
            height: 32
        ))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.bezelStyle = .regularSquare
        settingsButton.isBordered = false
        settingsButton.alphaValue = 0.5
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        container.addSubview(settingsButton)

        // Grid view (default view)
        setupGridView(container: container)

        // List view (search results)
        setupListView(container: container)

        // Preview panel (right side)
        previewScrollView = NSScrollView(frame: NSRect(
            x: 500,
            y: 16,
            width: container.bounds.width - 516,
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

    private func setupGridView(container: NSView) {
        gridScrollView = NSScrollView(frame: NSRect(
            x: 16,
            y: 16,
            width: container.bounds.width - 32,
            height: container.bounds.height - 80
        ))
        gridScrollView.autoresizingMask = [.width, .height]
        gridScrollView.hasVerticalScroller = true
        gridScrollView.drawsBackground = false
        gridScrollView.borderType = .noBorder

        gridView = NSView(frame: gridScrollView.bounds)
        gridScrollView.documentView = gridView
        container.addSubview(gridScrollView)
    }

    private func setupListView(container: NSView) {
        scrollView = NSScrollView(frame: NSRect(
            x: 16,
            y: 16,
            width: container.bounds.width - 320,
            height: container.bounds.height - 80
        ))
        scrollView.autoresizingMask = [.maxXMargin, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.isHidden = true

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 48
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = scrollView.bounds.width
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        container.addSubview(scrollView)
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
        isSearchMode = false
        gridScrollView.isHidden = false
        scrollView.isHidden = true
        previewScrollView.isHidden = true // Hide preview in grid mode
        loadRecentApps()
        updateGridView()
        previewTextView.string = ""

        // Scroll to top
        if gridView.bounds.height > gridScrollView.bounds.height {
            gridScrollView.contentView.scroll(to: NSPoint(x: 0, y: gridView.bounds.height - gridScrollView.bounds.height))
        }

        // Center on the screen with mouse cursor (multi-monitor support)
        centerOnMouseScreen()

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(searchField)
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

    @objc private func tableClicked() {
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

    private func executeItem(_ item: LaunchItem) {
        LaunchHistory.shared.record(identifier: item.path)
        hide()
        item.execute()
    }

    private func updatePreview() {
        if isSearchMode {
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
        } else {
            previewTextView.string = ""
        }
    }

    // MARK: - Grid View

    private func loadRecentApps() {
        // Get top 8 most frequently used apps
        let topItems = LaunchHistory.shared.topIdentifiers(limit: 8)
        recentApps = []
        for (path, _) in topItems {
            if let app = results.first(where: { $0.path == path }) {
                recentApps.append(app)
            }
        }
    }

    private func updateGridView() {
        // Clear existing subviews
        for subview in gridView.subviews {
            subview.removeFromSuperview()
        }

        let itemWidth: CGFloat = 110
        let itemHeight: CGFloat = 130
        let spacing: CGFloat = 20
        let columns = Int(gridView.bounds.width / (itemWidth + spacing))

        // Calculate total height needed
        var totalHeight: CGFloat = 20 // top padding

        // Recent apps section
        if !recentApps.isEmpty {
            totalHeight += 20 // label height
            let recentRows = Int(ceil(Double(recentApps.count) / Double(columns)))
            totalHeight += CGFloat(recentRows) * (itemHeight + spacing)
            totalHeight += 30 // separator and spacing
        }

        // All apps section - show all apps
        totalHeight += 20 // label height
        let allAppsCount = results.count
        let allRows = Int(ceil(Double(allAppsCount) / Double(columns)))
        totalHeight += CGFloat(allRows) * (itemHeight + spacing)
        totalHeight += 20 // bottom padding

        // Set grid view frame
        let contentHeight = max(gridScrollView.bounds.height, totalHeight)
        gridView.frame = NSRect(x: 0, y: 0, width: gridScrollView.bounds.width, height: contentHeight)

        // Start placing items from top
        var y: CGFloat = contentHeight - 20
        var x: CGFloat = 20
        var index = 0

        // Recent apps section
        if !recentApps.isEmpty {
            // Label for recent apps
            let recentLabel = NSTextField(labelWithString: "Recent")
            recentLabel.frame = NSRect(x: 20, y: y - 16, width: 100, height: 16)
            recentLabel.font = .systemFont(ofSize: 12, weight: .medium)
            recentLabel.textColor = .secondaryLabelColor
            gridView.addSubview(recentLabel)
            y -= 20

            for app in recentApps {
                let itemView = createGridItemView(app: app, size: NSSize(width: itemWidth, height: itemHeight))
                itemView.frame = NSRect(x: x, y: y - itemHeight, width: itemWidth, height: itemHeight)
                gridView.addSubview(itemView)

                index += 1
                x += itemWidth + spacing
                if index % columns == 0 {
                    x = 20
                    y -= itemHeight + spacing
                }
            }

            // Reset for next row if not at start
            if index % columns != 0 {
                y -= itemHeight + spacing
            }

            // Separator line
            y -= 10
            let separator = NSView(frame: NSRect(x: 20, y: y, width: gridView.bounds.width - 40, height: 1))
            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor
            gridView.addSubview(separator)
            y -= 20
        }

        // All apps section
        let allLabel = NSTextField(labelWithString: "All Apps")
        allLabel.frame = NSRect(x: 20, y: y - 16, width: 100, height: 16)
        allLabel.font = .systemFont(ofSize: 12, weight: .medium)
        allLabel.textColor = .secondaryLabelColor
        gridView.addSubview(allLabel)
        y -= 20

        x = 20
        index = 0
        for app in results { // Show all apps
            let itemView = createGridItemView(app: app, size: NSSize(width: itemWidth, height: itemHeight))
            itemView.frame = NSRect(x: x, y: y - itemHeight, width: itemWidth, height: itemHeight)
            gridView.addSubview(itemView)

            index += 1
            x += itemWidth + spacing
            if index % columns == 0 {
                x = 20
                y -= itemHeight + spacing
            }
        }
    }

    private func createGridItemView(app: LaunchItem, size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))

        // Icon - larger size
        let iconSize: CGFloat = 80
        let imageView = NSImageView(frame: NSRect(
            x: (size.width - iconSize) / 2,
            y: size.height - iconSize - 10,
            width: iconSize,
            height: iconSize
        ))
        imageView.image = app.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(imageView)

        // Name - larger font
        let nameField = NSTextField(labelWithString: app.name)
        nameField.frame = NSRect(x: 4, y: 0, width: size.width - 8, height: 40)
        nameField.alignment = .center
        nameField.font = .systemFont(ofSize: 13)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 2
        view.addSubview(nameField)

        // Make clickable
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(gridItemClicked(_:)))
        view.addGestureRecognizer(clickGesture)
        view.identifier = NSUserInterfaceItemIdentifier(app.path)

        return view
    }

    @objc private func gridItemClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view,
              let path = view.identifier?.rawValue,
              let app = results.first(where: { $0.path == path }) else { return }
        executeItem(app)
    }

    // MARK: - Filtering

    private func filterResults(with query: String) {
        if query.isEmpty {
            isSearchMode = false
            gridScrollView.isHidden = false
            scrollView.isHidden = true
            previewScrollView.isHidden = true // Hide preview in grid mode
            updateGridView()
            previewTextView.string = ""
            return
        }

        isSearchMode = true
        gridScrollView.isHidden = true
        scrollView.isHidden = false
        previewScrollView.isHidden = false // Show preview in search mode

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

        var fileResults: [LaunchItem] = []
        if let db = (NSApp.delegate as? AppDelegate)?.indexDB {
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
        var seenPaths = Set<String>()

        for dir in appDirs {
            scanDirectoryForApps(at: dir, fileManager: fileManager, items: &items, seenPaths: &seenPaths)
        }

        // Sort alphabetically
        items.sort { $0.name.lowercased() < $1.name.lowercased() }
        results = items
        filteredResults = items
    }

    private func scanDirectoryForApps(at path: String, fileManager: FileManager, items: inout [LaunchItem], seenPaths: inout Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else { return }

        for name in contents {
            // Skip hidden files and directories
            if name.hasPrefix(".") { continue }

            let fullPath = path + "/" + name
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                // If it's a .app bundle, add it
                if name.hasSuffix(".app") {
                    if !seenPaths.contains(fullPath) {
                        seenPaths.insert(fullPath)
                        let displayName = (name as NSString).deletingPathExtension
                        items.append(LaunchItem(name: displayName, path: fullPath, type: .application))
                    }
                } else {
                    // Recursively scan subdirectories
                    scanDirectoryForApps(at: fullPath, fileManager: fileManager, items: &items, seenPaths: &seenPaths)
                }
            }
        }
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
            if isSearchMode {
                moveSelection(by: -1)
            }
            return true
        case #selector(NSResponder.moveDown(_:)):
            if isSearchMode {
                moveSelection(by: 1)
            }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if isSearchMode {
                executeSelected()
            }
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
            if isSearchMode {
                executeSelected()
            }
        case 125: // Down arrow
            if isSearchMode {
                moveSelection(by: 1)
            }
        case 126: // Up arrow
            if isSearchMode {
                moveSelection(by: -1)
            }
        default:
            super.keyDown(with: event)
        }
    }

    private func moveSelection(by offset: Int) {
        guard isSearchMode, !filteredResults.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(filteredResults.count - 1, current + offset))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}
