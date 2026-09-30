// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon
import UniformTypeIdentifiers

/// Settings window with tabs for configuration.
final class SettingsWindow: NSWindow {

    private var tabView: NSTabView!
    private var generalTab: NSView!
    private var monitorTab: NSView!
    private var clipboardTab: NSView!
    private var indexTab: NSView!
    private var contentIndexTab: NSView!
    private var advancedTab: NSView!
    private var aboutTab: NSView!
    private var hotkeyRecorder: HotkeyRecorderButton!
    private var dirsTableView: NSTableView!
    private var ignoredTableView: NSTableView!
    private var extTableView: NSTableView!
    private var dirs: [String] = []
    private var ignoredDirs: [String] = []
    private var contentExts: [String] = []

    // Layout constants
    private let labelWidth: CGFloat = 120
    private let controlWidth: CGFloat = 200
    private let rowSpacing: CGFloat = 16
    private let viewWidth: CGFloat = 560

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 600
        let height: CGFloat = 580
        let x = screenFrame.midX - width / 2
        let y = screenFrame.midY - height / 2
        let frame = NSRect(x: x, y: y, width: width, height: height)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Keystarter Settings"
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 600, height: 500)

        setupUI()
        setupKeyHandlers()
    }

    private func setupUI() {
        tabView = NSTabView(frame: contentView!.bounds.insetBy(dx: 10, dy: 10))
        tabView.autoresizingMask = [.width, .height]

        generalTab = createGeneralTab()
        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = L("settings.tab.general")
        generalItem.view = generalTab
        tabView.addTabViewItem(generalItem)

        monitorTab = createMonitorTab()
        let monitorItem = NSTabViewItem(identifier: "monitor")
        monitorItem.label = L("settings.tab.monitor")
        monitorItem.view = monitorTab
        tabView.addTabViewItem(monitorItem)

        clipboardTab = createClipboardTab()
        let clipboardItem = NSTabViewItem(identifier: "clipboard")
        clipboardItem.label = L("settings.tab.clipboard")
        clipboardItem.view = clipboardTab
        tabView.addTabViewItem(clipboardItem)

        indexTab = createIndexTab()
        let indexItem = NSTabViewItem(identifier: "index")
        indexItem.label = L("settings.tab.index")
        indexItem.view = indexTab
        tabView.addTabViewItem(indexItem)

        contentIndexTab = createContentIndexTab()
        let contentIndexItem = NSTabViewItem(identifier: "contentIndex")
        contentIndexItem.label = L("settings.tab.contentIndex")
        contentIndexItem.view = contentIndexTab
        tabView.addTabViewItem(contentIndexItem)

        advancedTab = createAdvancedTab()
        let advancedItem = NSTabViewItem(identifier: "advanced")
        advancedItem.label = L("settings.tab.advanced")
        advancedItem.view = advancedTab
        tabView.addTabViewItem(advancedItem)

        aboutTab = createAboutTab()
        let aboutItem = NSTabViewItem(identifier: "about")
        aboutItem.label = L("settings.tab.about")
        aboutItem.view = aboutTab
        tabView.addTabViewItem(aboutItem)

        contentView?.addSubview(tabView)
    }

    // MARK: - Layout Helpers

    /// Wrap content in a top-aligned container so the stack starts at the top.
    private func wrapInTopAlignedContainer(_ stack: NSStackView) -> NSView {
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])
        return container
    }

    /// Build a row: right-aligned label on the left, control on the right.
    private func makeRow(label: String, control: NSView) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [labelField, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    /// Build a vertical stack with consistent spacing.
    private func makeVerticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = rowSpacing
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    // MARK: - General Tab

    private func createGeneralTab() -> NSView {
        let stack = makeVerticalStack()

        // Row: Language
        let languagePopup = NSPopUpButton()
        for language in LocalizationManager.Language.allCases {
            languagePopup.addItem(withTitle: language.displayName)
        }
        languagePopup.selectItem(withTitle: LocalizationManager.shared.currentLanguage.displayName)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        stack.addArrangedSubview(makeRow(label: L("settings.language"), control: languagePopup))

        // Row: Hotkey
        hotkeyRecorder = HotkeyRecorderButton()
        hotkeyRecorder.onKeyRecorded = { [weak self] recorder in
            self?.hotkeyChanged(recorder: recorder)
        }
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkey.keyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkey.modifiers")
        if savedKeyCode > 0 {
            hotkeyRecorder.setShortcut(keyCode: UInt16(savedKeyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(savedModifiers)))
        } else {
            hotkeyRecorder.setShortcut(keyCode: UInt16(49), modifiers: .command)
        }
        stack.addArrangedSubview(makeRow(label: L("settings.hotkey"), control: hotkeyRecorder))

        // Row: Status Bar
        let statusBarPopup = NSPopUpButton()
        statusBarPopup.addItem(withTitle: L("settings.statusbar.system"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.light"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.dark"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.hidden"))
        let savedTheme = UserDefaults.standard.string(forKey: "statusBar.theme") ?? "system"
        statusBarPopup.selectItem(withTitle: themeName(for: savedTheme))
        statusBarPopup.target = self
        statusBarPopup.action = #selector(statusBarThemeChanged(_:))
        stack.addArrangedSubview(makeRow(label: L("settings.statusbar"), control: statusBarPopup))

        // Row: Corner Radius
        let radiusSlider = NSSlider(value: Double(AppearanceSettings.cornerRadius), minValue: 0, maxValue: 24, target: self, action: #selector(radiusChanged(_:)))
        radiusSlider.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        let radiusValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.cornerRadius))")
        radiusValue.identifier = NSUserInterfaceItemIdentifier("radiusValue")
        radiusValue.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let radiusRow = NSStackView(views: [radiusSlider, radiusValue])
        radiusRow.orientation = .horizontal
        radiusRow.spacing = 8
        radiusRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: L("settings.cornerRadius"), control: radiusRow))

        // Row: Opacity
        let opacitySlider = NSSlider(value: Double(AppearanceSettings.opacity), minValue: 0.5, maxValue: 1.0, target: self, action: #selector(opacityChanged(_:)))
        opacitySlider.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        let opacityValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.opacity * 100))%")
        opacityValue.identifier = NSUserInterfaceItemIdentifier("opacityValue")
        opacityValue.widthAnchor.constraint(equalToConstant: 50).isActive = true

        let opacityRow = NSStackView(views: [opacitySlider, opacityValue])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 8
        opacityRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: L("settings.opacity"), control: opacityRow))

        // Row: Group By
        let groupByPopup = NSPopUpButton()
        groupByPopup.addItem(withTitle: L("settings.groupBy.frequency"))
        groupByPopup.addItem(withTitle: L("settings.groupBy.category"))
        groupByPopup.addItem(withTitle: L("settings.groupBy.letter"))
        let savedGroupBy = UserDefaults.standard.string(forKey: "launcher.groupBy") ?? "frequency"
        let selectedTitle: String
        switch savedGroupBy {
        case "letter": selectedTitle = L("settings.groupBy.letter")
        case "category": selectedTitle = L("settings.groupBy.category")
        default: selectedTitle = L("settings.groupBy.frequency")
        }
        groupByPopup.selectItem(withTitle: selectedTitle)
        groupByPopup.target = self
        groupByPopup.action = #selector(groupByChanged(_:))
        stack.addArrangedSubview(makeRow(label: L("settings.groupBy"), control: groupByPopup))

        // Row: Start at Login
        let loginCheckbox = NSButton(checkboxWithTitle: L("settings.startAtLogin.checkbox"), target: self, action: #selector(loginItemChanged(_:)))
        loginCheckbox.state = UserDefaults.standard.bool(forKey: "startAtLogin") ? .on : .off
        stack.addArrangedSubview(makeRow(label: L("settings.startAtLogin"), control: loginCheckbox))

        // Row: Dock Icon
        let dockIconCheckbox = NSButton(checkboxWithTitle: L("settings.dockIcon.checkbox"), target: self, action: #selector(dockIconChanged(_:)))
        dockIconCheckbox.state = UserDefaults.standard.bool(forKey: "showDockIcon") ? .on : .off
        stack.addArrangedSubview(makeRow(label: L("settings.dockIcon"), control: dockIconCheckbox))

        // Row: Update
        let updateFrequencyPopup = NSPopUpButton()
        for frequency in UpdateManager.CheckFrequency.allCases {
            updateFrequencyPopup.addItem(withTitle: frequency.displayName)
        }
        updateFrequencyPopup.selectItem(withTitle: UpdateManager.shared.checkFrequency.displayName)
        updateFrequencyPopup.target = self
        updateFrequencyPopup.action = #selector(updateFrequencyChanged(_:))
        updateFrequencyPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let checkNowButton = NSButton(title: L("settings.update.checkNow"), target: self, action: #selector(checkForUpdatesNow))
        checkNowButton.bezelStyle = .rounded

        let updateRow = NSStackView(views: [updateFrequencyPopup, checkNowButton])
        updateRow.orientation = .horizontal
        updateRow.spacing = 12
        updateRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: L("settings.update.frequency"), control: updateRow))

        // Row: Permissions
        let permissionsButton = NSButton(title: L("settings.permissions"), target: self, action: #selector(checkPermissions))
        permissionsButton.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: permissionsButton))

        // Section: Log
        let logLabel = NSTextField(labelWithString: L("settings.log"))
        logLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(logLabel)

        // Row: Enable Launcher Log
        let launcherLogCheckbox = NSButton(checkboxWithTitle: L("settings.launcher.log.enable"), target: self, action: #selector(launcherLogChanged(_:)))
        launcherLogCheckbox.state = LogSettings.shared.launcherLogEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: launcherLogCheckbox))

        // Log path
        let launcherLogPath = NSTextField()
        launcherLogPath.stringValue = LogSettings.shared.launcherLogPath
        launcherLogPath.isEditable = false
        launcherLogPath.isBezeled = true
        launcherLogPath.bezelStyle = .roundedBezel
        launcherLogPath.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(makeRow(label: L("settings.log.path"), control: launcherLogPath))

        return wrapInTopAlignedContainer(stack)
    }

    // MARK: - Monitor Tab

    private func createMonitorTab() -> NSView {
        let stack = makeVerticalStack()

        // Section: Status Bar Modules
        let modulesLabel = NSTextField(labelWithString: L("settings.monitor.modules"))
        modulesLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(modulesLabel)

        // Row: CPU Module
        let cpuCheckbox = NSButton(checkboxWithTitle: L("status.cpu.displayName"), target: self, action: #selector(cpuModuleChanged(_:)))
        cpuCheckbox.state = UserDefaults.standard.bool(forKey: "status.cpu.enabled") ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: cpuCheckbox))

        // Row: Memory Module
        let memoryCheckbox = NSButton(checkboxWithTitle: L("status.memory.displayName"), target: self, action: #selector(memoryModuleChanged(_:)))
        memoryCheckbox.state = UserDefaults.standard.bool(forKey: "status.memory.enabled") ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: memoryCheckbox))

        // Row: Network Module
        let networkCheckbox = NSButton(checkboxWithTitle: L("status.network.displayName"), target: self, action: #selector(networkModuleChanged(_:)))
        networkCheckbox.state = UserDefaults.standard.bool(forKey: "status.network.enabled") ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: networkCheckbox))

        // Row: Disk Module
        let diskCheckbox = NSButton(checkboxWithTitle: L("status.disk.displayName"), target: self, action: #selector(diskModuleChanged(_:)))
        diskCheckbox.state = UserDefaults.standard.bool(forKey: "status.disk.enabled") ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: diskCheckbox))

        // Row: GPU Module
        let gpuCheckbox = NSButton(checkboxWithTitle: L("status.gpu.displayName"), target: self, action: #selector(gpuModuleChanged(_:)))
        gpuCheckbox.state = UserDefaults.standard.bool(forKey: "status.gpu.enabled") ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: gpuCheckbox))

        // Row: Sensor Module
        let sensorCheckbox = NSButton(checkboxWithTitle: L("status.sensor.displayName"), target: self, action: #selector(sensorModuleChanged(_:)))
        sensorCheckbox.state = UserDefaults.standard.bool(forKey: "status.sensor.enabled") ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: sensorCheckbox))

        // Section: Log
        let logLabel = NSTextField(labelWithString: L("settings.log"))
        logLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(logLabel)

        // Row: Enable Monitor Log
        let monitorLogCheckbox = NSButton(checkboxWithTitle: L("settings.monitor.log.enable"), target: self, action: #selector(monitorLogChanged(_:)))
        monitorLogCheckbox.state = LogSettings.shared.monitorLogEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: monitorLogCheckbox))

        // Log path
        let monitorLogPath = NSTextField()
        monitorLogPath.stringValue = LogSettings.shared.monitorLogPath
        monitorLogPath.isEditable = false
        monitorLogPath.isBezeled = true
        monitorLogPath.bezelStyle = .roundedBezel
        monitorLogPath.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(makeRow(label: L("settings.log.path"), control: monitorLogPath))

        return wrapInTopAlignedContainer(stack)
    }

    // MARK: - Clipboard Tab

    private func createClipboardTab() -> NSView {
        let stack = makeVerticalStack()

        // Row: Hotkey
        let clipboardHotkeyRecorder = HotkeyRecorderButton()
        clipboardHotkeyRecorder.onKeyRecorded = { [weak self] recorder in
            self?.clipboardHotkeyChanged(recorder: recorder)
        }
        let savedKeyCode = UserDefaults.standard.integer(forKey: "clipboard.hotkey.keyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "clipboard.hotkey.modifiers")
        if savedKeyCode > 0 {
            clipboardHotkeyRecorder.setShortcut(keyCode: UInt16(savedKeyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(savedModifiers)))
        } else {
            clipboardHotkeyRecorder.setShortcut(keyCode: UInt16(9), modifiers: [.command, .shift])
        }
        stack.addArrangedSubview(makeRow(label: L("settings.clipboard.hotkey"), control: clipboardHotkeyRecorder))

        // Row: Max Count
        let maxCountField = NSTextField()
        let currentMaxCount = UserDefaults.standard.integer(forKey: "clipboard.maxCount") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxCount") : 500
        maxCountField.stringValue = String(currentMaxCount)
        maxCountField.target = self
        maxCountField.action = #selector(clipboardMaxCountChanged(_:))
        maxCountField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(makeRow(label: L("settings.clipboard.maxCount"), control: maxCountField))

        // Row: Max Days
        let maxDaysField = NSTextField()
        maxDaysField.stringValue = String(UserDefaults.standard.integer(forKey: "clipboard.maxDays") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxDays") : 30)
        maxDaysField.target = self
        maxDaysField.action = #selector(clipboardMaxDaysChanged(_:))
        maxDaysField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(makeRow(label: L("settings.clipboard.maxDays"), control: maxDaysField))

        // Row: Clear
        let clearButton = NSButton(title: L("settings.clipboard.clear"), target: self, action: #selector(clearClipboardHistory))
        clearButton.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: clearButton))

        // Section: Log
        let logLabel = NSTextField(labelWithString: L("settings.log"))
        logLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(logLabel)

        // Row: Enable Clipboard Log
        let clipboardLogCheckbox = NSButton(checkboxWithTitle: L("settings.clipboard.log.enable"), target: self, action: #selector(clipboardLogChanged(_:)))
        clipboardLogCheckbox.state = LogSettings.shared.clipboardLogEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: clipboardLogCheckbox))

        // Log path
        let clipboardLogPath = NSTextField()
        clipboardLogPath.stringValue = LogSettings.shared.clipboardLogPath
        clipboardLogPath.isEditable = false
        clipboardLogPath.isBezeled = true
        clipboardLogPath.bezelStyle = .roundedBezel
        clipboardLogPath.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(makeRow(label: L("settings.log.path"), control: clipboardLogPath))

        return wrapInTopAlignedContainer(stack)
    }

    // MARK: - Index Tab

    private func createIndexTab() -> NSView {
        let stack = makeVerticalStack()

        // Index directories
        let dirsLabel = NSTextField(labelWithString: L("settings.index.directories"))
        stack.addArrangedSubview(dirsLabel)

        // Load saved directories
        dirs = UserDefaults.standard.stringArray(forKey: "index.directories") ?? ["~/Desktop", "~/Documents"]

        let dirsScrollView = NSScrollView()
        dirsScrollView.hasVerticalScroller = true
        dirsScrollView.borderType = .bezelBorder
        dirsScrollView.translatesAutoresizingMaskIntoConstraints = false
        dirsScrollView.widthAnchor.constraint(equalToConstant: 400).isActive = true
        dirsScrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        dirsTableView = NSTableView()
        dirsTableView.identifier = NSUserInterfaceItemIdentifier("dirsTable")
        dirsTableView.headerView = nil
        let dirsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        dirsColumn.width = 380
        dirsTableView.addTableColumn(dirsColumn)
        dirsTableView.delegate = self
        dirsTableView.dataSource = self
        dirsScrollView.documentView = dirsTableView
        stack.addArrangedSubview(dirsScrollView)

        // Dirs buttons
        let addDirButton = NSButton(title: L("settings.index.add"), target: self, action: #selector(addIndexDirectory))
        addDirButton.bezelStyle = .rounded
        let removeDirButton = NSButton(title: L("settings.index.remove"), target: self, action: #selector(removeIndexDirectory))
        removeDirButton.bezelStyle = .rounded

        let dirsButtonRow = NSStackView(views: [addDirButton, removeDirButton])
        dirsButtonRow.orientation = .horizontal
        dirsButtonRow.spacing = 12
        dirsButtonRow.alignment = .centerY
        stack.addArrangedSubview(dirsButtonRow)

        // Ignored directories
        let ignoredLabel = NSTextField(labelWithString: L("settings.index.ignored"))
        stack.addArrangedSubview(ignoredLabel)

        // Load saved ignored directories
        ignoredDirs = UserDefaults.standard.stringArray(forKey: "index.ignoredDirs") ?? [
            "node_modules", "target", ".git", "Library", "DerivedData", "Pods", ".venv", "build", "dist"
        ]

        let ignoredScrollView = NSScrollView()
        ignoredScrollView.hasVerticalScroller = true
        ignoredScrollView.borderType = .bezelBorder
        ignoredScrollView.translatesAutoresizingMaskIntoConstraints = false
        ignoredScrollView.widthAnchor.constraint(equalToConstant: 400).isActive = true
        ignoredScrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        ignoredTableView = NSTableView()
        ignoredTableView.identifier = NSUserInterfaceItemIdentifier("ignoredTable")
        ignoredTableView.headerView = nil
        let ignoredColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        ignoredColumn.width = 380
        ignoredTableView.addTableColumn(ignoredColumn)
        ignoredTableView.delegate = self
        ignoredTableView.dataSource = self
        ignoredScrollView.documentView = ignoredTableView
        stack.addArrangedSubview(ignoredScrollView)

        // Ignored buttons
        let addIgnoredButton = NSButton(title: L("settings.index.add"), target: self, action: #selector(addIgnoredDirectory))
        addIgnoredButton.bezelStyle = .rounded
        let removeIgnoredButton = NSButton(title: L("settings.index.remove"), target: self, action: #selector(removeIgnoredDirectory))
        removeIgnoredButton.bezelStyle = .rounded

        let ignoredButtonRow = NSStackView(views: [addIgnoredButton, removeIgnoredButton])
        ignoredButtonRow.orientation = .horizontal
        ignoredButtonRow.spacing = 12
        ignoredButtonRow.alignment = .centerY
        stack.addArrangedSubview(ignoredButtonRow)

        // Max depth
        let depthField = NSTextField()
        let currentDepth = UserDefaults.standard.integer(forKey: "index.maxDepth")
        depthField.stringValue = currentDepth > 0 ? String(currentDepth) : "∞"
        depthField.placeholderString = "0 = unlimited"
        depthField.target = self
        depthField.action = #selector(indexDepthChanged(_:))
        depthField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        stack.addArrangedSubview(makeRow(label: L("settings.index.maxDepth"), control: depthField))

        return wrapInTopAlignedContainer(stack)
    }

    // MARK: - Content Index Tab

    private func createContentIndexTab() -> NSView {
        let stack = makeVerticalStack()

        // Content index checkbox
        let contentCheckbox = NSButton(checkboxWithTitle: L("settings.index.content.enable"), target: self, action: #selector(contentIndexChanged(_:)))
        contentCheckbox.state = UserDefaults.standard.bool(forKey: "index.fileContent") ? .on : .off
        stack.addArrangedSubview(makeRow(label: L("settings.index.content"), control: contentCheckbox))

        // Content file extensions
        let extLabel = NSTextField(labelWithString: L("settings.index.extensions"))
        stack.addArrangedSubview(extLabel)

        // Load saved extensions
        contentExts = UserDefaults.standard.stringArray(forKey: "index.contentExtensions") ?? ["md", "txt", "swift", "py", "js", "json"]

        let extScrollView = NSScrollView()
        extScrollView.hasVerticalScroller = true
        extScrollView.borderType = .bezelBorder
        extScrollView.translatesAutoresizingMaskIntoConstraints = false
        extScrollView.widthAnchor.constraint(equalToConstant: 400).isActive = true
        extScrollView.heightAnchor.constraint(equalToConstant: 150).isActive = true

        extTableView = NSTableView()
        extTableView.identifier = NSUserInterfaceItemIdentifier("extTable")
        extTableView.headerView = nil
        let extColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ext"))
        extColumn.width = 380
        extTableView.addTableColumn(extColumn)
        extTableView.delegate = self
        extTableView.dataSource = self
        extScrollView.documentView = extTableView
        stack.addArrangedSubview(extScrollView)

        // Extension buttons
        let addExtButton = NSButton(title: L("settings.index.add"), target: self, action: #selector(addContentExtension))
        addExtButton.bezelStyle = .rounded
        let removeExtButton = NSButton(title: L("settings.index.remove"), target: self, action: #selector(removeContentExtension))
        removeExtButton.bezelStyle = .rounded

        let extButtonRow = NSStackView(views: [addExtButton, removeExtButton])
        extButtonRow.orientation = .horizontal
        extButtonRow.spacing = 12
        extButtonRow.alignment = .centerY
        stack.addArrangedSubview(extButtonRow)

        // Spotlight status
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.identifier = NSUserInterfaceItemIdentifier("indexStatus")
        if SpotlightService.isSpotlightEnabled() {
            statusLabel.stringValue = "Spotlight: Enabled"
        } else {
            statusLabel.stringValue = "Spotlight: Disabled"
            statusLabel.textColor = .systemRed
        }
        stack.addArrangedSubview(makeRow(label: "", control: statusLabel))

        return wrapInTopAlignedContainer(stack)
    }

    // MARK: - Advanced Tab

    private func createAdvancedTab() -> NSView {
        let stack = makeVerticalStack()

        // Row: Ignored Apps label
        let ignoredLabel = NSTextField(labelWithString: L("settings.advanced.ignoredApps"))
        stack.addArrangedSubview(ignoredLabel)

        // Table view for ignored apps
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 400).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let tableView = NSTableView()
        tableView.identifier = NSUserInterfaceItemIdentifier("ignoredAppsTable")
        tableView.headerView = nil

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("appPath"))
        column.width = 380
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        stack.addArrangedSubview(scrollView)

        // Empty label
        let emptyLabel = NSTextField(labelWithString: L("settings.advanced.ignoredApps.empty"))
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.identifier = NSUserInterfaceItemIdentifier("emptyLabel")
        emptyLabel.isHidden = !IgnoredAppsManager.shared.getAllIgnored().isEmpty
        emptyLabel.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(emptyLabel)

        // Buttons row
        let addButton = NSButton(title: L("settings.advanced.ignoredApps.add"), target: self, action: #selector(addIgnoredApp))
        addButton.bezelStyle = .rounded
        let removeButton = NSButton(title: L("settings.advanced.ignoredApps.remove"), target: self, action: #selector(removeIgnoredApp))
        removeButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [addButton, removeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY
        stack.addArrangedSubview(buttonRow)

        return wrapInTopAlignedContainer(stack)
    }

    @objc private func launcherLogChanged(_ sender: NSButton) {
        LogSettings.shared.launcherLogEnabled = sender.state == .on
    }

    @objc private func monitorLogChanged(_ sender: NSButton) {
        LogSettings.shared.monitorLogEnabled = sender.state == .on
    }

    @objc private func clipboardLogChanged(_ sender: NSButton) {
        LogSettings.shared.clipboardLogEnabled = sender.state == .on
    }

    @objc private func addIgnoredApp() {
        let openPanel = NSOpenPanel()
        openPanel.title = L("settings.advanced.ignoredApps.addTitle")
        openPanel.allowedContentTypes = [.applicationBundle]
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")

        if openPanel.runModal() == .OK, let url = openPanel.url {
            IgnoredAppsManager.shared.ignore(path: url.path)
            refreshIgnoredAppsTable()
        }
    }

    @objc private func removeIgnoredApp() {
        guard let tableView = advancedTab?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTableView else { return }
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }

        let ignoredApps = IgnoredAppsManager.shared.getAllIgnored()
        guard selectedRow < ignoredApps.count else { return }

        let pathToRemove = ignoredApps[selectedRow]
        IgnoredAppsManager.shared.unignore(path: pathToRemove)
        refreshIgnoredAppsTable()
    }

    private func refreshIgnoredAppsTable() {
        guard let tableView = advancedTab?.subviews.compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTableView else { return }
        tableView.reloadData()

        if let emptyLabel = advancedTab?.subviews.first(where: { $0.identifier?.rawValue == "emptyLabel" }) as? NSTextField {
            emptyLabel.isHidden = !IgnoredAppsManager.shared.getAllIgnored().isEmpty
        }
    }

    // MARK: - About Tab

    private func createAboutTab() -> NSView {
        let container = NSView()

        // App Icon
        let appIcon = NSImageView()
        if let icnsPath = Bundle.main.path(forResource: "Keystarter", ofType: "icns"),
           let image = NSImage(contentsOfFile: icnsPath) {
            appIcon.image = image
        } else {
            appIcon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            appIcon.contentTintColor = .controlAccentColor
        }
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 80).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 80).isActive = true
        container.addSubview(appIcon)

        // App Name
        let nameLabel = NSTextField(labelWithString: "Keystarter")
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionLabel = NSTextField(labelWithString: String(format: L("settings.about.version"), version))
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(versionLabel)

        // Copyright
        let copyrightLabel = NSTextField(labelWithString: L("settings.about.copyright"))
        copyrightLabel.alignment = .center
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(copyrightLabel)

        // GitHub link
        let githubButton = NSButton(title: "github.com/J-Liu/Keystarter", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(githubButton)

        // Check for Updates button
        let checkUpdatesButton = NSButton(title: L("menu.checkUpdates"), target: self, action: #selector(checkForUpdatesNow))
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checkUpdatesButton)

        NSLayoutConstraint.activate([
            appIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            appIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            nameLabel.topAnchor.constraint(equalTo: appIcon.bottomAnchor, constant: 16),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            copyrightLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 8),
            copyrightLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            githubButton.topAnchor.constraint(equalTo: copyrightLabel.bottomAnchor, constant: 24),
            githubButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            checkUpdatesButton.topAnchor.constraint(equalTo: githubButton.bottomAnchor, constant: 12),
            checkUpdatesButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            checkUpdatesButton.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20)
        ])

        return container
    }

    // MARK: - Key Handlers

    private func setupKeyHandlers() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if HotkeyRecorderButton.isAnyRecording { return event }
            if event.keyCode == 53 { // Esc
                self.close()
                return nil
            }
            if event.modifierFlags.contains(.command) && event.keyCode == 13 { // Cmd+W
                self.close()
                return nil
            }
            return event
        }
    }

    // MARK: - Actions

    private func themeName(for key: String) -> String {
        switch key {
        case "light": return L("settings.statusbar.light")
        case "dark": return L("settings.statusbar.dark")
        case "hidden": return L("settings.statusbar.hidden")
        default: return L("settings.statusbar.system")
        }
    }

    private func hotkeyChanged(recorder: HotkeyRecorderButton) {
        (NSApp.delegate as? AppDelegate)?.updateHotkey(keyCode: recorder.keyCode, modifiers: recorder.modifiers)
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let language = LocalizationManager.Language.allCases.first { $0.displayName == sender.title } ?? .english
        LocalizationManager.shared.currentLanguage = language
        recreateUI()
    }

    private func recreateUI() {
        while let tab = tabView.tabViewItems.first {
            tabView.removeTabViewItem(tab)
        }

        generalTab = createGeneralTab()
        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = L("settings.tab.general")
        generalItem.view = generalTab
        tabView.addTabViewItem(generalItem)

        monitorTab = createMonitorTab()
        let monitorItem = NSTabViewItem(identifier: "monitor")
        monitorItem.label = L("settings.tab.monitor")
        monitorItem.view = monitorTab
        tabView.addTabViewItem(monitorItem)

        clipboardTab = createClipboardTab()
        let clipboardItem = NSTabViewItem(identifier: "clipboard")
        clipboardItem.label = L("settings.tab.clipboard")
        clipboardItem.view = clipboardTab
        tabView.addTabViewItem(clipboardItem)

        indexTab = createIndexTab()
        let indexItem = NSTabViewItem(identifier: "index")
        indexItem.label = L("settings.tab.index")
        indexItem.view = indexTab
        tabView.addTabViewItem(indexItem)

        contentIndexTab = createContentIndexTab()
        let contentIndexItem = NSTabViewItem(identifier: "contentIndex")
        contentIndexItem.label = L("settings.tab.contentIndex")
        contentIndexItem.view = contentIndexTab
        tabView.addTabViewItem(contentIndexItem)

        advancedTab = createAdvancedTab()
        let advancedItem = NSTabViewItem(identifier: "advanced")
        advancedItem.label = L("settings.tab.advanced")
        advancedItem.view = advancedTab
        tabView.addTabViewItem(advancedItem)

        aboutTab = createAboutTab()
        let aboutItem = NSTabViewItem(identifier: "about")
        aboutItem.label = L("settings.tab.about")
        aboutItem.view = aboutTab
        tabView.addTabViewItem(aboutItem)
    }

    @objc private func statusBarThemeChanged(_ sender: NSPopUpButton) {
        let theme: String
        let title = sender.selectedItem?.title ?? ""
        if title == L("settings.statusbar.light") { theme = "light" }
        else if title == L("settings.statusbar.dark") { theme = "dark" }
        else if title == L("settings.statusbar.hidden") { theme = "hidden" }
        else { theme = "system" }
        UserDefaults.standard.set(theme, forKey: "statusBar.theme")
        (NSApp.delegate as? AppDelegate)?.updateStatusBarTheme(theme)
    }

    @objc private func groupByChanged(_ sender: NSPopUpButton) {
        let title = sender.title
        let groupBy: String
        if title == L("settings.groupBy.letter") {
            groupBy = "letter"
        } else if title == L("settings.groupBy.category") {
            groupBy = "category"
        } else {
            groupBy = "frequency"
        }
        UserDefaults.standard.set(groupBy, forKey: "launcher.groupBy")
    }

    @objc private func loginItemChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "startAtLogin")
        PermissionManager.shared.setLoginItem(enabled: enabled)
    }

    @objc private func dockIconChanged(_ sender: NSButton) {
        let showDock = sender.state == .on
        UserDefaults.standard.set(showDock, forKey: "showDockIcon")
        (NSApp.delegate as? AppDelegate)?.updateDockIconVisibility()
    }

    @objc private func cpuModuleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "status.cpu.enabled")
        if enabled {
            StatusItemController.shared.enableModule("cpu")
        } else {
            StatusItemController.shared.disableModule("cpu")
        }
    }

    @objc private func memoryModuleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "status.memory.enabled")
        if enabled {
            StatusItemController.shared.enableModule("memory")
        } else {
            StatusItemController.shared.disableModule("memory")
        }
    }

    @objc private func networkModuleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "status.network.enabled")
        if enabled {
            StatusItemController.shared.enableModule("network")
        } else {
            StatusItemController.shared.disableModule("network")
        }
    }

    @objc private func diskModuleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "status.disk.enabled")
        if enabled {
            StatusItemController.shared.enableModule("disk")
        } else {
            StatusItemController.shared.disableModule("disk")
        }
    }

    @objc private func gpuModuleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "status.gpu.enabled")
        if enabled {
            StatusItemController.shared.enableModule("gpu")
        } else {
            StatusItemController.shared.disableModule("gpu")
        }
    }

    @objc private func sensorModuleChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "status.sensor.enabled")
        if enabled {
            StatusItemController.shared.enableModule("sensor")
        } else {
            StatusItemController.shared.disableModule("sensor")
        }
    }

    @objc private func contentIndexChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "index.fileContent")
    }

    @objc private func indexDepthChanged(_ sender: NSTextField) {
        let depth = Int(sender.stringValue) ?? 0
        UserDefaults.standard.set(depth, forKey: "index.maxDepth")
    }

    @objc private func addIndexDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("settings.index.selectDirectory")

        if panel.runModal() == .OK, let url = panel.url {
            let path = abbreviatePath(url.path)
            if !dirs.contains(path) {
                dirs.append(path)
                UserDefaults.standard.set(dirs, forKey: "index.directories")
                dirsTableView.reloadData()
            }
        }
    }

    /// Convert absolute path to ~ format if in home directory
    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    @objc private func removeIndexDirectory() {
        let selectedRow = dirsTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < dirs.count else { return }
        dirs.remove(at: selectedRow)
        UserDefaults.standard.set(dirs, forKey: "index.directories")
        dirsTableView.reloadData()
    }

    @objc private func addIgnoredDirectory() {
        let alert = NSAlert()
        alert.messageText = L("settings.index.ignored.addTitle")
        alert.informativeText = L("settings.index.ignored.addMessage")
        alert.addButton(withTitle: L("settings.index.add"))
        alert.addButton(withTitle: L("settings.index.cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !ignoredDirs.contains(name) {
                ignoredDirs.append(name)
                UserDefaults.standard.set(ignoredDirs, forKey: "index.ignoredDirs")
                ignoredTableView.reloadData()
            }
        }
    }

    @objc private func removeIgnoredDirectory() {
        let selectedRow = ignoredTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < ignoredDirs.count else { return }
        ignoredDirs.remove(at: selectedRow)
        UserDefaults.standard.set(ignoredDirs, forKey: "index.ignoredDirs")
        ignoredTableView.reloadData()
    }

    @objc private func addContentExtension() {
        let alert = NSAlert()
        alert.messageText = L("settings.index.ext.addTitle")
        alert.informativeText = L("settings.index.ext.addMessage")
        alert.addButton(withTitle: L("settings.index.add"))
        alert.addButton(withTitle: L("settings.index.cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let ext = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !ext.isEmpty && !contentExts.contains(ext) {
                contentExts.append(ext)
                UserDefaults.standard.set(contentExts, forKey: "index.contentExtensions")
                extTableView.reloadData()
            }
        }
    }

    @objc private func removeContentExtension() {
        let selectedRow = extTableView.selectedRow
        guard selectedRow >= 0 && selectedRow < contentExts.count else { return }
        contentExts.remove(at: selectedRow)
        UserDefaults.standard.set(contentExts, forKey: "index.contentExtensions")
        extTableView.reloadData()
    }

    @objc private func updateFrequencyChanged(_ sender: NSPopUpButton) {
        let frequency = UpdateManager.CheckFrequency.allCases.first { $0.displayName == sender.title } ?? .weekly
        UpdateManager.shared.checkFrequency = frequency
    }

    @objc private func checkForUpdatesNow() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func checkPermissions() {
        let hasAccessibility = PermissionManager.shared.hasAccessibilityPermission()

        if !hasAccessibility {
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
            ] as CFDictionary)
        } else {
            showPermissionsStatus()
        }
    }

    private func showPermissionsStatus() {
        let alert = NSAlert()
        alert.messageText = L("permissions.status.title")
        alert.informativeText = L("permissions.status.allGranted")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("permissions.status.ok"))

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))

        let accessibilityIcon = NSImageView(frame: NSRect(x: 10, y: 45, width: 20, height: 20))
        accessibilityIcon.image = NSImage(named: NSImage.statusAvailableName)
        containerView.addSubview(accessibilityIcon)

        let accessibilityLabel = NSTextField(labelWithString: L("permissions.status.accessibility"))
        accessibilityLabel.frame = NSRect(x: 35, y: 45, width: 250, height: 20)
        containerView.addSubview(accessibilityLabel)

        let inputIcon = NSImageView(frame: NSRect(x: 10, y: 15, width: 20, height: 20))
        inputIcon.image = NSImage(named: NSImage.statusAvailableName)
        containerView.addSubview(inputIcon)

        let inputLabel = NSTextField(labelWithString: L("permissions.status.inputMonitoring"))
        inputLabel.frame = NSRect(x: 35, y: 15, width: 250, height: 20)
        containerView.addSubview(inputLabel)

        alert.accessoryView = containerView
        alert.runModal()
    }

    @objc private func radiusChanged(_ sender: NSSlider) {
        AppearanceSettings.cornerRadius = CGFloat(sender.doubleValue)
        AppearanceSettings.save()
        if let label = generalTabSubview(withIdentifier: "radiusValue") as? NSTextField {
            label.stringValue = "\(Int(sender.doubleValue))"
        }
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        AppearanceSettings.opacity = CGFloat(sender.doubleValue)
        AppearanceSettings.save()
        if let label = generalTabSubview(withIdentifier: "opacityValue") as? NSTextField {
            label.stringValue = "\(Int(sender.doubleValue * 100))%"
        }
    }

    private func generalTabSubview(withIdentifier id: String) -> NSView? {
        return generalTab.subviews.first { $0.identifier?.rawValue == id }
    }

    private func clipboardHotkeyChanged(recorder: HotkeyRecorderButton) {
        UserDefaults.standard.set(Int(recorder.keyCode), forKey: "clipboard.hotkey.keyCode")
        UserDefaults.standard.set(Int(recorder.modifiers.rawValue), forKey: "clipboard.hotkey.modifiers")
        (NSApp.delegate as? AppDelegate)?.updateClipboardHotkey(keyCode: recorder.keyCode, modifiers: recorder.modifiers)
    }

    @objc private func clipboardMaxCountChanged(_ sender: NSTextField) {
        if let value = Int(sender.stringValue) {
            UserDefaults.standard.set(value, forKey: "clipboard.maxCount")
        }
    }

    @objc private func clipboardMaxDaysChanged(_ sender: NSTextField) {
        if let value = Int(sender.stringValue) {
            UserDefaults.standard.set(value, forKey: "clipboard.maxDays")
        }
    }

    @objc private func clearClipboardHistory() {
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

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/J-Liu/Keystarter") {
            NSWorkspace.shared.open(url)
        }
    }

    func selectTab(withIdentifier identifier: String) {
        tabView.selectTabViewItem(withIdentifier: identifier)
    }
}

