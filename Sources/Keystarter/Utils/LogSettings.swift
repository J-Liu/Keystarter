// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Manages log settings for different features.
final class LogSettings {

    static let shared = LogSettings()

    private init() {}

    // MARK: - Launcher Log

    var launcherLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "launcher.log.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "launcher.log.enabled") }
    }

    var launcherLogPath: String {
        get {
            let defaultPath = NSHomeDirectory() + "/Library/Application Support/Keystarter/launcher.log"
            return UserDefaults.standard.string(forKey: "launcher.log.path") ?? defaultPath
        }
        set { UserDefaults.standard.set(newValue, forKey: "launcher.log.path") }
    }

    // MARK: - Monitor Log

    var monitorLogEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "monitor.log.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "monitor.log.enabled") }
    }

    var monitorLogPath: String {
        get {
            let defaultPath = NSHomeDirectory() + "/Library/Application Support/Keystarter/monitor.log"
            return UserDefaults.standard.string(forKey: "monitor.log.path") ?? defaultPath
        }
        set { UserDefaults.standard.set(newValue, forKey: "monitor.log.path") }
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

    // MARK: - Helper

    /// Write log to file.
    static func write(_ message: String, to path: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}