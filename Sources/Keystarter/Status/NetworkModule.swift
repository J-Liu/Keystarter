// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

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
    }
    
    func makeDetailView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 90, width: 200, height: 20)
        container.addSubview(headerView)
        
        // Current rates
        let inLabel = NSTextField(labelWithString: "↓ Download: \(summaryText.split(separator: " ").first ?? "--")")
        inLabel.font = .systemFont(ofSize: 13)
        inLabel.frame = NSRect(x: 16, y: 60, width: 250, height: 20)
        inLabel.identifier = NSUserInterfaceItemIdentifier("inLabel")
        container.addSubview(inLabel)
        
        let outLabel = NSTextField(labelWithString: "↑ Upload: \(summaryText.split(separator: " ").last ?? "--")")
        outLabel.font = .systemFont(ofSize: 13)
        outLabel.frame = NSRect(x: 16, y: 30, width: 250, height: 20)
        outLabel.identifier = NSUserInterfaceItemIdentifier("outLabel")
        container.addSubview(outLabel)
        
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
            
            // Only count active interfaces (en0, en1, etc. - WiFi/Ethernet)
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
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 { // 1 MB/s
            return String(format: "%.1fM", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 { // 1 KB/s
            return String(format: "%.0fK", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f", bytesPerSec)
        }
    }
}