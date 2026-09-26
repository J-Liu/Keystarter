// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit

/// GPU monitoring module.
final class GPUModule: NSObject, StatusModule {
    
    var identifier: String { "gpu" }
    var displayName: String { L("status.gpu.displayName") }
    
    private(set) var summaryText: String = "GPU --%"
    
    var icon: NSImage? {
        NSImage(systemSymbolName: "cpu.fill", accessibilityDescription: "GPU")
    }
    
    private var gpuUsage: Double = 0
    private var vramUsed: UInt64 = 0
    private var vramTotal: UInt64 = 0
    
    func refreshSummary() {
        let (usage, vramUsed, vramTotal) = getGPUInfo()
        self.gpuUsage = usage
        self.vramUsed = vramUsed
        self.vramTotal = vramTotal
        
        summaryText = String(format: "GPU %.0f%%", usage)
    }
    
    func makeDetailView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 150))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 120, width: 200, height: 20)
        container.addSubview(headerView)
        
        // GPU Usage
        let usageLabel = NSTextField(labelWithString: String(format: "Usage: %.1f%%", gpuUsage))
        usageLabel.font = .systemFont(ofSize: 13)
        usageLabel.frame = NSRect(x: 16, y: 90, width: 250, height: 20)
        container.addSubview(usageLabel)
        
        // VRAM
        let vramUsedGB = Double(vramUsed) / 1_073_741_824.0
        let vramTotalGB = Double(vramTotal) / 1_073_741_824.0
        let vramLabel = NSTextField(labelWithString: String(format: "VRAM: %.1f / %.1f GB", vramUsedGB, vramTotalGB))
        vramLabel.font = .systemFont(ofSize: 13)
        vramLabel.frame = NSRect(x: 16, y: 60, width: 250, height: 20)
        container.addSubview(vramLabel)
        
        // Note
        let noteLabel = NSTextField(labelWithString: L("status.gpu.note"))
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.frame = NSRect(x: 16, y: 30, width: 250, height: 20)
        container.addSubview(noteLabel)
        
        return container
    }
    
    // MARK: - GPU Data
    
    private func getGPUInfo() -> (usage: Double, vramUsed: UInt64, vramTotal: UInt64) {
        var gpuUsage: Double = 0
        var vramUsed: UInt64 = 0
        var vramTotal: UInt64 = 0
        
        // Find GPU accelerator using IOKit
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS, iterator != 0 else {
            return (0, 0, 0)
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
            
            // Get performance statistics
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = props["PerformanceStatistics"] as? [String: Any] else {
                continue
            }
            
            // Try to get GPU utilization
            // Different GPUs report differently
            if let deviceUtil = statistics["Device Utilization"] as? Double {
                gpuUsage = deviceUtil * 100
            } else if let utilization = statistics["utilization"] as? Double {
                gpuUsage = utilization
            }
            
            // VRAM info
            if let vramFree = statistics["vramFreeBytes"] as? UInt64,
               let vramTotalVal = statistics["vramTotalBytes"] as? UInt64 {
                vramUsed = vramTotalVal - vramFree
                vramTotal = vramTotalVal
            }
            
            // Only use first GPU found
            break
        }
        
        return (gpuUsage, vramUsed, vramTotal)
    }
}