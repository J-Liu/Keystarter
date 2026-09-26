// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit
import SensorReader

/// Sensor monitoring module for Apple Silicon temperature and power.
final class SensorModule: NSObject, StatusModule {
    
    var identifier: String { "sensor" }
    var displayName: String { L("status.sensor.displayName") }
    var shortName: String { "PWR" }
    
    private(set) var summaryText: String = "--W"
    private(set) var summaryValue: String = "--W"
    
    var refreshInterval: TimeInterval { 2.0 }
    
    private var temperatures: [String: Double] = [:]
    private let sensorReader = SensorReaderSwift()
    private var powerReader: SensorReaderSwift?
    private var powerReadings: PowerReadings?
    private var totalPower: Double = 0
    
    // Fan data
    private var fans: [(speed: Int, maxSpeed: Int)] = []
    
    override init() {
        super.init()
        powerReader = SensorReaderSwift()
        powerReader?.setupPowerMonitoring()
    }
    
    func refreshSummary() {
        temperatures = SensorReaderSwift.readTemperatures()
        
        // Read power
        powerReadings = powerReader?.readPower()
        
        // Calculate total power
        if let power = powerReadings {
            totalPower = power.cpu + power.gpu + power.dram + power.ane + power.pci
        }
        
        // Read fan speeds
        fans = readFanSpeeds()
        
        if totalPower > 0 {
            summaryText = String(format: "%.0fW", totalPower)
            summaryValue = String(format: "%.0fW", totalPower)
        } else {
            summaryText = "--W"
            summaryValue = "--W"
        }
    }
    
    func makeDetailView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 420))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 390, width: 200, height: 20)
        container.addSubview(headerView)
        
        var yOffset: CGFloat = 360
        
        // Fan section
        if !fans.isEmpty {
            let fanHeader = NSTextField(labelWithString: "Fans")
            fanHeader.font = .systemFont(ofSize: 12, weight: .medium)
            fanHeader.frame = NSRect(x: 16, y: yOffset, width: 100, height: 16)
            container.addSubview(fanHeader)
            yOffset -= 100
            
            // Fan circles
            let fanView = createFanView(frame: NSRect(x: 16, y: yOffset, width: 248, height: 90))
            container.addSubview(fanView)
            yOffset -= 16
            
            // Divider
            let divider = NSView(frame: NSRect(x: 16, y: yOffset, width: 248, height: 1))
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
            container.addSubview(divider)
            yOffset -= 16
        }
        
        // Temperature section
        let tempHeader = NSTextField(labelWithString: "Temperature")
        tempHeader.font = .systemFont(ofSize: 12, weight: .medium)
        tempHeader.frame = NSRect(x: 16, y: yOffset, width: 100, height: 16)
        container.addSubview(tempHeader)
        yOffset -= 20
        
        // Temperature list
        let tempItems = getTemperatureItems()
        for item in tempItems {
            let row = createTempRow(name: item.name, value: item.value, frame: NSRect(x: 16, y: yOffset, width: 248, height: 18))
            container.addSubview(row)
            yOffset -= 20
        }
        
        return container
    }
    
    // MARK: - Fan Speed Reading
    
    private func readFanSpeeds() -> [(speed: Int, maxSpeed: Int)] {
        var result: [(Int, Int)] = []
        
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return result
        }
        
        defer { IOObjectRelease(iterator) }
        
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return result }
        
        defer { IOObjectRelease(service) }
        
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 1, &connect) == KERN_SUCCESS else {
            return result
        }
        
        defer { IOServiceClose(connect) }
        
        // Try to read fan speeds (F0Ac, F1Ac, etc.)
        for i in 0..<2 {
            let key = "F\(i)Ac"
            if let speed = readSMCKey(connect: connect, key: key),
               let maxSpeed = readSMCKey(connect: connect, key: "F\(i)Mx") {
                result.append((Int(speed), Int(maxSpeed)))
            }
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
        
        // Fan speed is stored as fpe2 (16.8 fixed point)
        let value = Double(output.val) / 256.0
        return value > 0 ? value : nil
    }
    
    // MARK: - Fan UI
    
    private func createFanView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        
        let fanCount = min(fans.count, 2)
        let circleDiameter: CGFloat = 70
        let spacing: CGFloat = (frame.width - CGFloat(fanCount) * circleDiameter) / CGFloat(fanCount + 1)
        
        for i in 0..<fanCount {
            let fan = fans[i]
            let x = spacing + CGFloat(i) * (circleDiameter + spacing)
            
            let circleView = createFanCircle(
                frame: NSRect(x: x, y: 10, width: circleDiameter, height: circleDiameter),
                speed: fan.speed,
                maxSpeed: fan.maxSpeed,
                index: i
            )
            view.addSubview(circleView)
        }
        
        return view
    }
    
    private func createFanCircle(frame: NSRect, speed: Int, maxSpeed: Int, index: Int) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        
        let percentage = maxSpeed > 0 ? min(Double(speed) / Double(maxSpeed), 1.0) : 0
        
        // Background circle
        let bgLayer = CAShapeLayer()
        let bgPath = CGMutablePath()
        bgPath.addEllipse(in: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        bgLayer.path = bgPath
        bgLayer.fillColor = NSColor.controlBackgroundColor.cgColor
        bgLayer.strokeColor = NSColor.separatorColor.cgColor
        bgLayer.lineWidth = 2
        view.layer?.addSublayer(bgLayer)
        
        // Progress arc
        let progressLayer = CAShapeLayer()
        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let radius = frame.width / 2 - 4
        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + CGFloat(percentage) * 2 * CGFloat.pi
        
        let progressPath = CGMutablePath()
        progressPath.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        progressLayer.path = progressPath
        progressLayer.fillColor = nil
        progressLayer.strokeColor = NSColor.systemBlue.cgColor
        progressLayer.lineWidth = 4
        progressLayer.lineCap = .round
        view.layer?.addSublayer(progressLayer)
        
        // Percentage label
        let percentLabel = NSTextField(labelWithString: String(format: "%.0f%%", percentage * 100))
        percentLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        percentLabel.alignment = .center
        percentLabel.frame = NSRect(x: 0, y: frame.height / 2 - 5, width: frame.width, height: 22)
        view.addSubview(percentLabel)
        
        // Speed label
        let speedLabel = NSTextField(labelWithString: "\(speed) RPM")
        speedLabel.font = .systemFont(ofSize: 9)
        speedLabel.textColor = .secondaryLabelColor
        speedLabel.alignment = .center
        speedLabel.frame = NSRect(x: 0, y: frame.height / 2 - 22, width: frame.width, height: 14)
        view.addSubview(speedLabel)
        
        // Fan label
        let fanLabel = NSTextField(labelWithString: "Fan \(index + 1)")
        fanLabel.font = .systemFont(ofSize: 10)
        fanLabel.textColor = .tertiaryLabelColor
        fanLabel.alignment = .center
        fanLabel.frame = NSRect(x: 0, y: -14, width: frame.width, height: 12)
        view.addSubview(fanLabel)
        
        return view
    }
    
    // MARK: - Temperature Items
    
    private func getTemperatureItems() -> [(name: String, value: Double)] {
        var items: [(String, Double)] = []
        
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