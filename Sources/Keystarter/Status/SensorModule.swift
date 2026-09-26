// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit
import SensorReader

/// Sensor monitoring module for Apple Silicon temperature and power.
final class SensorModule: NSObject, StatusModule {
    
    var identifier: String { "sensor" }
    var displayName: String { L("status.sensor.displayName") }
    var shortName: String { "TMP" }
    
    private(set) var summaryText: String = "--°C"
    private(set) var summaryValue: String = "--°"
    
    var refreshInterval: TimeInterval { 2.0 }
    
    private var temperatures: [String: Double] = [:]
    private let sensorReader = SensorReaderSwift()
    private var powerReader: SensorReaderSwift?
    private var powerReadings: PowerReadings?
    
    private var cpuTempHistory: [Double] = []
    private let maxHistoryCount = 60
    
    override init() {
        super.init()
        powerReader = SensorReaderSwift()
        powerReader?.setupPowerMonitoring()
    }
    
    func refreshSummary() {
        temperatures = SensorReaderSwift.readTemperatures()
        
        // Find CPU temperature
        var cpuTemp: Double = 0
        for (name, temp) in temperatures {
            if name.lowercased().contains("cpu") || name.lowercased().contains("tdie") {
                cpuTemp = temp
                break
            }
        }
        
        // If no specific CPU temp, use first available
        if cpuTemp == 0, let first = temperatures.values.first {
            cpuTemp = first
        }
        
        // Update history
        if cpuTemp > 0 {
            cpuTempHistory.append(cpuTemp)
            if cpuTempHistory.count > maxHistoryCount {
                cpuTempHistory.removeFirst()
            }
        }
        
        // Read power
        powerReadings = powerReader?.readPower()
        
        if cpuTemp > 0 {
            summaryText = String(format: "%.0f°C", cpuTemp)
            summaryValue = String(format: "%.0f°", cpuTemp)
        } else {
            summaryText = "--°C"
            summaryValue = "--°"
        }
    }
    
    func makeDetailView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 370, width: 200, height: 20)
        container.addSubview(headerView)
        
        // Temperature chart
        let chartView = createChart(frame: NSRect(x: 16, y: 280, width: 248, height: 80))
        container.addSubview(chartView)
        
        // Temperature section
        let tempHeader = NSTextField(labelWithString: "Temperature")
        tempHeader.font = .systemFont(ofSize: 12, weight: .medium)
        tempHeader.frame = NSRect(x: 16, y: 260, width: 100, height: 16)
        container.addSubview(tempHeader)
        
        // Temperature list
        var yOffset: CGFloat = 240
        let tempItems = getTemperatureItems()
        for item in tempItems {
            let row = createTempRow(name: item.name, value: item.value, frame: NSRect(x: 16, y: yOffset, width: 248, height: 18))
            container.addSubview(row)
            yOffset -= 20
        }
        
        // Power section
        yOffset -= 10
        let powerHeader = NSTextField(labelWithString: "Power")
        powerHeader.font = .systemFont(ofSize: 12, weight: .medium)
        powerHeader.frame = NSRect(x: 16, y: yOffset, width: 100, height: 16)
        container.addSubview(powerHeader)
        yOffset -= 20
        
        // Power readings
        if let power = powerReadings {
            let powerItems: [(String, Double)] = [
                ("CPU", power.cpu),
                ("GPU", power.gpu),
                ("Memory", power.dram),
                ("Neural Engine", power.ane),
                ("PCI", power.pci)
            ]
            
            for item in powerItems {
                if item.1 > 0 {
                    let row = createPowerRow(name: item.0, value: item.1, frame: NSRect(x: 16, y: yOffset, width: 248, height: 18))
                    container.addSubview(row)
                    yOffset -= 20
                }
            }
        }
        
        return container
    }
    
    // MARK: - Temperature Items
    
    private func getTemperatureItems() -> [(name: String, value: Double)] {
        var items: [(String, Double)] = []
        
        // Known sensor names mapping
        let nameMapping: [String: String] = [
            "tdie": "CPU Die",
            "cpu": "CPU",
            "gpu": "GPU",
            "dram": "Memory",
            "pmu": "PMU",
            "ane": "Neural Engine",
            "pcie": "PCIe",
            "battery": "Battery"
        ]
        
        for (sensorName, value) in temperatures.sorted(by: { $0.key < $1.key }) {
            let lowerName = sensorName.lowercased()
            
            // Find matching friendly name
            var friendlyName = sensorName
            for (key, friendly) in nameMapping {
                if lowerName.contains(key) {
                    friendlyName = friendly
                    break
                }
            }
            
            if value > 0 {
                items.append((friendlyName, value))
            }
        }
        
        // If no items, add placeholder
        if items.isEmpty {
            items.append(("No sensors", 0))
        }
        
        return items
    }
    
    // MARK: - UI Helpers
    
    private func createTempRow(name: String, value: Double, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)
        
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.frame = NSRect(x: 0, y: 0, width: 120, height: 16)
        row.addSubview(nameLabel)
        
        let valueLabel = NSTextField(labelWithString: String(format: "%.1f°C", value))
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 180, y: 0, width: 68, height: 16)
        row.addSubview(valueLabel)
        
        return row
    }
    
    private func createPowerRow(name: String, value: Double, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)
        
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.frame = NSRect(x: 0, y: 0, width: 120, height: 16)
        row.addSubview(nameLabel)
        
        let valueLabel = NSTextField(labelWithString: String(format: "%.2f W", value))
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 180, y: 0, width: 68, height: 16)
        row.addSubview(valueLabel)
        
        return row
    }
    
    private func createChart(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        view.layer?.cornerRadius = 4
        
        return view
    }
}