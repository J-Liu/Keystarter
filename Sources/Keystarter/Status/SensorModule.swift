// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit
import SensorReader

/// Sensor monitoring module for Apple Silicon temperature and power.
final class SensorModule: NSObject, StatusModule {
    
    var identifier: String { "sensor" }
    var displayName: String { L("status.sensor.displayName") }
    var shortName: String { "" }
    
    private(set) var summaryText: String = "--W"
    private(set) var summaryValue: String = "--W"
    
    var refreshInterval: TimeInterval { 2.0 }
    
    // Temperature data
    private var cpuPcoreTemp: Double = 0
    private var cpuEcoreTemp: Double = 0
    private var gpuTemp: Double = 0
    private var dramTemp: Double = 0
    private var aneTemp: Double = 0
    private var pciTemp: Double = 0
    private var storageTemp: Double = 0
    private var batteryTemp: Double = 0
    
    // Power data
    private var totalPower: Double = 0
    private let powerReader = SensorReaderSwift()
    
    // Fan data from SMC
    private var fanLeft: Int = 0
    private var fanRight: Int = 0
    private var fanLeftMax: Int = 6000
    private var fanRightMax: Int = 6000
    
    // SMC connection
    private var smcConnection: io_connect_t = 0
    
    private weak var chartView: NSView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?
    
    override init() {
        super.init()
        powerReader.setupPowerMonitoring()
        openSMCConnection()
    }
    
    deinit {
        closeSMCConnection()
    }
    
    func refreshSummary() {
        // Read power
        let power = powerReader.readPower()
        totalPower = power.cpu + power.gpu + power.dram + power.ane + power.pci
        
        // Read temperatures
        let temps = SensorReaderSwift.readTemperatures()
        cpuPcoreTemp = getAverageTemp(for: temps, keys: ["tdie0", "tdie1", "tdie2", "tdie3"])
        cpuEcoreTemp = getAverageTemp(for: temps, keys: ["tdie4", "tdie5", "tdie6", "tdie7"])
        gpuTemp = getAverageTemp(for: temps, keys: ["TP1g", "TP2g", "TP3g"])
        dramTemp = getAverageTemp(for: temps, keys: ["TP0s", "TP1s", "TP2s"])
        aneTemp = getAverageTemp(for: temps, keys: ["TP0s", "TP1s"])
        pciTemp = getAverageTemp(for: temps, keys: ["tdev"])
        storageTemp = getAverageTemp(for: temps, keys: ["NAND"])
        batteryTemp = getAverageTemp(for: temps, keys: ["gas gauge battery"])
        
        // Read fan speeds
        readFanSpeeds()
        
        if totalPower > 0 {
            summaryText = String(format: "%.0fW", totalPower)
            summaryValue = String(format: "%.0fW", totalPower)
        } else if cpuPcoreTemp > 0 {
            summaryText = String(format: "%.0f°", cpuPcoreTemp)
            summaryValue = String(format: "%.0f°", cpuPcoreTemp)
        } else {
            summaryText = "--W"
            summaryValue = "--W"
        }
    }
    
    private func getAverageTemp(for temps: [String: Double], keys: [String]) -> Double {
        var values: [Double] = []
        for (name, temp) in temps {
            for key in keys {
                if name.localizedCaseInsensitiveContains(key) && temp > 20 && temp < 120 {
                    values.append(temp)
                    break
                }
            }
        }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    
    func makeDetailView() -> NSView {
        let toolbarHeight = PopoverToolbar.height
        let headerHeight: CGFloat = 24
        let fanChartHeight: CGFloat = 120
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 10
        let totalHeight = toolbarHeight + headerHeight + fanChartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 400
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))
        
        // Toolbar
        let toolbar = PopoverToolbar.create(title: displayName, width: viewWidth)
        toolbar.frame = NSRect(x: 0, y: totalHeight - toolbarHeight, width: viewWidth, height: toolbarHeight)
        container.addSubview(toolbar)
        
