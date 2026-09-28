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
    private var smcPower: Double = 0  // SMC PSTR power
    
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
        // Read power from SMC PSTR (System Total) - most reliable
        readSMCPower()
        totalPower = smcPower
        
        // Fallback to IOReport if SMC fails
        if totalPower <= 0 {
            let power = powerReader.readPower()
            totalPower = power.cpu + power.gpu + power.dram + power.ane + power.pci
        }
        
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
        let rowCount = 30  // Increased for more sensors
        let tableHeight: CGFloat = 300  // Fixed height for scrollable area
        let totalHeight = toolbarHeight + headerHeight + fanChartHeight + dividerHeight + tableHeight + 16
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
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: tableHeight))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: viewWidth - 16, height: CGFloat(rowCount) * rowHeight))
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 200
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
        // Read power from IOReport
        let power = powerReader.readPower()
        let ioReportPower = power.cpu + power.gpu + power.dram + power.ane + power.pci
        
        // Read power from SMC (PSTR - System Total)
        readSMCPower()
        
        // Use SMC power if available, otherwise use IOReport power
        totalPower = smcPower > 0 ? smcPower : ioReportPower
        
        // Read all sensors from HID and SMC
        readAllSensors()
        
        // Read fan speeds
        readFanSpeeds()
        
        // Update summary
        if totalPower > 0 {
            summaryText = String(format: "%.0fW", totalPower)
            summaryValue = String(format: "%.0fW", totalPower)
        } else if let first = allSensors.first, first.value > 0 {
            summaryText = String(format: "%.0f°", first.value)
            summaryValue = String(format: "%.0f°", first.value)
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
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return }
        
        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard service != 0 else { return }
        
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
        IOObjectRelease(service)
        
        if openResult != KERN_SUCCESS {
            smcConnection = 0
        }
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
        
        // Re-open connection if closed
        if smcConnection == 0 {
            openSMCConnection()
        }
        guard smcConnection != 0 else { return }
        
        // Try to read fan count - if this fails, connection is bad
        guard let fanCount = readSMCValue(key: "FNum") else {
            closeSMCConnection()
            return
        }
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
    
    private func readSMCPower() {
        smcPower = 0
        
        if smcConnection == 0 {
            openSMCConnection()
        }
        guard smcConnection != 0 else { return }
        
        if let power = readSMCValue(key: "PSTR") {
            smcPower = power
        }
    }
    
    private func readSMCValue(key: String) -> Double? {
        guard smcConnection != 0 else { return nil }
        guard key.count == 4 else { return nil }
        
        let input = SMCKeyDataBuffer()
        let output = SMCKeyDataBuffer()
        
        let keyBytes = Array(key.utf8)
        input.key = UInt32(keyBytes[0]) << 24 |
                    UInt32(keyBytes[1]) << 16 |
                    UInt32(keyBytes[2]) << 8 |
                    UInt32(keyBytes[3])
        input.data8 = UInt8(kSMCReadKeyInfo)
        
        var outputSize = SMCKeyDataBuffer.size
        var kr = input.withUnsafeMutableBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                IOConnectCallStructMethod(
                    smcConnection,
                    UInt32(kSMCKernelIndex),
                    inputPtr.baseAddress,
                    SMCKeyDataBuffer.size,
                    outputPtr.baseAddress,
                    &outputSize
                )
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        
        let dataSize = output.dataSize
        let dataType = output.dataType
        
        input.dataSize = dataSize
        input.data8 = UInt8(kSMCReadBytes)
        
        outputSize = SMCKeyDataBuffer.size
        kr = input.withUnsafeMutableBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                IOConnectCallStructMethod(
                    smcConnection,
                    UInt32(kSMCKernelIndex),
                    inputPtr.baseAddress,
                    SMCKeyDataBuffer.size,
                    outputPtr.baseAddress,
                    &outputSize
                )
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        
        let typeStr = String(bytes: [
            UInt8((dataType >> 24) & 0xFF),
            UInt8((dataType >> 16) & 0xFF),
            UInt8((dataType >> 8) & 0xFF),
            UInt8(dataType & 0xFF)
        ], encoding: .ascii) ?? ""
        
        switch typeStr {
        case "ui8 ", "UI8 ":
            return Double(output.getByte(0))
        case "ui16", "UI16":
            return Double(UInt16(output.getByte(0)) << 8 | UInt16(output.getByte(1)))
        case "ui32", "UI32":
            return Double(UInt32(output.getByte(0)) << 24 | UInt32(output.getByte(1)) << 16 | UInt32(output.getByte(2)) << 8 | UInt32(output.getByte(3)))
        case "sp78", "SP78":
            let intValue = Double(Int16(output.getByte(0)) << 8 | Int16(output.getByte(1)))
            return intValue / 256.0
        case "sp96", "SP96":
            let intValue = Double(Int16(output.getByte(0)) << 8 | Int16(output.getByte(1)))
            return intValue / 64.0
        case "fpe2", "FPE2":
            return Double(Int(output.getByte(0)) << 6 | Int(output.getByte(1)) >> 2)
        case "flt ", "FLT ":
            let floatValue = output.withUnsafeBytes { $0.load(fromByteOffset: 48, as: Float.self) }
            return Double(floatValue)
        default:
            return Double(Int(output.getByte(0)) << 6 | Int(output.getByte(1)) >> 2)
        }
    }
    
    // MARK: - Temperature data for table

    private var allSensors: [(key: String, name: String, value: Double)] = []
    private var tempComponents: [(name: String, value: Double)] = []
    
    private func readAllSMCKeys() -> [String] {
        guard smcConnection != 0 else { return [] }
        
        // First, get the total number of keys
        guard let keyCount = readSMCValue(key: "#KEY") else {
            return []
        }
        let count = Int(keyCount)
        
        var keys: [String] = []
        
        for i in 0..<count {
            let input = SMCKeyDataBuffer()
            let output = SMCKeyDataBuffer()
            
            input.data8 = UInt8(kSMCGetKeyFromIndex)
            input.data32 = UInt32(i)
            
            var outputSize = SMCKeyDataBuffer.size
            let kr = input.withUnsafeMutableBytes { inputPtr in
                output.withUnsafeMutableBytes { outputPtr in
                    IOConnectCallStructMethod(
                        smcConnection,
                        UInt32(kSMCKernelIndex),
                        inputPtr.baseAddress,
                        SMCKeyDataBuffer.size,
                        outputPtr.baseAddress,
                        &outputSize
                    )
                }
            }
            guard kr == KERN_SUCCESS else { continue }
            
            // Extract key from output.key
            let keyVal = output.key
            let key = String(bytes: [
                UInt8((keyVal >> 24) & 0xFF),
                UInt8((keyVal >> 16) & 0xFF),
                UInt8((keyVal >> 8) & 0xFF),
                UInt8(keyVal & 0xFF)
            ], encoding: .ascii) ?? ""
            
            if !key.isEmpty {
                keys.append(key)
            }
        }
        
        return keys
    }
    
    private func readAllSensors() {
        allSensors = []
        
        // Read from HID first (most reliable for Apple Silicon CPU/GPU temps)
        let hidTemps = SensorReaderSwift.readTemperatures()
        for (key, value) in hidTemps {
            let name = mapHIDSensorName(key)
            // Only include sensors with valid names and reasonable values
            if !name.isEmpty && value > 0 && value < 120 {
                allSensors.append((key: key, name: name, value: value))
            }
        }
        
        // Read from SMC for additional sensors
        if smcConnection != 0 {
            let allKeys = readAllSMCKeys()
            
            // Filter to temperature keys only (start with T)
            let tempKeys = allKeys.filter { $0.hasPrefix("T") }
            
            // Sensor name mapping based on discovered keys on Apple Silicon
            let sensorMap: [String: String] = [
                // Apple Silicon specific airflow/ambient sensors
                "TaLP": "sensor.airflow.left",
                "TaRF": "sensor.airflow.right",
                // Airport/WiFi
                "TW0P": "sensor.airport",
                // Storage/NAND
                "TH0x": "sensor.storage",
                "TH0a": "sensor.storage",
                "TH0b": "sensor.storage",
                "TH1a": "sensor.storage",
                "TH1b": "sensor.storage",
                // Battery
                "TB0T": "sensor.battery",
                "TB1T": "sensor.battery",
                "TB2T": "sensor.battery",
                // Memory
                "Tm0C": "sensor.memory",
                "Tm0D": "sensor.memory",
                "Tm0E": "sensor.memory",
            ]
            
            for key in tempKeys {
                // Check if this key matches a known sensor
                var localizedName: String? = nil
                if let nameKey = sensorMap[key] {
                    localizedName = L(nameKey)
                }
                
                // Pattern matching for common prefixes
                if key.hasPrefix("TH") && localizedName == nil {
                    localizedName = L("sensor.storage")
                }
                if key.hasPrefix("Tm") && localizedName == nil {
                    localizedName = L("sensor.memory")
                }
                
                // Only read keys we have names for
                if localizedName == nil { continue }
                
                if let value = readSMCValue(key: key) {
                    // Filter out invalid values (0, >120, or clearly broken sensors)
                    if value > 10 && value < 120 {
                        if !allSensors.contains(where: { $0.key == key }) {
                            allSensors.append((key: key, name: localizedName!, value: value))
                        }
                    }
                }
            }
        }
        
        // Sort by name, CPU first, then GPU, Memory, etc.
        allSensors.sort { a, b in
            let order = [
                L("sensor.cpu.pcore"),
                L("sensor.cpu.ecore"),
                L("sensor.cpu.core"),
                L("sensor.gpu"),
                L("sensor.memory"),
                L("sensor.battery"),
                L("sensor.storage"),
                L("sensor.airport"),
                L("sensor.display"),
                L("sensor.thunderbolt"),
                L("sensor.mainboard"),
                L("sensor.airflow")
            ]
            for prefix in order {
                if a.name.hasPrefix(prefix) && !b.name.hasPrefix(prefix) { return true }
                if !a.name.hasPrefix(prefix) && b.name.hasPrefix(prefix) { return false }
            }
            return a.name < b.name
        }
    }
    
    private func mapHIDSensorName(_ key: String) -> String {
        // Remove "PMU " prefix if present
        let cleanKey = key.hasPrefix("PMU ") ? String(key.dropFirst(4)) : key
        
        // CPU核心温度 (tdie = die temperature)
        // M3/M4 MacBook Pro: 通常是 8个性能核 + 2个能效核
        // tdie0-7 = 性能核, tdie8-9 = 能效核 (具体取决于芯片型号)
        if cleanKey.hasPrefix("tdie") {
            let numStr = cleanKey.replacingOccurrences(of: "tdie", with: "")
            if let num = Int(numStr) {
                // 假设前8个是性能核，后2个是能效核（M3 Pro典型配置）
                if num < 8 {
                    return "\(L("sensor.cpu.pcore")) \(num + 1)"
                } else if num < 10 {
                    return "\(L("sensor.cpu.ecore")) \(num - 7)"
                } else {
                    return "\(L("sensor.cpu.core")) \(num + 1)"
                }
            }
            return L("sensor.cpu.core")
        }
        
        // GPU温度 (TP*g = GPU temperature point)
        if cleanKey.hasPrefix("TP") && cleanKey.hasSuffix("g") {
            return L("sensor.gpu")
        }
        
        // 内存温度 (TP*s = DRAM temperature)
        if cleanKey.hasPrefix("TP") && cleanKey.hasSuffix("s") {
            return L("sensor.memory")
        }
        
        // 设备温度 (tdev = device temperature)
        // 这些是各种外设的温度，但无法确定具体是哪个设备
        if cleanKey.hasPrefix("tdev") {
            return "" // 跳过，无实际意义
        }
        
        // 其他已知传感器
        if cleanKey == "tcal" { return "" }  // 校准温度，跳过
        if cleanKey.contains("NAND") { return L("sensor.storage") }
        if cleanKey.contains("gas gauge") { return L("sensor.battery") }
        
        // 未知传感器不显示
        return ""
    }
    
    private func updateTempComponents() {
        // If we have all sensors, use them
        if !allSensors.isEmpty {
            tempComponents = allSensors.map { ($0.name, $0.value) }
            return
        }
        
        // Fallback to hardcoded list
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
private let kSMCGetKeyFromIndex: UInt8 = 8

// Sensor name mapping based on Stats SensorsList
private let smcSensorNames: [String: String] = [
    // M3 Apple Silicon temperature sensors
    "Te05": "CPU E-core 1", "Te0L": "CPU E-core 2", "Te0P": "CPU E-core 3", "Te0S": "CPU E-core 4",
    "Tf04": "CPU P-core 1", "Tf09": "CPU P-core 2", "Tf0A": "CPU P-core 3", "Tf0B": "CPU P-core 4",
    "Tf0D": "CPU P-core 5", "Tf0E": "CPU P-core 6", "Tf44": "CPU P-core 7", "Tf49": "CPU P-core 8",
    "Tf4A": "CPU P-core 9", "Tf4B": "CPU P-core 10", "Tf4D": "CPU P-core 11", "Tf4E": "CPU P-core 12",
    "Tf14": "GPU 1", "Tf18": "GPU 2", "Tf19": "GPU 3", "Tf1A": "GPU 4",
    "Tf24": "GPU 5", "Tf28": "GPU 6", "Tf29": "GPU 7", "Tf2A": "GPU 8",
    
    // M2 temperature sensors
    "Tp1h": "CPU E-core 1", "Tp1t": "CPU E-core 2", "Tp1p": "CPU E-core 3", "Tp1l": "CPU E-core 4",
    "Tp01": "CPU P-core 1", "Tp05": "CPU P-core 2", "Tp09": "CPU P-core 3", "Tp0D": "CPU P-core 4",
    "Tp0X": "CPU P-core 5", "Tp0b": "CPU P-core 6", "Tp0f": "CPU P-core 7", "Tp0j": "CPU P-core 8",
    "Tg0f": "GPU 1", "Tg0j": "GPU 2",
    
    // M4 temperature sensors (unique keys)
    "Te0H": "CPU E-core 4",
    "Tp0V": "CPU P-core 5", "Tp0Y": "CPU P-core 6", "Tp0e": "CPU P-core 8",
    "Tg0G": "GPU 1", "Tg0H": "GPU 2", "Tg1U": "GPU 1 Pro", "Tg1k": "GPU 2 Pro",
    "Tg0K": "GPU 3", "Tg0d": "GPU 5", "Tg0k": "GPU 8",
    "Tm0p": "Memory 1", "Tm1p": "Memory 2", "Tm2p": "Memory 3",
    
    // M1 temperature sensors (unique keys not already in M2)
    "Tp0T": "CPU E-core 2",
    "Tp0H": "CPU P-core 4", "Tp0L": "CPU P-core 5", "Tp0P": "CPU P-core 6",
    "Tg05": "GPU 1", "Tg0D": "GPU 2", "Tg0L": "GPU 3", "Tg0T": "GPU 4",
    "Tm02": "Memory 1", "Tm06": "Memory 2", "Tm08": "Memory 3", "Tm09": "Memory 4",
    
    // Common sensors
    "TaLP": "Airflow Left", "TaRF": "Airflow Right",
    "TH0x": "NAND", "TB1T": "Battery", "TB2T": "Battery 2",
    
    // Intel sensors
    "TC0D": "CPU Diode", "TC0P": "CPU Proximity", "TC0H": "CPU Heatsink",
    "TG0D": "GPU Diode", "TG0P": "GPU Proximity",
    "Tm0P": "Mainboard", "TL0P": "Display"
]

// Use raw memory buffer for SMC calls to avoid struct layout issues
// Total size must be 80 bytes to match kernel expectation
private class SMCKeyDataBuffer {
    static let size = 80
    private var buffer: [UInt8]
    
    init() {
        buffer = [UInt8](repeating: 0, count: SMCKeyDataBuffer.size)
    }
    
    // Key at offset 0 (4 bytes)
    var key: UInt32 {
        get { buffer.withUnsafeBytes { $0.load(as: UInt32.self) } }
        set { withUnsafeMutableBytes { $0.storeBytes(of: newValue, as: UInt32.self) } }
    }
    
    // data8 at offset 40
    var data8: UInt8 {
        get { buffer[40] }
        set { buffer[40] = newValue }
    }
    
    // data32 at offset 44
    var data32: UInt32 {
        get { buffer.withUnsafeBytes { $0.load(fromByteOffset: 44, as: UInt32.self) } }
        set { withUnsafeMutableBytes { $0.storeBytes(of: newValue, toByteOffset: 44, as: UInt32.self) } }
    }
    
    // keyInfo.dataSize at offset 26 (4 bytes)
    var dataSize: UInt32 {
        get { buffer.withUnsafeBytes { $0.load(fromByteOffset: 26, as: UInt32.self) } }
        set { withUnsafeMutableBytes { $0.storeBytes(of: newValue, toByteOffset: 26, as: UInt32.self) } }
    }
    
    // keyInfo.dataType at offset 30 (4 bytes)
    var dataType: UInt32 {
        get { buffer.withUnsafeBytes { $0.load(fromByteOffset: 30, as: UInt32.self) } }
        set { withUnsafeMutableBytes { $0.storeBytes(of: newValue, toByteOffset: 30, as: UInt32.self) } }
    }
    
    // bytes array at offset 48 (32 bytes)
    func getByte(_ index: Int) -> UInt8 {
        buffer[48 + index]
    }
    
    // For IOConnectCallStructMethod
    func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
        try buffer.withUnsafeMutableBytes(body)
    }
    
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        try buffer.withUnsafeBytes(body)
    }
}
