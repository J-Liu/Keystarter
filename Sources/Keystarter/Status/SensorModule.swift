// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit

/// Sensor monitoring module.
final class SensorModule: NSObject, StatusModule {
    
    var identifier: String { "sensor" }
    var displayName: String { L("status.sensor.displayName") }
    
    private(set) var summaryText: String = "CPU --°C"
    
    var icon: NSImage? {
        NSImage(systemSymbolName: "thermometer", accessibilityDescription: "Temperature")
    }
    
    private var cpuTemp: Double = 0
    
    func refreshSummary() {
        cpuTemp = getCPUTemperature()
        if cpuTemp > 0 {
            summaryText = String(format: "CPU %.0f°C", cpuTemp)
        } else {
            summaryText = "CPU --°C"
        }
    }
    
    func makeDetailView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 90, width: 200, height: 20)
        container.addSubview(headerView)
        
        // CPU Temperature
        let tempLabel = NSTextField(labelWithString: String(format: "CPU: %.1f°C", cpuTemp))
        tempLabel.font = .systemFont(ofSize: 13)
        tempLabel.frame = NSRect(x: 16, y: 60, width: 250, height: 20)
        container.addSubview(tempLabel)
        
        // Note
        let noteLabel = NSTextField(labelWithString: L("status.sensor.note"))
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.frame = NSRect(x: 16, y: 30, width: 250, height: 20)
        container.addSubview(noteLabel)
        
        return container
    }
    
    // MARK: - Sensor Data
    
    private func getCPUTemperature() -> Double {
        // Try to find AppleSMC service
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS, iterator != 0 else {
            return 0
        }
        
        defer {
            IOObjectRelease(iterator)
        }
        
        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            return 0
        }
        
        defer {
            IOObjectRelease(service)
        }
        
        // Try to read temperature via IOKit properties
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else {
            return 0
        }
        
        // Look for temperature in properties
        // On Apple Silicon, this might be under different keys
        if let temp = props["Temperature"] as? Double {
            return temp
        }
        
        // Alternative: try to use sysctl to get temperature info
        // This is a fallback that may not work on all systems
        return 0
    }
}