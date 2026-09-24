// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Kills running processes by name.
/// Usage: "kill chrome" lists matching processes, Enter to kill.
final class KillPlugin: Plugin {

    let keyword = "kill"
    let pluginDescription = "Kill running processes by name"

    func query(_ input: String) -> [PluginResult] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()

        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        guard !query.isEmpty else {
            // Show all running apps
            return runningApps.prefix(20).map { app in
                createResult(for: app)
            }
        }

        // Filter by name match
        let matched = runningApps.filter { app in
            let name = (app.localizedName ?? "").lowercased()
            let bundleId = (app.bundleIdentifier ?? "").lowercased()
            return name.contains(query) || bundleId.contains(query)
        }

        guard !matched.isEmpty else {
            return [PluginResult(
                title: "No process matching \"\(query)\"",
                icon: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
            )]
        }

        return matched.map { createResult(for: $0) }
    }

    private func createResult(for app: NSRunningApplication) -> PluginResult {
        let name = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier

        // Get memory usage
        let memUsage = getMemoryUsage(pid: pid)
        let memString = formatBytes(memUsage)

        let subtitle = "PID: \(pid) • Memory: \(memString)"

        return PluginResult(
            title: name,
            subtitle: subtitle,
            icon: app.icon ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil),
            action: {
                kill(pid, SIGTERM)
            }
        )
    }

    private func getMemoryUsage(pid: pid_t) -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }

        if kr == KERN_SUCCESS {
            return info.resident_size
        }
        return 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb < 1 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        } else if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }
}
