// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Manages log settings for different modules.
final class LogSettings {

    static let shared = LogSettings()

    private init() {}

    // MARK: - General Log

    var generalLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "general.log.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "general.log.enabled") }
    }

    var generalLogPath: String {
        get {
            let defaultPath = NSHomeDirectory() + "/Library/Application Support/Keystarter/general.log"
            return UserDefaults.standard.string(forKey: "general.log.path") ?? defaultPath
        }
        set { UserDefaults.standard.set(newValue, forKey: "general.log.path") }
    }

    // MARK: - Clipboard Log

    var clipboardLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "clipboard.log.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "clipboard.log.enabled") }
    }

    var clipboardLogPath: String {
        get {
            let defaultPath = NSHomeDirectory() + "/Library/Application Support/Keystarter/clipboard.log"
            return UserDefaults.standard.string(forKey: "clipboard.log.path") ?? defaultPath
        }
        set { UserDefaults.standard.set(newValue, forKey: "clipboard.log.path") }
    }
}
