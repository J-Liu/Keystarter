// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

struct LaunchItem {

    enum ItemType {
        case application
        case command
        case file
        case bookmark
        case history
        case clipboard
    }

    let name: String
    let path: String
    let type: ItemType
    let category: String?

    /// Optional action for plugin results. If set, overrides default execute().
    var pluginAction: (() -> Void)?
    /// Optional icon for plugin results.
    var pluginIcon: NSImage?
    /// Optional detail text for preview panel.
    var detailText: String?

    var icon: NSImage? {
        if let pluginIcon = pluginIcon { return pluginIcon }
        switch type {
        case .application, .file:
            return NSWorkspace.shared.icon(forFile: path)
        case .command:
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        case .bookmark, .history:
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        case .clipboard:
            return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        }
    }

    func execute() {
        if let pluginAction = pluginAction {
            pluginAction()
            return
        }
        switch type {
        case .application, .file:
            LaunchHistory.shared.record(identifier: path)
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .command:
            break
        case .bookmark, .history:
            if let url = URL(string: path) {
                NSWorkspace.shared.open(url)
            }
        case .clipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}
