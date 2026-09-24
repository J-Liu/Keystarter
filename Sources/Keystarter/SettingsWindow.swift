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
    private let labelX: CGFloat = 20
    private let controlX: CGFloat = 150
    private let controlWidth: CGFloat = 200
    private let rowHeight: CGFloat = 40
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

    // MARK: - General Tab
    // 10 rows: Language, Hotkey, StatusBar, CornerRadius, Opacity, GroupBy, Login, Dock, Update, Permissions

    private func createGeneralTab() -> NSView {
        let viewHeight: CGFloat = 440
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))

        var y = viewHeight - rowHeight

        // Row: Language
        addLabel(L("settings.language"), to: view, y: y)
        let languagePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 4, width: controlWidth, height: 32))
        for language in LocalizationManager.Language.allCases {
            languagePopup.addItem(withTitle: language.displayName)
        }
        languagePopup.selectItem(withTitle: LocalizationManager.shared.currentLanguage.displayName)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        view.addSubview(languagePopup)

        y -= rowHeight

        // Row: Hotkey
        addLabel(L("settings.hotkey"), to: view, y: y)
        hotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: controlX, y: y - 4, width: 150, height: 32))
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
        view.addSubview(hotkeyRecorder)

        y -= rowHeight

        // Row: Status Bar
        addLabel(L("settings.statusbar"), to: view, y: y)
        let statusBarPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 4, width: controlWidth, height: 32))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.system"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.light"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.dark"))
        statusBarPopup.addItem(withTitle: L("settings.statusbar.hidden"))
        let savedTheme = UserDefaults.standard.string(forKey: "statusBar.theme") ?? "system"
        statusBarPopup.selectItem(withTitle: themeName(for: savedTheme))
        statusBarPopup.target = self
        statusBarPopup.action = #selector(statusBarThemeChanged(_:))
        view.addSubview(statusBarPopup)

        y -= rowHeight

        // Row: Corner Radius
        addLabel(L("settings.cornerRadius"), to: view, y: y)
        let radiusSlider = NSSlider(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 24))
        radiusSlider.minValue = 0
        radiusSlider.maxValue = 24
        radiusSlider.doubleValue = Double(AppearanceSettings.cornerRadius)
        radiusSlider.target = self
        radiusSlider.action = #selector(radiusChanged(_:))
        view.addSubview(radiusSlider)

        let radiusValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.cornerRadius))")
        radiusValue.frame = NSRect(x: controlX + controlWidth + 10, y: y, width: 40, height: 24)
        radiusValue.identifier = NSUserInterfaceItemIdentifier("radiusValue")
        view.addSubview(radiusValue)

        y -= rowHeight

        // Row: Opacity
        addLabel(L("settings.opacity"), to: view, y: y)
        let opacitySlider = NSSlider(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 24))
        opacitySlider.minValue = 0.5
        opacitySlider.maxValue = 1.0
        opacitySlider.doubleValue = Double(AppearanceSettings.opacity)
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        view.addSubview(opacitySlider)

        let opacityValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.opacity * 100))%")
        opacityValue.frame = NSRect(x: controlX + controlWidth + 10, y: y, width: 50, height: 24)
        opacityValue.identifier = NSUserInterfaceItemIdentifier("opacityValue")
        view.addSubview(opacityValue)

        y -= rowHeight

        // Row: Group By
        addLabel(L("settings.groupBy"), to: view, y: y)
        let groupByPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 4, width: controlWidth, height: 32))
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
        view.addSubview(groupByPopup)

        y -= rowHeight

        // Row: Start at Login
        addLabel(L("settings.startAtLogin"), to: view, y: y)
        let loginCheckbox = NSButton(checkboxWithTitle: L("settings.startAtLogin.checkbox"), target: self, action: #selector(loginItemChanged(_:)))
        loginCheckbox.frame = NSRect(x: controlX, y: y, width: 300, height: 24)
        loginCheckbox.state = UserDefaults.standard.bool(forKey: "startAtLogin") ? .on : .off
        view.addSubview(loginCheckbox)

        y -= rowHeight

        // Row: Dock Icon
        addLabel(L("settings.dockIcon"), to: view, y: y)
        let dockIconCheckbox = NSButton(checkboxWithTitle: L("settings.dockIcon.checkbox"), target: self, action: #selector(dockIconChanged(_:)))
        dockIconCheckbox.frame = NSRect(x: controlX, y: y, width: 300, height: 24)
        dockIconCheckbox.state = UserDefaults.standard.bool(forKey: "showDockIcon") ? .on : .off
        view.addSubview(dockIconCheckbox)

        y -= rowHeight

        // Row: Update
        addLabel(L("settings.update.frequency"), to: view, y: y)
        let updateFrequencyPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y - 4, width: 150, height: 32))
        for frequency in UpdateManager.CheckFrequency.allCases {
            updateFrequencyPopup.addItem(withTitle: frequency.displayName)
        }
        updateFrequencyPopup.selectItem(withTitle: UpdateManager.shared.checkFrequency.displayName)
        updateFrequencyPopup.target = self
        updateFrequencyPopup.action = #selector(updateFrequencyChanged(_:))
        view.addSubview(updateFrequencyPopup)

        let checkNowButton = NSButton(frame: NSRect(x: controlX + 160, y: y - 2, width: 100, height: 28))
        checkNowButton.title = L("settings.update.checkNow")
        checkNowButton.bezelStyle = .rounded
        checkNowButton.target = self
        checkNowButton.action = #selector(checkForUpdatesNow)
        view.addSubview(checkNowButton)

        y -= rowHeight

        // Row: Permissions
        let permissionsButton = NSButton(frame: NSRect(x: controlX, y: y, width: 200, height: 32))
        permissionsButton.title = L("settings.permissions")
        permissionsButton.bezelStyle = .rounded
        permissionsButton.target = self
        permissionsButton.action = #selector(checkPermissions)
        view.addSubview(permissionsButton)

        return view
    }

    // MARK: - Clipboard Tab
    // 4 rows: Hotkey, MaxCount, MaxDays, Clear

    private func createClipboardTab() -> NSView {
        let viewHeight: CGFloat = 200
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))

        var y = viewHeight - rowHeight

        // Row: Hotkey
        addLabel(L("settings.clipboard.hotkey"), to: view, y: y)
        let clipboardHotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: controlX, y: y - 4, width: 150, height: 32))
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
        view.addSubview(clipboardHotkeyRecorder)

        y -= rowHeight

        // Row: Max Count
        addLabel(L("settings.clipboard.maxCount"), to: view, y: y)
        let maxCountField = NSTextField(frame: NSRect(x: controlX, y: y, width: 80, height: 24))
        let currentMaxCount = UserDefaults.standard.integer(forKey: "clipboard.maxCount") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxCount") : 500
        maxCountField.stringValue = String(currentMaxCount)
        maxCountField.target = self
        maxCountField.action = #selector(clipboardMaxCountChanged(_:))
        view.addSubview(maxCountField)

        y -= rowHeight

        // Row: Max Days
        addLabel(L("settings.clipboard.maxDays"), to: view, y: y)
        let maxDaysField = NSTextField(frame: NSRect(x: controlX, y: y, width: 80, height: 24))
        maxDaysField.stringValue = String(UserDefaults.standard.integer(forKey: "clipboard.maxDays") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxDays") : 30)
        maxDaysField.target = self
        maxDaysField.action = #selector(clipboardMaxDaysChanged(_:))
        view.addSubview(maxDaysField)

        y -= rowHeight

        // Row: Clear
        let clearButton = NSButton(frame: NSRect(x: controlX, y: y, width: 200, height: 32))
        clearButton.title = L("settings.clipboard.clear")
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearClipboardHistory)
        view.addSubview(clearButton)

        return view
    }

    // MARK: - Advanced Tab

    private func createAdvancedTab() -> NSView {
        let viewHeight: CGFloat = 400
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))

        var y = viewHeight - rowHeight

        // Row: Ignored Apps label
        addLabel(L("settings.advanced.ignoredApps"), to: view, y: y)

        y -= rowHeight + 10

        // Table view for ignored apps
        let scrollView = NSScrollView(frame: NSRect(x: controlX, y: y - 180, width: 300, height: 200))
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
        view.addSubview(scrollView)

        // Empty label
        let emptyLabel = NSTextField(labelWithString: L("settings.advanced.ignoredApps.empty"))
        emptyLabel.frame = NSRect(x: controlX + 10, y: y - 90, width: 280, height: 20)
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.identifier = NSUserInterfaceItemIdentifier("emptyLabel")
        emptyLabel.isHidden = !IgnoredAppsManager.shared.getAllIgnored().isEmpty
        view.addSubview(emptyLabel)

        y -= 220

        // Add button
        let addButton = NSButton(frame: NSRect(x: controlX, y: y, width: 80, height: 32))
        addButton.title = L("settings.advanced.ignoredApps.add")
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addIgnoredApp)
        view.addSubview(addButton)

        // Remove button
        let removeButton = NSButton(frame: NSRect(x: controlX + 90, y: y, width: 80, height: 32))
        removeButton.title = L("settings.advanced.ignoredApps.remove")
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeIgnoredApp)
        view.addSubview(removeButton)

        return view
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
        let viewHeight: CGFloat = 360
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))

        // App Icon
        let appIcon = NSImageView(frame: NSRect(x: (viewWidth - 80) / 2, y: 240, width: 80, height: 80))
        if let icnsPath = Bundle.main.path(forResource: "Keystarter", ofType: "icns"),
           let image = NSImage(contentsOfFile: icnsPath) {
            appIcon.image = image
        } else {
            appIcon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            appIcon.contentTintColor = .controlAccentColor
        }
        view.addSubview(appIcon)

        // App Name
        let nameLabel = NSTextField(labelWithString: "Keystarter")
        nameLabel.frame = NSRect(x: 0, y: 200, width: viewWidth, height: 28)
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        view.addSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionLabel = NSTextField(labelWithString: String(format: L("settings.about.version"), version))
        versionLabel.frame = NSRect(x: 0, y: 170, width: viewWidth, height: 20)
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        view.addSubview(versionLabel)

        // Copyright
        let copyrightLabel = NSTextField(labelWithString: L("settings.about.copyright"))
        copyrightLabel.frame = NSRect(x: 0, y: 140, width: viewWidth, height: 20)
        copyrightLabel.alignment = .center
        copyrightLabel.textColor = .secondaryLabelColor
        view.addSubview(copyrightLabel)

        // GitHub link
        let githubButton = NSButton(frame: NSRect(x: (viewWidth - 220) / 2, y: 90, width: 220, height: 32))
        githubButton.title = "github.com/J-Liu/Keystarter"
        githubButton.bezelStyle = .rounded
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        view.addSubview(githubButton)

        // Check for Updates button
        let checkUpdatesButton = NSButton(frame: NSRect(x: (viewWidth - 160) / 2, y: 50, width: 160, height: 32))
        checkUpdatesButton.title = L("menu.checkUpdates")
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.target = self
        checkUpdatesButton.action = #selector(checkForUpdatesNow)
        view.addSubview(checkUpdatesButton)

        return view
    }

    // MARK: - Layout Helpers

    private func addLabel(_ text: String, to view: NSView, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: labelX, y: y, width: 120, height: 24)
        label.alignment = .right
        view.addSubview(label)
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
        let hasAccessibility = PermissionManager.shared.hasAccessibilityPermission()

        if !hasAccessibility {
            // 没有权限，直接弹系统对话框
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
            ] as CFDictionary)
        } else {
            // 有权限，显示权限状态界面
            showPermissionsStatus()
        }
    }

    private func showPermissionsStatus() {
        let alert = NSAlert()
        alert.messageText = "权限状态"
        alert.informativeText = "所有必需权限已授予："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")

        // 创建自定义视图显示权限列表
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))

        // Accessibility 权限
        let accessibilityIcon = NSImageView(frame: NSRect(x: 10, y: 45, width: 20, height: 20))
        accessibilityIcon.image = NSImage(named: NSImage.statusAvailableName)
        containerView.addSubview(accessibilityIcon)

        let accessibilityLabel = NSTextField(labelWithString: "辅助功能 (Accessibility)")
        accessibilityLabel.frame = NSRect(x: 35, y: 45, width: 250, height: 20)
        containerView.addSubview(accessibilityLabel)

        // Input Monitoring 权限
        let inputIcon = NSImageView(frame: NSRect(x: 10, y: 15, width: 20, height: 20))
        inputIcon.image = NSImage(named: NSImage.statusAvailableName)
        containerView.addSubview(inputIcon)

        let inputLabel = NSTextField(labelWithString: "输入监控 (Input Monitoring)")
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
