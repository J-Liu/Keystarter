// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

struct LaunchItem {

    enum ItemType {
        case application
        case command
        case file
    }

    let name: String
    let path: String
    let type: ItemType

    /// Optional action for plugin results. If set, overrides default execute().
    var pluginAction: (() -> Void)?
    /// Optional icon for plugin results.
    var pluginIcon: NSImage?

    var icon: NSImage? {
        if let pluginIcon = pluginIcon { return pluginIcon }
        switch type {
        case .application, .file:
            return NSWorkspace.shared.icon(forFile: path)
        case .command:
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        }
    }

    func execute() {
        if let pluginAction = pluginAction {
            pluginAction()
            return
        }
        switch type {
        case .application, .file:
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .command:
            break
        }
    }
}
