// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

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

    /// Input history for command recall
    private var inputHistory: [String] = []
    private var historyIndex: Int = -1
    private var currentInput: String = ""

    /// Autocomplete suggestions
    private var autocompleteSuggestions: [String] = []
    private var isAutocompleteMode = false

    /// Saved input source for restoration
    private var savedInputSource: TISInputSource?

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

        // Monitor for clicks outside window to auto-hide
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            let clickPoint = event.locationInWindow
            let windowFrame = self.frame
            // If click is outside window, hide it
            if !windowFrame.contains(clickPoint) {
                self.orderOut(nil)
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            
            // Esc - close window
            if event.keyCode == 53 {
                self.orderOut(nil)
                return nil
            }
            
            // Cmd+W - close window
            if event.modifierFlags.contains(.command) && event.keyCode == 13 {
                self.orderOut(nil)
                return nil
            }
            
            // Handle standard editing commands manually for the search field
            if let fieldEditor = self.searchField.currentEditor() {
                // Tab - autocomplete
                if event.keyCode == 48 {
                    self.performAutocomplete()
                    return nil
                }
                
                if event.modifierFlags.contains(.command) {
                    // Cmd+C - copy
                    if event.keyCode == 8 {
                        fieldEditor.copy(nil)
                        return nil
                    }
                    // Cmd+V - paste
                    if event.keyCode == 9 {
                        fieldEditor.paste(nil)
                        return nil
                    }
                    // Cmd+X - cut
                    if event.keyCode == 7 {
                        fieldEditor.cut(nil)
                        return nil
                    }
                    // Cmd+A - select all
                    if event.keyCode == 0 {
                        fieldEditor.selectAll(nil)
                        return nil
                    }
                    // Cmd+Z - undo
                    if event.keyCode == 6 && !event.modifierFlags.contains(.shift) {
                        (fieldEditor as? NSTextView)?.undoManager?.undo()
                        return nil
                    }
                    // Cmd+Shift+Z - redo
                    if event.keyCode == 6 && event.modifierFlags.contains(.shift) {
                        (fieldEditor as? NSTextView)?.undoManager?.redo()
                        return nil
                    }
                }
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

    // MARK: - Autocomplete

    /// Get autocomplete suggestions based on current input
    private func getAutocompleteSuggestions(for input: String) -> [String] {
        guard !input.isEmpty else { return [] }

        var suggestions: [String] = []
        let lowercasedInput = input.lowercased()

        // Plugin keywords
        let pluginKeywords = ["dict", "tr", "calc", "kill", "sleep", "lock", "empty trash", "restart", "shutdown", "logout", "ip", "stock", "convert"]
        for keyword in pluginKeywords {
            if keyword.hasPrefix(lowercasedInput) {
                suggestions.append(keyword)
            }
        }

        // App names
        for app in results {
            let appName = app.name.lowercased()
            if appName.hasPrefix(lowercasedInput) {
                suggestions.append(app.name)
            }
        }

        // Remove duplicates and limit to 10
        return Array(Set(suggestions).sorted()).prefix(10).map { $0 }
    }

    /// Perform autocomplete
    private func performAutocomplete() {
        let currentText = searchField.stringValue
        guard !currentText.isEmpty else { return }

        if autocompleteSuggestions.isEmpty || !isAutocompleteMode {
            // First Tab press - get suggestions
            autocompleteSuggestions = getAutocompleteSuggestions(for: currentText)
            isAutocompleteMode = true
        }

        guard !autocompleteSuggestions.isEmpty else { return }

        // Complete with the first suggestion
        let completion = autocompleteSuggestions[0]
        searchField.stringValue = completion
        searchField.currentEditor()?.selectedRange = NSRange(location: completion.count, length: 0)

        // Update suggestions to show all matches
        filterResults(with: completion)
    }

    // MARK: - Input History

    /// Save current input to history
    private func saveToHistory() {
        let text = searchField.stringValue
        guard !text.isEmpty else { return }

        // Remove if already exists
        inputHistory.removeAll { $0 == text }
        // Add to front
        inputHistory.insert(text, at: 0)
        // Limit history size
        if inputHistory.count > 50 {
            inputHistory = Array(inputHistory.prefix(50))
        }
        historyIndex = -1
    }

    /// Navigate to previous input in history
    private func navigateHistoryUp() {
        guard !inputHistory.isEmpty else { return }

        if historyIndex == -1 {
            // Save current input before navigating
            currentInput = searchField.stringValue
        }

        if historyIndex < inputHistory.count - 1 {
            historyIndex += 1
            searchField.stringValue = inputHistory[historyIndex]
            searchField.currentEditor()?.selectedRange = NSRange(location: searchField.stringValue.count, length: 0)
            filterResults(with: searchField.stringValue)
        }
    }

    /// Navigate to next input in history
    private func navigateHistoryDown() {
        if historyIndex > 0 {
            historyIndex -= 1
            searchField.stringValue = inputHistory[historyIndex]
            searchField.currentEditor()?.selectedRange = NSRange(location: searchField.stringValue.count, length: 0)
            filterResults(with: searchField.stringValue)
        } else if historyIndex == 0 {
            // Return to current input
            historyIndex = -1
            searchField.stringValue = currentInput
            searchField.currentEditor()?.selectedRange = NSRange(location: searchField.stringValue.count, length: 0)
            filterResults(with: searchField.stringValue)
        }
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

    // MARK: - Input Source Management

    /// Save current input source and switch to English
    private func switchToEnglishInput() {
        // Save current input source
        if let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            savedInputSource = currentSource
        }

        // Find English input source
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }

        // Try to find ABC or US keyboard
        for source in inputSources {
            guard let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String

            if sourceIDString.contains("com.apple.keylayout.ABC") ||
               sourceIDString.contains("com.apple.keylayout.US") ||
               sourceIDString == "com.apple.keylayout.ABC" {
                TISSelectInputSource(source)
                break
            }
        }
    }

    /// Restore previously saved input source
    private func restoreInputSource() {
        guard let savedSource = savedInputSource else { return }
        savedInputSource = nil
        TISSelectInputSource(savedSource)
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
        // Don't switch input source here - wait until window has focus

        // Reset search
        searchField.stringValue = ""
        isSearchMode = false
        gridScrollView.isHidden = false
        scrollView.isHidden = true
        previewScrollView.isHidden = true // Hide preview in grid mode
        updateGridView()
        previewTextView.string = ""

        // Reset autocomplete and history
        isAutocompleteMode = false
        autocompleteSuggestions = []
        historyIndex = -1
        currentInput = ""

        // Scroll to top
        if gridView.bounds.height > gridScrollView.bounds.height {
            gridScrollView.contentView.scroll(to: NSPoint(x: 0, y: gridView.bounds.height - gridScrollView.bounds.height))
        }

        // Center on the screen with mouse cursor (multi-monitor support)
        centerOnMouseScreen()

        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(searchField)
        
        // Switch to English input AFTER window has focus
        // Use async to ensure focus is fully transferred
        DispatchQueue.main.async {
            self.switchToEnglishInput()
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
        let y = screenFrame.minY + (screenFrame.height - height) / 2

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
        // Restore input source after window is fully hidden
        DispatchQueue.main.async {
            self.restoreInputSource()
        }
    }

    // MARK: - Focus Handling

    override func resignKey() {
        super.resignKey()
        // Restore input source when window loses key status
        // Use async to ensure it happens after any pending orderOut
        DispatchQueue.main.async {
            self.restoreInputSource()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Actions

    @objc private func searchFieldChanged() {
        // Reset autocomplete mode when user types
        isAutocompleteMode = false
        autocompleteSuggestions = []
        filterResults(with: searchField.stringValue)
    }

    @objc private func tableClicked() {
        // In list mode, just update preview, don't execute
        updatePreview()
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

    private func updateGridView() {
        // Clear existing subviews
        for subview in gridView.subviews {
            subview.removeFromSuperview()
        }

        let itemWidth: CGFloat = 95
        let itemHeight: CGFloat = 95
        let spacing: CGFloat = 10
        let columns = Int(gridView.bounds.width / (itemWidth + spacing))
        let groupHeaderHeight: CGFloat = 24

        // Read grouping preference
        let groupBy = UserDefaults.standard.string(forKey: "launcher.groupBy") ?? "frequency"

        // Group apps
        let groupedApps: [(String, [LaunchItem])]
        if groupBy == "letter" {
            groupedApps = Dictionary(grouping: results) { app -> String in
                let firstChar = app.name.prefix(1).uppercased()
                if firstChar.rangeOfCharacter(from: CharacterSet.letters) != nil {
                    return firstChar
                }
                return "#"
            }.sorted { $0.key < $1.key }
        } else if groupBy == "category" {
            // Group by category (function)
            groupedApps = Dictionary(grouping: results) { app -> String in
                app.category ?? "Other"
            }.sorted { $0.key < $1.key }
        } else {
            // Group by frequency (most used)
            let runningPaths = getRunningAppPaths()
            let sorted = results.sorted { a, b in
                let aRunning = runningPaths.contains(a.path)
                let bRunning = runningPaths.contains(b.path)
                // Running apps first
                if aRunning != bRunning { return aRunning }
                let aFreq = LaunchHistory.shared.count(for: a.path)
                let bFreq = LaunchHistory.shared.count(for: b.path)
                if aFreq != bFreq { return aFreq > bFreq }
                let aDate = LaunchHistory.shared.lastLaunched(for: a.path) ?? .distantPast
                let bDate = LaunchHistory.shared.lastLaunched(for: b.path) ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.name < b.name
            }
            groupedApps = [(L("settings.groupBy.frequency"), sorted)]
        }

        // Calculate total height needed
        var totalHeight: CGFloat = 10 // top padding

        // All apps section - grouped
        for (_, apps) in groupedApps {
            // Only add group header height if there are multiple groups
            if groupedApps.count > 1 {
                totalHeight += groupHeaderHeight // group header
            }
            let rows = Int(ceil(Double(apps.count) / Double(columns)))
            totalHeight += CGFloat(rows) * (itemHeight + spacing)
        }
        totalHeight += 10 // bottom padding

        // Set grid view frame
        let contentHeight = max(gridScrollView.bounds.height, totalHeight)
        gridView.frame = NSRect(x: 0, y: 0, width: gridScrollView.bounds.width, height: contentHeight)

        // Start placing items from top
        var y: CGFloat = contentHeight - 10
        var x: CGFloat = 10

        for (groupName, apps) in groupedApps {
            // Group header - skip if only one group (frequency mode)
            if groupedApps.count > 1 {
                let groupLabel = NSTextField(labelWithString: groupName)
                groupLabel.frame = NSRect(x: 10, y: y - 16, width: 200, height: 16)
                groupLabel.font = .systemFont(ofSize: 13, weight: .bold)
                groupLabel.textColor = .labelColor
                gridView.addSubview(groupLabel)
                y -= groupHeaderHeight
            }

            x = 10
            var index = 0
            for app in apps {
                let itemView = createGridItemView(app: app, size: NSSize(width: itemWidth, height: itemHeight))
                itemView.frame = NSRect(x: x, y: y - itemHeight, width: itemWidth, height: itemHeight)
                gridView.addSubview(itemView)

                index += 1
                x += itemWidth + spacing
                if index % columns == 0 {
                    x = 10
                    y -= itemHeight + spacing
                }
            }

            // Reset for next row if not at start
            if index % columns != 0 {
                y -= itemHeight + spacing
            }
        }
    }

    private func createGridItemView(app: LaunchItem, size: NSSize) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))

        // Icon
        let iconSize: CGFloat = 75
        let imageView = NSImageView(frame: NSRect(
            x: (size.width - iconSize) / 2,
            y: size.height - iconSize - 5,
            width: iconSize,
            height: iconSize
        ))
        imageView.image = app.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(imageView)

        // Name (centered below icon)
        let nameField = NSTextField(wrappingLabelWithString: app.name)
        // Use full width minus small padding
        let nameWidth = size.width - 4
        let nameHeight: CGFloat = 32
        nameField.frame = NSRect(
            x: (size.width - nameWidth) / 2,
            y: -14,
            width: nameWidth,
            height: nameHeight
        )
        nameField.alignment = .center
        nameField.font = .systemFont(ofSize: 12)
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

        // 1. Plugin results (if any) - separate stock plugin results
        var nonStockPluginResults: [LaunchItem] = []
        var stockPluginResults: [LaunchItem] = []
        if let results = PluginManager.shared.dispatch(query) {
            let allPluginResults = results.map { result in
                LaunchItem(
                    name: result.title,
                    path: result.subtitle ?? "",
                    type: .command,
                    category: nil,
                    pluginAction: result.action,
                    pluginIcon: result.icon,
                    detailText: result.detailText
                )
            }
            
            // Check if this is a stock query (starts with "stock" or is a 6-digit code)
            let isStockQuery = query.lowercased().hasPrefix("stock ") || 
                              (query.count == 6 && query.allSatisfy { $0.isNumber })
            
            if isStockQuery {
                stockPluginResults = allPluginResults
            } else {
                nonStockPluginResults = allPluginResults
            }
        }

        // 2. App filtering (always runs)
        let lowered = query.lowercased()
        var appResults: [LaunchItem] = []
        appResults = results.filter { item in
            let name = item.name.lowercased()
            // Direct match: contains
            if name.contains(lowered) { return true }
            // Acronym match: "gc" matches "Google Chrome"
            let acronym = item.name.components(separatedBy: " ")
                .compactMap { $0.first?.lowercased() }
                .joined()
            return acronym.contains(lowered)
        }
        appResults.sort { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            // Running apps boost
            let runningPaths = getRunningAppPaths()
            let aRunning = runningPaths.contains(a.path)
            let bRunning = runningPaths.contains(b.path)
            // Frequency weight
            let aFreq = LaunchHistory.shared.count(for: a.path)
            let bFreq = LaunchHistory.shared.count(for: b.path)
            // Prefix match
            let aPrefix = aName.hasPrefix(lowered)
            let bPrefix = bName.hasPrefix(lowered)
            // Acronym match
            let aAcronym = a.name.components(separatedBy: " ")
                .compactMap { $0.first?.lowercased() }.joined()
            let bAcronym = b.name.components(separatedBy: " ")
                .compactMap { $0.first?.lowercased() }.joined()
            let aAcronymMatch = aAcronym.hasPrefix(lowered)
            let bAcronymMatch = bAcronym.hasPrefix(lowered)
            // Sort: prefix > acronym > running > frequency > name length
            if aPrefix != bPrefix { return aPrefix }
            if aAcronymMatch != bAcronymMatch { return aAcronymMatch }
            if aRunning != bRunning { return aRunning }
            if aFreq != bFreq { return aFreq > bFreq }
            return a.name.count < b.name.count
        }

        var fileResults: [LaunchItem] = []
        if (NSApp.delegate as? AppDelegate)?.isIndexReady == true,
           let db = (NSApp.delegate as? AppDelegate)?.indexDB {
            // Use FTS for direct matches
            let files = db.search(query)
            var fileSet = Set(files.map { $0.path })

            // Add pinyin and fuzzy matches
            let allFiles = db.getAllFiles(limit: 5000)
            for file in allFiles {
                if fileSet.contains(file.path) { continue }

                // Pinyin matching (for Chinese filenames)
                if PinyinConverter.shared.matchesInitials(query: query, text: file.name) ||
                   PinyinConverter.shared.matchesFullPinyin(query: query, text: file.name) {
                    fileSet.insert(file.path)
                    continue
                }

                // Fuzzy matching (e.g., "rdme" -> "readme.md")
                if FuzzyMatcher.shared.matches(query: query, text: file.name) {
                    fileSet.insert(file.path)
                }
            }

            // Re-query to get sorted results, or build results from our set
            let matchedFiles = files + allFiles.filter { fileSet.contains($0.path) && !files.contains(where: { $0.path == $0.path }) }
            fileResults = matchedFiles.prefix(20).map { file in
                LaunchItem(
                    name: file.name,
                    path: file.path,
                    type: .file,
                    category: nil
                )
            }
        }

        // 4. Browser bookmarks
        var bookmarkResults: [LaunchItem] = []
        let bookmarkMatches = BrowserBookmarksManager.shared.search(query)
        bookmarkResults = bookmarkMatches.map { bookmark in
            LaunchItem(
                name: bookmark.title,
                path: bookmark.url,
                type: .bookmark,
                category: nil
            )
        }

        // 5. Browser history
        var historyResults: [LaunchItem] = []
        let historyMatches = BrowserHistoryManager.shared.search(query, limit: 10)
        historyResults = historyMatches.map { history in
            LaunchItem(
                name: history.title.isEmpty ? history.url : history.title,
                path: history.url,
                type: .history,
                category: nil
            )
        }

        // 6. Clipboard history
        var clipboardResults: [LaunchItem] = []
        let clipboardMatches = ClipboardManager.shared.db.search(query, limit: 5)
        clipboardResults = clipboardMatches.filter { $0.type == "text" }.map { item in
            let preview = item.content.count > 50 ? String(item.content.prefix(50)) + "..." : item.content
            return LaunchItem(
                name: preview,
                path: item.content,
                type: .clipboard,
                category: nil
            )
        }

        // 7. Merge: non-stock plugins first, then apps, stock plugins, files, bookmarks, history, clipboard
        merged += nonStockPluginResults
        merged += appResults
        merged += stockPluginResults
        merged += fileResults
        merged += bookmarkResults
        merged += historyResults
        merged += clipboardResults

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
            NSHomeDirectory() + "/Applications",
            // Xcode bundled apps
            "/Applications/Xcode.app/Contents/Applications",
            // Developer tools
            "/Applications/Utilities",
            "/System/Applications/Utilities",
            // Additional system locations
            "/System/Library/CoreServices/Applications"
        ]

        var items: [LaunchItem] = []
        var seenPaths = Set<String>()

        for dir in appDirs {
            scanDirectoryForApps(at: dir, fileManager: fileManager, items: &items, seenPaths: &seenPaths)
        }

        // Filter out ignored apps
        items = items.filter { !IgnoredAppsManager.shared.isIgnored(path: $0.path) }

        // Sort alphabetically
        items.sort { $0.name.lowercased() < $1.name.lowercased() }
        results = items
        filteredResults = items

        // Debug log
        print("[LauncherWindow] Loaded \(items.count) applications")
    }

    /// Get paths of currently running applications.
    private func getRunningAppPaths() -> Set<String> {
        var paths = Set<String>()
        let workspace = NSWorkspace.shared
        for app in workspace.runningApplications {
            if let url = app.bundleURL {
                paths.insert(url.path)
            }
        }
        return paths
    }

    private func scanDirectoryForApps(at path: String, fileManager: FileManager, items: inout [LaunchItem], seenPaths: inout Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            print("[LauncherWindow] Failed to scan: \(path)")
            return
        }

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
                        let category = readAppCategory(path: fullPath)
                        items.append(LaunchItem(name: displayName, path: fullPath, type: .application, category: category))
                    }
                } else {
                    // Recursively scan subdirectories
                    scanDirectoryForApps(at: fullPath, fileManager: fileManager, items: &items, seenPaths: &seenPaths)
                }
            }
        }
    }

    private func readAppCategory(path: String) -> String? {
        let plistPath = path + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let categoryType = plist["LSApplicationCategoryType"] as? String else {
            return nil
        }
        // Convert category type to display name
        return categoryDisplayName(for: categoryType)
    }

    private func categoryDisplayName(for categoryType: String) -> String {
        switch categoryType {
        case "public.app-category.utilities": return "Utilities"
        case "public.app-category.productivity": return "Productivity"
        case "public.app-category.games": return "Games"
        case "public.app-category.entertainment": return "Entertainment"
        case "public.app-category.education": return "Education"
        case "public.app-category.finance": return "Finance"
        case "public.app-category.lifestyle": return "Lifestyle"
        case "public.app-category.medical": return "Medical"
        case "public.app-category.music": return "Music"
        case "public.app-category.news": return "News"
        case "public.app-category.photography": return "Photography"
        case "public.app-category.social-networking": return "Social"
        case "public.app-category.travel": return "Travel"
        case "public.app-category.video": return "Video"
        case "public.app-category.weather": return "Weather"
        case "public.app-category.developer-tools": return "Developer Tools"
        case "public.app-category.graphics-design": return "Graphics & Design"
        case "public.app-category.business": return "Business"
        case "public.app-category.reference": return "Reference"
        case "public.app-category.sports": return "Sports"
        case "public.app-category.healthcare-fitness": return "Health & Fitness"
        default: return "Other"
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
                // In search mode, navigate results
                moveSelection(by: -1)
            } else {
                // In grid mode, navigate history
                navigateHistoryUp()
            }
            return true
        case #selector(NSResponder.moveDown(_:)):
            if isSearchMode {
                // In search mode, navigate results
                moveSelection(by: 1)
            } else {
                // In grid mode, navigate history
                navigateHistoryDown()
            }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if isAutocompleteMode && !autocompleteSuggestions.isEmpty {
                // Confirm autocomplete
                saveToHistory()
                isAutocompleteMode = false
                autocompleteSuggestions = []
            } else if isSearchMode {
                // Execute selected item
                saveToHistory()
                executeSelected()
            }
            return true
        case #selector(NSResponder.insertTab(_:)):
            // Tab autocomplete
            performAutocomplete()
            return true
        default:
            // Let the system handle all other commands (copy, paste, cut, undo, redo, etc.)
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
                if event.modifierFlags.contains(.command) {
                    showSelectedInFinder()
                } else {
                    executeSelected()
                }
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

    private func showSelectedInFinder() {
        guard isSearchMode, !filteredResults.isEmpty else { return }
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredResults.count else { return }
        let item = filteredResults[row]
        hide()
        item.showInFinder()
    }
}
