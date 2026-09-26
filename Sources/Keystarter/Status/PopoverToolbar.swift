// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Shared toolbar for module popovers with Open, Settings, and Quit buttons.
final class PopoverToolbar {
    
    static let height: CGFloat = 24
    
    static func create(title: String, width: CGFloat) -> NSView {
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        
        // Title (centered)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.frame = NSRect(x: 40, y: 4, width: width - 100, height: 16)
        titleLabel.alignment = .center
        toolbar.addSubview(titleLabel)
        
        // Open button (left)
        let openButton = NSButton(frame: NSRect(x: 8, y: 2, width: 24, height: 20))
        openButton.bezelStyle = .inline
        openButton.isBordered = false
        openButton.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Open")
        openButton.imageScaling = .scaleNone
        openButton.contentTintColor = .labelColor
        openButton.target = ToolbarHandler.shared
        openButton.action = #selector(ToolbarHandler.openAction(_:))
        toolbar.addSubview(openButton)
        
        // Settings button (right, before quit)
        let settingsButton = NSButton(frame: NSRect(x: width - 60, y: 2, width: 24, height: 20))
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.imageScaling = .scaleNone
        settingsButton.contentTintColor = .labelColor
        settingsButton.target = ToolbarHandler.shared
        settingsButton.action = #selector(ToolbarHandler.settingsAction(_:))
        toolbar.addSubview(settingsButton)
        
        // Quit button (rightmost)
        let quitButton = NSButton(frame: NSRect(x: width - 32, y: 2, width: 24, height: 20))
        quitButton.bezelStyle = .inline
        quitButton.isBordered = false
        quitButton.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        quitButton.imageScaling = .scaleNone
        quitButton.contentTintColor = .labelColor
        quitButton.target = ToolbarHandler.shared
        quitButton.action = #selector(ToolbarHandler.quitAction(_:))
        toolbar.addSubview(quitButton)
        
        return toolbar
    }
}

final class ToolbarHandler: NSObject {
    static let shared = ToolbarHandler()
    
    @objc func openAction(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.showLauncher()
    }
    
    @objc func settingsAction(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.showSettings()
    }
    
    @objc func quitAction(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
