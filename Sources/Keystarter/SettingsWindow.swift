// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Settings window with tabs for configuration.
final class SettingsWindow: NSWindow {

    private var tabView: NSTabView!
    private var generalTab: NSView!
    private var clipboardTab: NSView!
    private var aboutTab: NSView!
    private var hotkeyRecorder: HotkeyRecorderButton!

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 600
        let height: CGFloat = 500
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
        tabView = NSTabView(frame: contentView!.bounds.insetBy(dx: 20, dy: 20))
        tabView.autoresizingMask = [.width, .height]

        // General tab
        generalTab = createGeneralTab()
        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = generalTab
        tabView.addTabViewItem(generalItem)

        // Clipboard tab
        clipboardTab = createClipboardTab()
        let clipboardItem = NSTabViewItem(identifier: "clipboard")
        clipboardItem.label = "Clipboard"
        clipboardItem.view = clipboardTab
        tabView.addTabViewItem(clipboardItem)

        // About tab
        aboutTab = createAboutTab()
        let aboutItem = NSTabViewItem(identifier: "about")
        aboutItem.label = "About"
        aboutItem.view = aboutTab
        tabView.addTabViewItem(aboutItem)

        contentView?.addSubview(tabView)
    }

    private func createGeneralTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))

        // Hotkey
        let hotkeyLabel = NSTextField(labelWithString: "Hotkey:")
        hotkeyLabel.frame = NSRect(x: 0, y: 380, width: 100, height: 24)
        view.addSubview(hotkeyLabel)

        hotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: 110, y: 376, width: 150, height: 32))
        hotkeyRecorder.onKeyRecorded = { [weak self] recorder in
            self?.hotkeyChanged(recorder: recorder)
        }
        // Load saved hotkey
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkey.keyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkey.modifiers")
        if savedKeyCode > 0 {
            hotkeyRecorder.setShortcut(keyCode: UInt16(savedKeyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(savedModifiers)))
        } else {
            hotkeyRecorder.setShortcut(keyCode: UInt16(49), modifiers: .command) // Space + Command
        }
        view.addSubview(hotkeyRecorder)

        // Hotkey hint label
        let hotkeyHint = NSTextField(labelWithString: "Click to record")
        hotkeyHint.frame = NSRect(x: 270, y: 380, width: 150, height: 24)
        hotkeyHint.textColor = .secondaryLabelColor
        hotkeyHint.font = .systemFont(ofSize: 12)
        view.addSubview(hotkeyHint)

        // Status Bar Icon
        let statusBarLabel = NSTextField(labelWithString: "Status Bar:")
        statusBarLabel.frame = NSRect(x: 0, y: 330, width: 100, height: 24)
        view.addSubview(statusBarLabel)

        let statusBarPopup = NSPopUpButton(frame: NSRect(x: 110, y: 326, width: 200, height: 32))
        statusBarPopup.addItem(withTitle: "System Default")
        statusBarPopup.addItem(withTitle: "Light")
        statusBarPopup.addItem(withTitle: "Dark")
        statusBarPopup.addItem(withTitle: "Hidden")
        let savedTheme = UserDefaults.standard.string(forKey: "statusBar.theme") ?? "system"
        statusBarPopup.selectItem(withTitle: themeName(for: savedTheme))
        statusBarPopup.target = self
        statusBarPopup.action = #selector(statusBarThemeChanged(_:))
        view.addSubview(statusBarPopup)

        // Corner Radius
        let radiusLabel = NSTextField(labelWithString: "Corner Radius:")
        radiusLabel.frame = NSRect(x: 0, y: 280, width: 100, height: 24)
        view.addSubview(radiusLabel)

        let radiusSlider = NSSlider(frame: NSRect(x: 110, y: 280, width: 200, height: 24))
        radiusSlider.minValue = 0
        radiusSlider.maxValue = 24
        radiusSlider.doubleValue = Double(AppearanceSettings.cornerRadius)
        radiusSlider.target = self
        radiusSlider.action = #selector(radiusChanged(_:))
        view.addSubview(radiusSlider)

        let radiusValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.cornerRadius))")
        radiusValue.frame = NSRect(x: 320, y: 280, width: 40, height: 24)
        radiusValue.identifier = NSUserInterfaceItemIdentifier("radiusValue")
        view.addSubview(radiusValue)

        // Opacity
        let opacityLabel = NSTextField(labelWithString: "Opacity:")
        opacityLabel.frame = NSRect(x: 0, y: 230, width: 100, height: 24)
        view.addSubview(opacityLabel)

        let opacitySlider = NSSlider(frame: NSRect(x: 110, y: 230, width: 200, height: 24))
        opacitySlider.minValue = 0.5
        opacitySlider.maxValue = 1.0
        opacitySlider.doubleValue = Double(AppearanceSettings.opacity)
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        view.addSubview(opacitySlider)

        let opacityValue = NSTextField(labelWithString: "\(Int(AppearanceSettings.opacity * 100))%")
        opacityValue.frame = NSRect(x: 320, y: 230, width: 50, height: 24)
        opacityValue.identifier = NSUserInterfaceItemIdentifier("opacityValue")
        view.addSubview(opacityValue)

        // Group By
        let groupByLabel = NSTextField(labelWithString: "Group By:")
        groupByLabel.frame = NSRect(x: 0, y: 185, width: 100, height: 24)
        view.addSubview(groupByLabel)

        let groupByPopup = NSPopUpButton(frame: NSRect(x: 110, y: 181, width: 200, height: 32))
        groupByPopup.addItem(withTitle: "Category")
        groupByPopup.addItem(withTitle: "Letter")
        let savedGroupBy = UserDefaults.standard.string(forKey: "launcher.groupBy") ?? "category"
        groupByPopup.selectItem(withTitle: savedGroupBy == "letter" ? "Letter" : "Category")
        groupByPopup.target = self
        groupByPopup.action = #selector(groupByChanged(_:))
        view.addSubview(groupByPopup)

        // Start at Login
        let loginLabel = NSTextField(labelWithString: "Start at Login:")
        loginLabel.frame = NSRect(x: 0, y: 145, width: 100, height: 24)
        view.addSubview(loginLabel)

        let loginCheckbox = NSButton(checkboxWithTitle: "Automatically start at login", target: self, action: #selector(loginItemChanged(_:)))
        loginCheckbox.frame = NSRect(x: 110, y: 144, width: 250, height: 24)
        loginCheckbox.state = UserDefaults.standard.bool(forKey: "startAtLogin") ? .on : .off
        view.addSubview(loginCheckbox)

        // Show Dock Icon
        let dockIconLabel = NSTextField(labelWithString: "Dock Icon:")
        dockIconLabel.frame = NSRect(x: 0, y: 115, width: 100, height: 24)
        view.addSubview(dockIconLabel)

        let dockIconCheckbox = NSButton(checkboxWithTitle: "Show Dock icon", target: self, action: #selector(dockIconChanged(_:)))
        dockIconCheckbox.frame = NSRect(x: 110, y: 114, width: 200, height: 24)
        dockIconCheckbox.state = UserDefaults.standard.bool(forKey: "showDockIcon") ? .on : .off
        view.addSubview(dockIconCheckbox)

        // Enable Log
        let enableLogCheckbox = NSButton(checkboxWithTitle: "Enable log", target: self, action: #selector(generalLogEnabledChanged(_:)))
        enableLogCheckbox.frame = NSRect(x: 110, y: 85, width: 120, height: 24)
        enableLogCheckbox.state = LogSettings.shared.generalLogEnabled ? .on : .off
        view.addSubview(enableLogCheckbox)

        // Log path (read-only)
        let logPathField = NSTextField(frame: NSRect(x: 240, y: 85, width: 200, height: 24))
        logPathField.stringValue = LogSettings.shared.generalLogPath
        logPathField.isEditable = false
        logPathField.isBezeled = false
        logPathField.drawsBackground = false
        logPathField.font = .systemFont(ofSize: 11)
        logPathField.lineBreakMode = .byTruncatingMiddle
        logPathField.identifier = NSUserInterfaceItemIdentifier("generalLogPath")
        view.addSubview(logPathField)

        // Choose log file button
        let chooseLogButton = NSButton(frame: NSRect(x: 450, y: 84, width: 80, height: 24))
        chooseLogButton.title = "Choose..."
        chooseLogButton.bezelStyle = .rounded
        chooseLogButton.target = self
        chooseLogButton.action = #selector(chooseGeneralLogFile)
        view.addSubview(chooseLogButton)

        // Check Permissions button
        let permissionsButton = NSButton(frame: NSRect(x: 0, y: 40, width: 200, height: 32))
        permissionsButton.title = "Check Permissions..."
        permissionsButton.bezelStyle = .rounded
        permissionsButton.target = self
        permissionsButton.action = #selector(checkPermissions)
        view.addSubview(permissionsButton)

        return view
    }

    private func themeName(for key: String) -> String {
        switch key {
        case "light": return "Light"
        case "dark": return "Dark"
        case "hidden": return "Hidden"
        default: return "System Default"
        }
    }

    private func hotkeyChanged(recorder: HotkeyRecorderButton) {
        (NSApp.delegate as? AppDelegate)?.updateHotkey(keyCode: recorder.keyCode, modifiers: recorder.modifiers)
    }

    @objc private func statusBarThemeChanged(_ sender: NSPopUpButton) {
        let theme: String
        switch sender.title {
        case "Light": theme = "light"
        case "Dark": theme = "dark"
        case "Hidden": theme = "hidden"
        default: theme = "system"
        }
        UserDefaults.standard.set(theme, forKey: "statusBar.theme")
        (NSApp.delegate as? AppDelegate)?.updateStatusBarTheme(theme)
    }

    @objc private func groupByChanged(_ sender: NSPopUpButton) {
        let groupBy = sender.title == "Letter" ? "letter" : "category"
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

    @objc private func checkPermissions() {
        PermissionManager.shared.requestAllPermissions {
            // Permissions granted
        }
    }

    private func createClipboardTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))

        // Hotkey
        let hotkeyLabel = NSTextField(labelWithString: "Hotkey:")
        hotkeyLabel.frame = NSRect(x: 0, y: 280, width: 100, height: 24)
        view.addSubview(hotkeyLabel)

        let clipboardHotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: 110, y: 276, width: 150, height: 32))
        clipboardHotkeyRecorder.onKeyRecorded = { [weak self] recorder in
            self?.clipboardHotkeyChanged(recorder: recorder)
        }
        let savedKeyCode = UserDefaults.standard.integer(forKey: "clipboard.hotkey.keyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "clipboard.hotkey.modifiers")
        if savedKeyCode > 0 {
            clipboardHotkeyRecorder.setShortcut(keyCode: UInt16(savedKeyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(savedModifiers)))
        } else {
            clipboardHotkeyRecorder.setShortcut(keyCode: UInt16(9), modifiers: [.command, .shift]) // V + Cmd + Shift
        }
        view.addSubview(clipboardHotkeyRecorder)

        let hotkeyHint = NSTextField(labelWithString: "Click to record")
        hotkeyHint.frame = NSRect(x: 270, y: 280, width: 150, height: 24)
        hotkeyHint.textColor = .secondaryLabelColor
        hotkeyHint.font = .systemFont(ofSize: 12)
        view.addSubview(hotkeyHint)

        // Max count
        let maxCountLabel = NSTextField(labelWithString: "Max Count:")
        maxCountLabel.frame = NSRect(x: 0, y: 230, width: 100, height: 24)
        view.addSubview(maxCountLabel)

        let maxCountField = NSTextField(frame: NSRect(x: 110, y: 230, width: 80, height: 24))
        maxCountField.stringValue = String(UserDefaults.standard.integer(forKey: "clipboard.maxCount") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxCount") : 500)
        maxCountField.target = self
        maxCountField.action = #selector(clipboardMaxCountChanged(_:))
        view.addSubview(maxCountField)

        let maxCountHint = NSTextField(labelWithString: "entries (groups: \((UserDefaults.standard.integer(forKey: "clipboard.maxCount") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxCount") : 500) / 10 + 1))")
        maxCountHint.frame = NSRect(x: 200, y: 230, width: 150, height: 24)
        maxCountHint.textColor = .secondaryLabelColor
        maxCountHint.identifier = NSUserInterfaceItemIdentifier("maxCountHint")
        view.addSubview(maxCountHint)

        // Max days
        let maxDaysLabel = NSTextField(labelWithString: "Max Days:")
        maxDaysLabel.frame = NSRect(x: 0, y: 180, width: 100, height: 24)
        view.addSubview(maxDaysLabel)

        let maxDaysField = NSTextField(frame: NSRect(x: 110, y: 180, width: 80, height: 24))
        maxDaysField.stringValue = String(UserDefaults.standard.integer(forKey: "clipboard.maxDays") > 0 ? UserDefaults.standard.integer(forKey: "clipboard.maxDays") : 30)
        maxDaysField.target = self
        maxDaysField.action = #selector(clipboardMaxDaysChanged(_:))
        view.addSubview(maxDaysField)

        let maxDaysHint = NSTextField(labelWithString: "days")
        maxDaysHint.frame = NSRect(x: 200, y: 180, width: 60, height: 24)
        maxDaysHint.textColor = .secondaryLabelColor
        view.addSubview(maxDaysHint)

        // Enable Log
        let enableLogCheckbox = NSButton(checkboxWithTitle: "Enable log", target: self, action: #selector(clipboardLogEnabledChanged(_:)))
        enableLogCheckbox.frame = NSRect(x: 110, y: 130, width: 120, height: 24)
        enableLogCheckbox.state = LogSettings.shared.clipboardLogEnabled ? .on : .off
        view.addSubview(enableLogCheckbox)

        // Log path (read-only)
        let logPathField = NSTextField(frame: NSRect(x: 240, y: 130, width: 150, height: 24))
        logPathField.stringValue = LogSettings.shared.clipboardLogPath
        logPathField.isEditable = false
        logPathField.isBezeled = false
        logPathField.drawsBackground = false
        logPathField.font = .systemFont(ofSize: 11)
        logPathField.lineBreakMode = .byTruncatingMiddle
        logPathField.identifier = NSUserInterfaceItemIdentifier("clipboardLogPath")
        view.addSubview(logPathField)

        // Choose log file button
        let chooseLogButton = NSButton(frame: NSRect(x: 395, y: 129, width: 60, height: 24))
        chooseLogButton.title = "Choose..."
        chooseLogButton.bezelStyle = .rounded
        chooseLogButton.target = self
        chooseLogButton.action = #selector(chooseClipboardLogFile)
        view.addSubview(chooseLogButton)

        // Clear button
        let clearButton = NSButton(frame: NSRect(x: 0, y: 80, width: 180, height: 32))
        clearButton.title = "Clear Clipboard History"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearClipboardHistory)
        view.addSubview(clearButton)

        return view
    }

    private func clipboardHotkeyChanged(recorder: HotkeyRecorderButton) {
        UserDefaults.standard.set(Int(recorder.keyCode), forKey: "clipboard.hotkey.keyCode")
        UserDefaults.standard.set(Int(recorder.modifiers.rawValue), forKey: "clipboard.hotkey.modifiers")
        (NSApp.delegate as? AppDelegate)?.updateClipboardHotkey(keyCode: recorder.keyCode, modifiers: recorder.modifiers)
    }

    @objc private func clipboardMaxCountChanged(_ sender: NSTextField) {
        if let value = Int(sender.stringValue) {
            UserDefaults.standard.set(value, forKey: "clipboard.maxCount")
            // Update groups hint
            if let view = sender.superview,
               let hint = view.subviews.first(where: { $0.identifier?.rawValue == "maxCountHint" }) as? NSTextField {
                hint.stringValue = "entries (groups: \(value / 10 + 1))"
            }
        }
    }

    @objc private func clipboardMaxDaysChanged(_ sender: NSTextField) {
        if let value = Int(sender.stringValue) {
            UserDefaults.standard.set(value, forKey: "clipboard.maxDays")
        }
    }

    @objc private func generalLogEnabledChanged(_ sender: NSButton) {
        LogSettings.shared.generalLogEnabled = sender.state == .on
    }

    @objc private func chooseGeneralLogFile() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = URL(fileURLWithPath: LogSettings.shared.generalLogPath).deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            LogSettings.shared.generalLogPath = path
            // Update the text field
            if let textField = generalTab?.subviews.first(where: { $0.identifier?.rawValue == "generalLogPath" }) as? NSTextField {
                textField.stringValue = path
            }
        }
    }

    @objc private func clipboardLogEnabledChanged(_ sender: NSButton) {
        LogSettings.shared.clipboardLogEnabled = sender.state == .on
    }

    @objc private func chooseClipboardLogFile() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = URL(fileURLWithPath: LogSettings.shared.clipboardLogPath).deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            LogSettings.shared.clipboardLogPath = path
            // Update the text field
            if let textField = clipboardTab?.subviews.first(where: { $0.identifier?.rawValue == "clipboardLogPath" }) as? NSTextField {
                textField.stringValue = path
            }
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
            (NSApp.delegate as? AppDelegate)?.indexDB?.clearClipboard()
        }
    }

    private func createAboutTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))

        // App Icon
        let appIcon = NSImageView(frame: NSRect(x: 190, y: 240, width: 80, height: 80))
        if let icnsPath = Bundle.main.path(forResource: "Keystarter", ofType: "icns"),
           let image = NSImage(contentsOfFile: icnsPath) {
            appIcon.image = image
        } else {
            // Fallback to system icon
            appIcon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            appIcon.contentTintColor = .controlAccentColor
        }
        view.addSubview(appIcon)

        // App Name
        let nameLabel = NSTextField(labelWithString: "Keystarter")
        nameLabel.frame = NSRect(x: 0, y: 200, width: 460, height: 28)
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        view.addSubview(nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.frame = NSRect(x: 0, y: 170, width: 460, height: 20)
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        view.addSubview(versionLabel)

        // Copyright
        let copyrightLabel = NSTextField(labelWithString: "© 2026 Jia Liu. All rights reserved.")
        copyrightLabel.frame = NSRect(x: 0, y: 140, width: 460, height: 20)
        copyrightLabel.alignment = .center
        copyrightLabel.textColor = .secondaryLabelColor
        view.addSubview(copyrightLabel)

        // GitHub link
        let githubButton = NSButton(frame: NSRect(x: 130, y: 80, width: 200, height: 32))
        githubButton.title = "github.com/J-Liu/Keystarter"
        githubButton.bezelStyle = .rounded
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        view.addSubview(githubButton)

        return view
    }

    private func setupKeyHandlers() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            // Don't intercept keys when hotkey recorder is active
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

    @objc private func radiusChanged(_ sender: NSSlider) {
        AppearanceSettings.cornerRadius = CGFloat(sender.doubleValue)
        AppearanceSettings.save()
        if let label = generalTab.viewWithTag(1) as? NSTextField ?? 
                      generalViewWithIdentifier("radiusValue") {
            label.stringValue = "\(Int(sender.doubleValue))"
        }
    }

    private func generalViewWithIdentifier(_ id: String) -> NSTextField? {
        return generalTab.subviews.first { $0.identifier?.rawValue == id } as? NSTextField
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        AppearanceSettings.opacity = CGFloat(sender.doubleValue)
        AppearanceSettings.save()
        if let label = generalViewWithIdentifier("opacityValue") {
            label.stringValue = "\(Int(sender.doubleValue * 100))%"
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Launch History?"
        alert.informativeText = "This will reset the frequency ranking for all applications."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            // Clear history file
            let path = NSHomeDirectory() + "/Library/Application Support/Keystarter/history.plist"
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @objc private func rebuildIndex() {
        let alert = NSAlert()
        alert.messageText = "Rebuild File Index?"
        alert.informativeText = "This will re-scan Documents, Desktop, and Downloads."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Rebuild")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            (NSApp.delegate as? AppDelegate)?.rebuildIndex()
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