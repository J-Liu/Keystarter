// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Process network usage info.
struct ProcessNetworkInfo {
    let pid: Int32
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    let isApp: Bool
}

/// Network monitoring module.
final class NetworkModule: NSObject, StatusModule {
    
    var identifier: String { "network" }
    var displayName: String { L("status.network.displayName") }
    
    private(set) var summaryText: String = "↓-- ↑--"
    
    var icon: NSImage? {
        NSImage(systemSymbolName: "network", accessibilityDescription: "Network")
    }
    
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var previousTime: Date = Date()
    
    private var processStats: [ProcessNetworkInfo] = []
    private var previousProcessBytes: [Int32: (in: UInt64, out: UInt64)] = [:]
    
    func refreshSummary() {
        let (bytesIn, bytesOut) = getNetworkBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)
        
        if elapsed > 0 && previousTime != now {
            let bytesInDelta = bytesIn > previousBytesIn ? bytesIn - previousBytesIn : 0
            let bytesOutDelta = bytesOut > previousBytesOut ? bytesOut - previousBytesOut : 0
            
            let bytesInPerSec = Double(bytesInDelta) / elapsed
            let bytesOutPerSec = Double(bytesOutDelta) / elapsed
            
            summaryText = "↓\(formatSpeed(bytesInPerSec)) ↑\(formatSpeed(bytesOutPerSec))"
        }
        
        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        previousTime = now
        
        // Also refresh process-level stats
        refreshProcessStats(elapsed: elapsed)
    }
    
    func makeDetailView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 450))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 420, width: 200, height: 20)
        container.addSubview(headerView)
        
        // Total rates
        let totalLabel = NSTextField(labelWithString: "Total: \(summaryText)")
        totalLabel.font = .systemFont(ofSize: 12)
        totalLabel.textColor = .secondaryLabelColor
        totalLabel.frame = NSRect(x: 16, y: 395, width: 200, height: 16)
        container.addSubview(totalLabel)
        
        // Process table
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 380))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 160
        tableView.addTableColumn(nameColumn)
        
        let inColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("in"))
        inColumn.width = 80
        tableView.addTableColumn(inColumn)
        
        let outColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("out"))
        outColumn.width = 80
        tableView.addTableColumn(outColumn)
        
        tableView.dataSource = self
        tableView.delegate = self
        
        scrollView.documentView = tableView
        container.addSubview(scrollView)
        
        return container
    }
    
    // MARK: - Network Data
    
    private func getNetworkBytes() -> (in: UInt64, out: UInt64) {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }
        
        var ptr = firstAddr
        while true {
            let addr = ptr.pointee
            
            if let name = addr.ifa_name {
                let ifaName = String(cString: name)
                if ifaName.hasPrefix("en") || ifaName.hasPrefix("awdl") || ifaName.hasPrefix("llw") {
                    if let data = addr.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        bytesIn += UInt64(networkData.ifi_ibytes)
                        bytesOut += UInt64(networkData.ifi_obytes)
                    }
                }
            }
            
            guard let next = addr.ifa_next else { break }
            ptr = next
        }
        
        freeifaddrs(ifaddr)
        return (bytesIn, bytesOut)
    }
    
    // MARK: - Process Network Stats
    
    private func refreshProcessStats(elapsed: TimeInterval) {
        // Get process network stats via nettop
        // nettop -P -L 1 -J bytes_in,bytes_out -x
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                parseNettopOutput(output, elapsed: elapsed)
            }
        } catch {
            // nettop failed, keep previous stats
        }
    }
    
    private func parseNettopOutput(_ output: String, elapsed: TimeInterval) {
        var stats: [ProcessNetworkInfo] = []
        var seenPids = Set<Int32>()
        
        // Skip header lines and parse data
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { continue }
            
            // Parse process name (format: "AppName.123" where 123 is PID)
            let processInfo = parts[0]
            guard let dotIndex = processInfo.lastIndex(of: ".") else { continue }
            
            let pidString = String(processInfo[processInfo.index(after: dotIndex)...])
            guard let pid = Int32(pidString) else { continue }
            
            // Skip duplicates
            if seenPids.contains(pid) { continue }
            seenPids.insert(pid)
            
            let name = String(processInfo[..<dotIndex])
            
            // Parse bytes
            let bytesIn = UInt64(parts[1]) ?? 0
            let bytesOut = UInt64(parts[2]) ?? 0
            
            // Check if it's an app
            let isApp = isAppBundle(pid: pid)
            
            stats.append(ProcessNetworkInfo(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut, isApp: isApp))
        }
        
        // Sort by total bytes
        stats.sort { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) }
        
        // Limit to top 30
        processStats = Array(stats.prefix(30))
    }
    
    private func isAppBundle(pid: Int32) -> Bool {
        // Check if process has a bundle URL
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.processIdentifier == pid && $0.bundleURL != nil }
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0fK", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f", bytesPerSec)
        }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1fG", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1fM", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.0fK", Double(bytes) / 1024)
        } else {
            return String(format: "%llu", bytes)
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension NetworkModule: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return processStats.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < processStats.count else { return nil }
        let info = processStats[row]
        
        let cell = NSTableCellView()
        
        if tableColumn?.identifier.rawValue == "name" {
            var displayName = info.name
            // Mark non-app processes with ⚠️
            if !info.isApp {
                displayName = "⚠️ " + displayName
            }
            
            let label = NSTextField(labelWithString: displayName)
            label.font = .systemFont(ofSize: 12)
            if !info.isApp {
                label.textColor = .systemOrange
            }
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 8, y: 4, width: 140, height: 16)
            cell.addSubview(label)
        } else if tableColumn?.identifier.rawValue == "in" {
            let label = NSTextField(labelWithString: "↓\(formatBytes(info.bytesIn))")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .systemBlue
            label.alignment = .right
            label.frame = NSRect(x: 0, y: 4, width: 64, height: 16)
            cell.addSubview(label)
        } else {
            let label = NSTextField(labelWithString: "↑\(formatBytes(info.bytesOut))")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .systemGreen
            label.alignment = .right
            label.frame = NSRect(x: 0, y: 4, width: 64, height: 16)
            cell.addSubview(label)
        }
        
        return cell
    }
}