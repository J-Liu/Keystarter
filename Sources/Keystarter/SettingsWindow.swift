// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

/// Settings window with tabs for configuration.
final class SettingsWindow: NSWindow {

    private var tabView: NSTabView!
    private var generalTab: NSView!
    private var clipboardTab: NSView!
    private var advancedTab: NSView!
    private var aboutTab: NSView!
    private var hotkeyRecorder: HotkeyRecorderButton!

    // Layout constants
    private let labelWidth: CGFloat = 120
    private let controlWidth: CGFloat = 200
    private let rowHeight: CGFloat = 36
    private let viewWidth: CGFloat = 560

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 600
        let height: CGFloat = 650
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

        clipboardTab = createClipboardTab()
        let clipboardItem = NSTabViewItem(identifier: "clipboard")
        clipboardItem.label = L("settings.tab.clipboard")
        clipboardItem.view = clipboardTab
        tabView.addTabViewItem(clipboardItem)

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

    // MARK: - Stack View Helpers

    private func makeRow(label: String, control: NSView) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))
        let labelField = NSTextField(labelWithString: label)
        labelField.frame = NSRect(x: 20, y: 6, width: labelWidth, height: 24)
        labelField.alignment = .right
        labelField.textColor = .labelColor
        row.addSubview(labelField)
        control.frame = NSRect(x: 20 + labelWidth + 10, y: 4, width: control.frame.width, height: control.frame.height)
        row.addSubview(control)
        return row
    }

    private func makeStackView(rows: [NSView]) -> NSStackView {
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: CGFloat(rows.count) * rowHeight + 40))
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        for row in rows {
            stack.addArrangedSubview(row)
        }
        return stack
    }

    // MARK: - General Tab

    private func createGeneralTab() -> NSView {
        // Language
        let languagePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: controlWidth, height: 28))
        for language in LocalizationManager.Language.allCases {
            languagePopup.addItem(withTitle: language.displayName)
        }
        languagePopup.selectItem(withTitle: LocalizationManager.shared.currentLanguage.displayName)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        let languageRow = makeRow(label: L("settings.language"), control: languagePopup)

        // Hotkey
        hotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
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
        let hotkeyRow = makeRow(label: L("settings.hotkey"), control: hotkeyRecorder)

        // Status Bar
        let statusBarPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: controlWidth, height: 28))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.system"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.light"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.dark"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.hidden"))
        let savedTheme = UserDefaults.standard.string(forKey: "statusBar.theme") ?? "system"
        statusBarPopup.selectItem(withTitle: themeName(for: savedTheme))
        statusBarPopup.target = self
        statusBarPopup.action = #selector(statusBarThemeChanged(_:))
        let statusBarRow = makeRow(label: L("settings.statusbar"), control: statusBarPopup)

        // Corner Radius
        let radiusSlider = NSSlider(frame: NSRect(x: 0, y: 0, width: controlWidth, height: 24))
        radiusSlider.minValue = 0
        radiusSlider.maxValue = 24
        radiusSlider.doubleValue = Double(AppearanceSettings.cornerRadius)
        radiusSlider.target = self
        radiusSlider.action = #selector(radiusChanged(_:))
        let radiusValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.cornerRadius))")
        radiusValue.frame = NSRect(x: 20 + labelWidth + 10 + controlWidth + 10, y: 6, width: 40, height: 24)
        radiusValue.identifier = NSUserInterfaceItemIdentifier("radiusValue")
        let radiusRow = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))
        let radiusLabel = NSTextField(labelWithString: L("settings.cornerRadius"))
        radiusLabel.frame = NSRect(x: 20, y: 6, width: labelWidth, height: 24)
        radiusLabel.alignment = .right
        radiusRow.addSubview(radiusLabel)
        radiusSlider.frame = NSRect(x: 20 + labelWidth + 10, y: 6, width: controlWidth, height: 24)
        radiusRow.addSubview(radiusSlider)
        radiusRow.addSubview(radiusValue)

        // Opacity
        let opacitySlider = NSSlider(frame: NSRect(x: 0, y: 0, width: controlWidth, height: 24))
        opacitySlider.minValue = 0.5
        opacitySlider.maxValue = 1.0
        opacitySlider.doubleValue = Double(AppearanceSettings.opacity)
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        let opacityValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.opacity * 100))%")
        opacityValue.frame = NSRect(x: 20 + labelWidth + 10 + controlWidth + 10, y: 6, width: 50, height: 24)
        opacityValue.identifier = NSUserInterfaceItemIdentifier("opacityValue")
        let opacityRow = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))
        let opacityLabel = NSTextField(labelWithString: L("settings.opacity"))
        opacityLabel.frame = NSRect(x: 20, y: 6, width: labelWidth, height: 24)
        opacityLabel.alignment = .right
        opacityRow.addSubview(opacityLabel)
        opacitySlider.frame = NSRect(x: 20 + labelWidth + 10, y: 6, width: controlWidth, height: 24)
        opacityRow.addSubview(opacitySlider)
        opacityRow.addSubview(opacityValue)

        // Group By
        let groupByPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: controlWidth, height: 28))
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
        let groupByRow = makeRow(label: L("settings.groupBy"), control: groupByPopup)

        // Start at Login
        let loginCheckbox = NSButton(checkboxWithTitle: L("settings.startAtLogin.checkbox"), target: self, action: #selector(loginItemChanged(_:)))
        loginCheckbox.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        loginCheckbox.state = UserDefaults.standard.bool(forKey: "startAtLogin") ? .on : .off
        let loginRow = makeRow(label: L("settings.startAtLogin"), control: loginCheckbox)

        // Dock Icon
        let dockIconCheckbox = NSButton(checkboxWithTitle: L("settings.dockIcon.checkbox"), target: self, action: #selector(dockIconChanged(_:)))
        dockIconCheckbox.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        dockIconCheckbox.state = UserDefaults.standard.bool(forKey: "showDockIcon") ? .on : .off
        let dockRow = makeRow(label: L("settings.dockIcon"), control: dockIconCheckbox)

        // Update frequency
        let updateFrequencyPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
        for frequency in UpdateManager.CheckFrequency.allCases {
            updateFrequencyPopup.addItem(withTitle: frequency.displayName)
        }
        updateFrequencyPopup.selectItem(withTitle: UpdateManager.shared.checkFrequency.displayName)
        updateFrequencyPopup.target = self
        updateFrequencyPopup.action = #selector(updateFrequencyChanged(_:))
        let checkNowButton = NSButton(frame: NSRect(x: 160, y: 0, width: 100, height: 28))
        checkNowButton.title = L("settings.update.checkNow")
        checkNowButton.bezelStyle = .rounded
        checkNowButton.target = self
        checkNowButton.action = #selector(checkForUpdatesNow)
        let updateRow = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))
        let updateLabel = NSTextField(labelWithString: L("settings.update.frequency"))
        updateLabel.frame = NSRect(x: 20, y: 6, width: labelWidth, height: 24)
        updateLabel.alignment = .right
        updateRow.addSubview(updateLabel)
        updateFrequencyPopup.frame = NSRect(x: 20 + labelWidth + 10, y: 4, width: 150, height: 28)
        updateRow.addSubview(updateFrequencyPopup)
        checkNowButton.frame = NSRect(x: 20 + labelWidth + 10 + 160, y: 4, width: 100, height: 28)
        updateRow.addSubview(checkNowButton)

        // Permissions button
        let permissionsButton = NSButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        permissionsButton.title = L("settings.permissions")
        permissionsButton.bezelStyle = .rounded
        permissionsButton.target = self
        permissionsButton.action = #selector(checkPermissions)
        let permissionsRow = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))
        permissionsButton.frame = NSRect(x: 20 + labelWidth + 10, y: 2, width: 200, height: 28)
        permissionsRow.addSubview(permissionsButton)

        let stack = makeStackView(rows: [
            languageRow, hotkeyRow, statusBarRow, radiusRow, opacityRow,
            groupByRow, loginRow, dockRow, updateRow, permissionsRow
        ])

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: 580))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = stack
        stack.frame = NSRect(x: 0, y: 0, width: viewWidth, height: stack.frame.height)
        stack.autoresizingMask = [.width]

        return scrollView
    }

    // MARK: - Clipboard Tab

    private func createClipboardTab() -> NSView {
        // Hotkey
        let clipboardHotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
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
        let hotkeyRow = makeRow(label: L("settings.clipboard.hotkey"), control: clipboardHotkeyRecorder)

        // Max Count
        let maxCountField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        let currentMaxCount = UserDefaults.standard.integer(forKey: "clipboard.maxCount") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxCount") : 500
        maxCountField.stringValue = String(currentMaxCount)
        maxCountField.target = self
        maxCountField.action = #selector(clipboardMaxCountChanged(_:))
        let maxCountRow = makeRow(label: L("settings.clipboard.maxCount"), control: maxCountField)

        // Max Days
        let maxDaysField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        maxDaysField.stringValue = String(UserDefaults.standard.integer(forKey: "clipboard.maxDays") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxDays") : 30)
        maxDaysField.target = self
        maxDaysField.action = #selector(clipboardMaxDaysChanged(_:))
        let maxDaysRow = makeRow(label: L("settings.clipboard.maxDays"), control: maxDaysField)

        // Clear button
        let clearButton = NSButton(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        clearButton.title = L("settings.clipboard.clear")
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearClipboardHistory)
        let clearRow = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: rowHeight))
        clearButton.frame = NSRect(x: 20 + labelWidth + 10, y: 2, width: 200, height: 28)
        clearRow.addSubview(clearButton)

        let stack = makeStackView(rows: [hotkeyRow, maxCountRow, maxDaysRow, clearRow])

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: 580))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = stack
        stack.autoresizingMask = [.width]

        return scrollView
    }

    // MARK: - Advanced Tab

    private func createAdvancedTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: 580))

        // Label
        let label = NSTextField(labelWithString: L("settings.advanced.ignoredApps"))
        label.frame = NSRect(x: 20, y: 540, width: labelWidth, height: 24)
        label.alignment = .right
        container.addSubview(label)

        // Table
        let scrollView = NSScrollView(frame: NSRect(x: 20 + labelWidth + 10, y: 340, width: 300, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.identifier = NSUserInterfaceItemIdentifier("ignoredAppsTable")
        tableView.headerView = nil

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("appPath"))
        column.width = 280
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        container.addSubview(scrollView)

        // Empty label
        let emptyLabel = NSTextField(labelWithString: L("settings.advanced.ignoredApps.empty"))
        emptyLabel.frame = NSRect(x: 20 + labelWidth + 20, y: 440, width: 280, height: 20)
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.identifier = NSUserInterfaceItemIdentifier("emptyLabel")
        emptyLabel.isHidden = !IgnoredAppsManager.shared.getAllIgnored().isEmpty
        container.addSubview(emptyLabel)

        // Add button
        let addButton = NSButton(frame: NSRect(x: 20 + labelWidth + 10, y: 300, width: 80, height: 32))
        addButton.title = L("settings.advanced.ignoredApps.add")
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addIgnoredApp)
        container.addSubview(addButton)

        // Remove button
        let removeButton = NSButton(frame: NSRect(x: 20 + labelWidth + 100, y: 300, width: 80, height: 32))
        removeButton.title = L("settings.advanced.ignoredApps.remove")
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeIgnoredApp)
        container.addSubview(removeButton)

        return container
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
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: 400))
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 0, bottom: 20, right: 0)

        // App Icon
        let appIcon = NSImageView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        if let icnsPath = Bundle.main.path(forResource: "Keystarter", ofType: "icns"),
           let image = NSImage(contentsOfFile: icnsPath) {
            appIcon.image = image
        } else {
            appIcon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            appIcon.contentTintColor = .controlAccentColor
        }
        stack.addArrangedSubview(appIcon)

        // App Name
        let nameLabel = NSTextField(labelWithString: "Keystarter")
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionLabel = NSTextField(labelWithString: String(format: L("settings.about.version"), version))
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        // Copyright
        let copyrightLabel = NSTextField(labelWithString: L("settings.about.copyright"))
        copyrightLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(copyrightLabel)

        // Spacer
        stack.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 20)))

        // GitHub link
        let githubButton = NSButton(frame: NSRect(x: 0, y: 0, width: 220, height: 32))
        githubButton.title = "github.com/J-Liu/Keystarter"
        githubButton.bezelStyle = .rounded
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        stack.addArrangedSubview(githubButton)

        // Check for Updates button
        let checkUpdatesButton = NSButton(frame: NSRect(x: 0, y: 0, width: 160, height: 32))
        checkUpdatesButton.title = L("menu.checkUpdates")
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForUpdatesNow)
        stack.addArrangedSubview(checkUpdatesButton)

        return stack
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

        clipboardTab = createClipboardTab()
        let clipboardItem = NSTabViewItem(identifier: "clipboard")
        clipboardItem.label = L("settings.tab.clipboard")
        clipboardItem.view = clipboardTab
        tabView.addTabViewItem(clipboardItem)

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

    @objc private func updateFrequencyChanged(_ sender: NSPopUpButton) {
        let frequency = UpdateManager.CheckFrequency.allCases.first { $0.displayName == sender.title } ?? .weekly
        UpdateManager.shared.checkFrequency = frequency
    }

    @objc private func checkForUpdatesNow() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func checkPermissions() {
        // Directly trigger system permission dialog, no custom alert
        _ = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
        ] as CFDictionary)
    }

    @objc private func radiusChanged(_ sender: NSSlider) {
        AppearanceSettings.cornerRadius = CGFloat(sender.doubleValue)
        AppearanceSettings.save()
        if let scrollView = generalTab as? NSScrollView,
           let label = scrollView.documentView?.subviews.first(where: { $0.identifier?.rawValue == "radiusValue" }) as? NSTextField {
            label.stringValue = "\(Int(sender.doubleValue))"
        }
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        AppearanceSettings.opacity = CGFloat(sender.doubleValue)
        AppearanceSettings.save()
        if let scrollView = generalTab as? NSScrollView,
           let label = scrollView.documentView?.subviews.first(where: { $0.identifier?.rawValue == "opacityValue" }) as? NSTextField {
            label.stringValue = "\(Int(sender.doubleValue * 100))%"
        }
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
        if tableView.identifier?.rawValue == "ignoredAppsTable" {
            return IgnoredAppsManager.shared.getAllIgnored().count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView.identifier?.rawValue == "ignoredAppsTable" {
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
        }
        return nil
    }
}