        // Header
        let headerView = NSTextField(labelWithString: "Sensors")
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - toolbarHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)
        
        // Fan chart (two circles)
        let fanChartY = totalHeight - toolbarHeight - headerHeight - fanChartHeight
        let fanChart = createFanChart(frame: NSRect(x: 12, y: fanChartY, width: viewWidth - 24, height: fanChartHeight))
        chartView = fanChart
        container.addSubview(fanChart)
        
        // Divider
        let divider1Y = fanChartY - dividerHeight + 4
        let divider1 = NSBox(frame: NSRect(x: 12, y: divider1Y, width: viewWidth - 24, height: 1))
        divider1.boxType = .separator
        container.addSubview(divider1)
        
        // Temperature table
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: divider1Y))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: viewWidth - 16, height: CGFloat(rowCount) * rowHeight * 2))
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 150
        nameColumn.headerCell.title = "Component"
        table.addTableColumn(nameColumn)
        
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.width = 80
        valueColumn.headerCell.title = "Temperature"
        table.addTableColumn(valueColumn)
        
        table.dataSource = self
        table.delegate = self
        
        scrollView.documentView = table
        tableView = table
        container.addSubview(scrollView)
        
        // Refresh immediately on open, then start timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshDetail()
            self?.startDetailTimer()
        }
        
        return container
    }
    
    private func startDetailTimer() {
        detailTimer?.invalidate()
        detailTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDetail()
        }
    }
    
    private func refreshDetail() {
        // Read power
        let power = powerReader.readPower()
        totalPower = power.cpu + power.gpu + power.dram + power.ane + power.pci
        
        // Read temperatures
        let temps = SensorReaderSwift.readTemperatures()
        cpuPcoreTemp = getAverageTemp(for: temps, keys: ["tdie0", "tdie1", "tdie2", "tdie3"])
        cpuEcoreTemp = getAverageTemp(for: temps, keys: ["tdie4", "tdie5", "tdie6", "tdie7"])
        gpuTemp = getAverageTemp(for: temps, keys: ["TP1g", "TP2g", "TP3g"])
        dramTemp = getAverageTemp(for: temps, keys: ["TP0s", "TP1s", "TP2s"])
        aneTemp = getAverageTemp(for: temps, keys: ["TP0s", "TP1s"])
        pciTemp = getAverageTemp(for: temps, keys: ["tdev"])
        storageTemp = getAverageTemp(for: temps, keys: ["NAND"])
        batteryTemp = getAverageTemp(for: temps, keys: ["gas gauge battery"])
        
        // Read fan speeds
        readFanSpeeds()
        
        // Update summary
        if totalPower > 0 {
            summaryText = String(format: "%.0fW", totalPower)
            summaryValue = String(format: "%.0fW", totalPower)
        } else if cpuPcoreTemp > 0 {
            summaryText = String(format: "%.0f°", cpuPcoreTemp)
            summaryValue = String(format: "%.0f°", cpuPcoreTemp)
        }
        
        updateFanChart()
        tableView?.reloadData()
        
        NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "sensor"])
    }
    
    private func updateFanChart() {
        guard let chart = chartView else { return }
        chart.subviews.forEach { $0.removeFromSuperview() }
        
        let chartWidth = chart.bounds.width
        let chartHeight = chart.bounds.height
        
        let radius: CGFloat = 35
        let centerY = chartHeight / 2
        
        // Left fan (purple-ish)
        let leftX = chartWidth / 2 - radius - 40
        let leftPercent = fanLeftMax > 0 ? Double(fanLeft) / Double(fanLeftMax) * 100 : 0
        let leftColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.8, alpha: 0.3)
        createFanCircle(in: chart, center: NSPoint(x: leftX, y: centerY), radius: radius,
                       percent: leftPercent, speed: fanLeft, color: leftColor, label: "L")
        
        // Right fan (blue-ish)
        let rightX = chartWidth / 2 + radius + 40
        let rightPercent = fanRightMax > 0 ? Double(fanRight) / Double(fanRightMax) * 100 : 0
        let rightColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 0.9, alpha: 0.3)
        createFanCircle(in: chart, center: NSPoint(x: rightX, y: centerY), radius: radius,
                       percent: rightPercent, speed: fanRight, color: rightColor, label: "R")
    }
    
    private func createFanCircle(in parent: NSView, center: NSPoint, radius: CGFloat,
                                 percent: Double, speed: Int, color: NSColor, label: String) {
        // Light colored circle
        let circle = NSView(frame: NSRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        circle.wantsLayer = true
        circle.layer?.backgroundColor = color.cgColor
        circle.layer?.cornerRadius = radius
        parent.addSubview(circle)
        
        // Center percentage label (white)
        let pctLabel = NSTextField(labelWithString: String(format: "%.0f%%", percent))
        pctLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        pctLabel.textColor = NSColor.white
        pctLabel.alignment = .center
        pctLabel.frame = NSRect(x: center.x - 30, y: center.y - 8, width: 60, height: 16)
        parent.addSubview(pctLabel)
        
        // Label below (L or R)
        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: center.x - 20, y: center.y - radius - 20, width: 40, height: 14)
        parent.addSubview(nameLabel)
        
        // RPM label
        let rpmLabel = NSTextField(labelWithString: "\(speed) RPM")
        rpmLabel.font = .systemFont(ofSize: 10)
        rpmLabel.textColor = .secondaryLabelColor
        rpmLabel.alignment = .center
        rpmLabel.frame = NSRect(x: center.x - 35, y: center.y + radius + 6, width: 70, height: 12)
        parent.addSubview(rpmLabel)
    }
    
    private func createFanChart(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        view.layer?.cornerRadius = 4
        return view
    }
    
    // MARK: - SMC Connection
    
    private func openSMCConnection() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        
        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard service != 0 else { return }
        
        _ = IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
        IOObjectRelease(service)
    }
    
    private func closeSMCConnection() {
        if smcConnection != 0 {
            IOServiceClose(smcConnection)
            smcConnection = 0
        }
    }
    
    // MARK: - Fan Speed Reading (SMC)
    
    private func readFanSpeeds() {
        fanLeft = 0
        fanRight = 0
        guard smcConnection != 0 else { return }
        
        guard let fanCount = readSMCValue(key: "FNum") else { return }
        let count = Int(fanCount)
        
        if count >= 1 {
            if let speed = readSMCValue(key: "F0Ac") {
                fanLeft = Int(speed)
            }
            if let maxSpeed = readSMCValue(key: "F0Mx") {
                fanLeftMax = Int(maxSpeed)
            }
        }
        
        if count >= 2 {
            if let speed = readSMCValue(key: "F1Ac") {
                fanRight = Int(speed)
            }
            if let maxSpeed = readSMCValue(key: "F1Mx") {
                fanRightMax = Int(maxSpeed)
            }
        }
    }
    
    private func readSMCValue(key: String) -> Double? {
        guard smcConnection != 0 else { return nil }
        
        var input = SMCKeyData()
        var output = SMCKeyData()
        
        let keyBytes = key.utf8
        input.key = UInt32(keyBytes[keyBytes.startIndex]) << 24 |
                    UInt32(keyBytes[keyBytes.index(keyBytes.startIndex, offsetBy: 1)]) << 16 |
                    UInt32(keyBytes[keyBytes.index(keyBytes.startIndex, offsetBy: 2)]) << 8 |
                    UInt32(keyBytes[keyBytes.index(keyBytes.startIndex, offsetBy: 3)])
        input.data8 = UInt8(kSMCReadKeyInfo)
        
        let inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size
        
        var kr = IOConnectCallStructMethod(smcConnection, UInt32(kSMCKernelIndex), &input, inputSize, &output, &outputSize)
        guard kr == KERN_SUCCESS else { return nil }
        
        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType
        
        input.keyInfo.dataSize = dataSize
        input.data8 = UInt8(kSMCReadBytes)
        
        kr = IOConnectCallStructMethod(smcConnection, UInt32(kSMCKernelIndex), &input, inputSize, &output, &outputSize)
        guard kr == KERN_SUCCESS else { return nil }
        
        let typeStr = String(bytes: [
            UInt8((dataType >> 24) & 0xFF),
            UInt8((dataType >> 16) & 0xFF),
            UInt8((dataType >> 8) & 0xFF),
            UInt8(dataType & 0xFF)
        ], encoding: .ascii) ?? ""
        
        switch typeStr {
        case "ui8 ", "UI8 ":
            return Double(output.bytes.0)
        case "ui16", "UI16":
            return Double(UInt16(output.bytes.0) << 8 | UInt16(output.bytes.1))
        case "ui32", "UI32":
            return Double(UInt32(output.bytes.0) << 24 | UInt32(output.bytes.1) << 16 | UInt32(output.bytes.2) << 8 | UInt32(output.bytes.3))
        case "sp78", "SP78":
            let intValue = Double(Int16(output.bytes.0) << 8 | Int16(output.bytes.1))
            return intValue / 256.0
        case "sp96", "SP96":
            let intValue = Double(Int16(output.bytes.0) << 8 | Int16(output.bytes.1))
            return intValue / 64.0
        case "fpe2", "FPE2":
            return Double(Int(output.bytes.0) << 6 | Int(output.bytes.1) >> 2)
        case "flt ", "FLT ":
            var bytes = [output.bytes.0, output.bytes.1, output.bytes.2, output.bytes.3]
            return bytes.withUnsafeMutableBytes { Double($0.load(as: Float.self)) }
        default:
            return Double(Int(output.bytes.0) << 6 | Int(output.bytes.1) >> 2)
        }
    }
    
    // MARK: - Temperature data for table
    
    private var tempComponents: [(name: String, value: Double)] = []
    
    private func updateTempComponents() {
        tempComponents = [
            ("CPU P-core", cpuPcoreTemp),
            ("CPU E-core", cpuEcoreTemp),
            ("GPU", gpuTemp),
            ("DRAM", dramTemp),
            ("ANE", aneTemp),
            ("PCI", pciTemp),
            ("Storage", storageTemp),
            ("Battery", batteryTemp)
        ]
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension SensorModule: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        updateTempComponents()
        return tempComponents.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < tempComponents.count else { return nil }
        let component = tempComponents[row]
        
        let cell = NSTableCellView()
        let colId = tableColumn?.identifier.rawValue ?? ""
        
        switch colId {
        case "name":
            let label = NSTextField(labelWithString: component.name)
            label.font = .systemFont(ofSize: 11)
            label.frame = NSRect(x: 12, y: 2, width: 130, height: 16)
            cell.addSubview(label)
            
        case "value":
            let tempText = component.value > 0 ? String(format: "%.0f°", component.value) : "--"
            let label = NSTextField(labelWithString: tempText)
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 72, height: 16)
            cell.addSubview(label)
            
        default:
            break
        }
        
        return cell
    }
}

// MARK: - SMC Constants and Structures

private let kSMCKernelIndex: UInt8 = 2
private let kSMCReadKeyInfo: UInt8 = 9
private let kSMCReadBytes: UInt8 = 5

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var keyInfo: KeyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8_2: UInt8 = 0
    var val: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    
    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    init() {}
}