// MARK: - NSTableViewDelegate / NSTableViewDataSource

extension SettingsWindow: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView.identifier?.rawValue {
        case "ignoredAppsTable":
            return IgnoredAppsManager.shared.getAllIgnored().count
        case "dirsTable":
            return dirs.count
        case "ignoredTable":
            return ignoredDirs.count
        case "extTable":
            return contentExts.count
        default:
            return 0
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableView.identifier?.rawValue {
        case "ignoredAppsTable":
            let ignoredApps = IgnoredAppsManager.shared.getAllIgnored()
            guard row < ignoredApps.count else { return nil }

            let path = ignoredApps[row]
            let name = IgnoredAppsManager.shared.appName(from: path)

            let cellIdentifier = NSUserInterfaceItemIdentifier("appCell")
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
            cell.identifier = cellIdentifier
            cell.stringValue = name
            cell.toolTip = path
            return cell

        case "dirsTable":
            guard row < dirs.count else { return nil }
            let cellIdentifier = NSUserInterfaceItemIdentifier("dirCell")
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
            cell.identifier = cellIdentifier
            cell.stringValue = dirs[row]
            return cell

        case "ignoredTable":
            guard row < ignoredDirs.count else { return nil }
            let cellIdentifier = NSUserInterfaceItemIdentifier("ignoredCell")
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
            cell.identifier = cellIdentifier
            cell.stringValue = ignoredDirs[row]
            return cell

        case "extTable":
            guard row < contentExts.count else { return nil }
            let cellIdentifier = NSUserInterfaceItemIdentifier("extCell")
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
            cell.identifier = cellIdentifier
            cell.stringValue = contentExts[row]
            return cell

        default:
            return nil
        }
    }
}
