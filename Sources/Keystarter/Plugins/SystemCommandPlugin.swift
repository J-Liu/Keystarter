// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Executes common system commands.
/// Usage: "sleep", "lock", "empty trash", "restart", "shutdown", "logout"
final class SystemCommandPlugin: Plugin {

    let keyword = ""
    let pluginDescription = "Execute system commands like sleep, lock, restart"

    private let commands: [(String, String, String)] = [
        ("sleep", "Sleep", "pmset sleepnow"),
        ("lock", "Lock Screen", "/System/Library/CoreServices/Menu\\ Extras/User.menu/Contents/Resources/CGSession -suspend"),
        ("empty trash", "Empty Trash", "osascript -e 'tell application \"Finder\" to empty the trash'"),
        ("restart", "Restart", "osascript -e 'tell app \"System Events\" to restart'"),
        ("shutdown", "Shut Down", "osascript -e 'tell app \"System Events\" to shut down'"),
        ("logout", "Log Out", "osascript -e 'tell app \"System Events\" to log out'")
    ]

    func matchesDirect(_ input: String) -> Bool {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        return commands.contains { $0.0.hasPrefix(query) || query.hasPrefix($0.0) }
    }

    func queryDirect(_ input: String) -> [PluginResult] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()

        let matched = commands.filter { $0.0.hasPrefix(query) || query.hasPrefix($0.0) }

        guard !matched.isEmpty else {
            return []
        }

        return matched.map { cmd in
            // Use trash icon for empty trash command
            let iconName = cmd.0 == "empty trash" ? "trash" : "power"
            let title = L("command.\(cmd.0.replacingOccurrences(of: " ", with: "."))")

            return PluginResult(
                title: title,
                subtitle: String(format: L("command.pressEnter"), title.lowercased()),
                icon: NSImage(systemSymbolName: iconName, accessibilityDescription: nil),
                action: {
                    let task = Process()
                    task.launchPath = "/bin/bash"
                    task.arguments = ["-c", cmd.2]
                    try? task.run()
                }
            )
        }
    }

    func query(_ input: String) -> [PluginResult] {
        return []
    }
}
