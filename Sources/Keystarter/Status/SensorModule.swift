// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit

/// Sensor monitoring module for Apple Silicon temperature.
final class SensorModule: NSObject, StatusModule {
    
    var identifier: String { "sensor" }
    var displayName: String { L("status.sensor.displayName") }
    var shortName: String { "TMP" }
    
    private(set) var summaryText: String = "--°C"
    private(set) var summaryValue: String = "--°"
    
    var refreshInterval: TimeInterval { 10.0 }
    
    private var cpuTemp: Double = 0
    
    func refreshSummary() {
        cpuTemp = getCPUTemperature()
        if cpuTemp > 0 {
            summaryText = String(format: "%.0f°C", cpuTemp)
            summaryValue = String(format: "%.0f°", cpuTemp)
        } else {
            summaryText = "--°C"
            summaryValue = "--°"
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
    
    // MARK: - Temperature Reading
    
    private func getCPUTemperature() -> Double {
        // Method 1: Try HID sensor (Apple Silicon)
        if let temp = readHIDSensorTemperature() {
            return temp
        }
        
        // Method 2: Try AppleSMC (Intel Mac)
        if let temp = readSMCTemperature() {
            return temp
        }
        
        return 0
    }
    
    private func readHIDSensorTemperature() -> Double? {
        // Apple Silicon uses IOHIDDevice for temperature sensors
        var iterator: io_iterator_t = 0
        
        // Match HID devices with Apple Vendor temperature sensors
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
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
            
            // Get device properties
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }
            
            // Check if this is a temperature sensor
            // PrimaryUsagePage: 0xFF00 (Apple Vendor), PrimaryUsage: varies
            guard let usagePage = props["PrimaryUsagePage"] as? Int,
                  usagePage == 0xFF00 else { // Apple Vendor page
                continue
            }
            
            // Try to read temperature value
            if let inputValues = props["Elements"] as? [[String: Any]] {
                for element in inputValues {
                    if let usagePage = element["UsagePage"] as? Int,
                       usagePage == 0xFF00,
                       let value = element["Value"] as? Double {
                        // Value might be in centidegrees or other units
                        // Typical: temperature * 100
                        return value / 100.0
                    }
                }
            }
        }
        
        return nil
    }
    
    private func readSMCTemperature() -> Double? {
        // Intel Mac SMC temperature reading
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        
        defer {
            IOObjectRelease(iterator)
        }
        
        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            return nil
        }
        
        defer {
            IOObjectRelease(service)
        }
        
        // Open connection to SMC
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 1, &connect) == KERN_SUCCESS else {
            return nil
        }
        
        defer {
            IOServiceClose(connect)
        }
        
        // Read TC0P key (CPU Proximity Temperature)
        let result = readSMCKey(connect: connect, key: "TC0P")
        
        // Fallback: try TC0D (CPU Die Temperature)
        if result == nil {
            return readSMCKey(connect: connect, key: "TC0D")
        }
        
        return result
    }
    
    private func readSMCKey(connect: io_connect_t, key: String) -> Double? {
        let keyBytes = key.utf8.map { UInt8($0) }
        
        var input = SMCKeyData()
        input.key = (UInt32(keyBytes[0]) << 24) | (UInt32(keyBytes[1]) << 16) | (UInt32(keyBytes[2]) << 8) | UInt32(keyBytes[3])
        input.data8 = UInt8(kSMCReadKey)
        
        var output = SMCKeyData()
        let inputSize: Int = MemoryLayout<SMCKeyData>.size
        var outputSize: Int = MemoryLayout<SMCKeyData>.size
        
        let kr = IOConnectCallStructMethod(
            connect,
            kSMCUserClientMethod,
            &input,
            inputSize,
            &output,
            &outputSize
        )
        
        guard kr == KERN_SUCCESS else { return nil }
        
        // Temperature is stored as SP78 (signed 15.8 fixed point)
        let temp = Double(Int16(bitPattern: UInt16(output.val))) / 256.0
        return temp > 0 ? temp : nil
    }
}

// MARK: - SMC Constants and Structures

private let kSMCUserClientMethod: UInt32 = 2
private let kSMCReadKey: UInt8 = 5

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8_2: UInt8 = 0
    var val: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    
    init() {}
}