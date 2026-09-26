// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit

/// Disk monitoring module.
final class DiskModule: NSObject, StatusModule {
    
    var identifier: String { "disk" }
    var displayName: String { L("status.disk.displayName") }
    
    private(set) var summaryText: String = "R-- W--"
    
    var icon: NSImage? {
        NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "Disk")
    }
    
    private var previousReadBytes: UInt64 = 0
    private var previousWriteBytes: UInt64 = 0
    private var previousTime: Date = Date()
    
    func refreshSummary() {
        let (readBytes, writeBytes) = getDiskBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTime)
        
        if elapsed > 0 && previousTime != now {
            let readDelta = readBytes > previousReadBytes ? readBytes - previousReadBytes : 0
            let writeDelta = writeBytes > previousWriteBytes ? writeBytes - previousWriteBytes : 0
            
            let readPerSec = Double(readDelta) / elapsed
            let writePerSec = Double(writeDelta) / elapsed
            
            summaryText = "R\(formatSpeed(readPerSec)) W\(formatSpeed(writePerSec))"
        }
        
        previousReadBytes = readBytes
        previousWriteBytes = writeBytes
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
        let readLabel = NSTextField(labelWithString: "R Read: \(summaryText.split(separator: " ").first ?? "--")")
        readLabel.font = .systemFont(ofSize: 13)
        readLabel.frame = NSRect(x: 16, y: 60, width: 250, height: 20)
        readLabel.identifier = NSUserInterfaceItemIdentifier("readLabel")
        container.addSubview(readLabel)
        
        let writeLabel = NSTextField(labelWithString: "W Write: \(summaryText.split(separator: " ").last ?? "--")")
        writeLabel.font = .systemFont(ofSize: 13)
        writeLabel.frame = NSRect(x: 16, y: 30, width: 250, height: 20)
        writeLabel.identifier = NSUserInterfaceItemIdentifier("writeLabel")
        container.addSubview(writeLabel)
        
        return container
    }
    
    // MARK: - Disk Data
    
    private func getDiskBytes() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        
        // Get IOKit service for block storage drivers
        let masterPort = kIOMainPortDefault
        var iterator: io_iterator_t = 0
        
        let matching = IOServiceMatching("IOBlockStorageDriver")
        let result = IOServiceGetMatchingServices(masterPort, matching, &iterator)
        
        guard result == KERN_SUCCESS, iterator != 0 else {
            return (0, 0)
        }
        
        defer {
            IOObjectRelease(iterator)
        }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = props["Statistics"] as? [String: Any] else {
                continue
            }
            
            // Read and write bytes from statistics
            if let read = statistics["BytesRead"] as? UInt64 {
                totalRead += read
            }
            if let write = statistics["BytesWritten"] as? UInt64 {
                totalWrite += write
            }
        }
        
        return (totalRead, totalWrite)
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