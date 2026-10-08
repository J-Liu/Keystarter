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

    // Fan history for chart (last 60 samples = 2 minutes)
    private var fanLeftHistory: [Int] = []
    private var fanRightHistory: [Int] = []
    private let maxFanHistoryCount = 60

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

        // Read temperatures using correct HID sensor keys
        let temps = SensorReaderSwift.readTemperatures()
        // CPU Performance cores: pACC MTR Temp Sensor
        cpuPcoreTemp = getAverageTemp(for: temps, keys: ["pACC MTR Temp Sensor"])
        // CPU Efficiency cores: eACC MTR Temp Sensor
        cpuEcoreTemp = getAverageTemp(for: temps, keys: ["eACC MTR Temp Sensor"])
        // GPU: GPU MTR Temp Sensor
        gpuTemp = getAverageTemp(for: temps, keys: ["GPU MTR Temp Sensor"])
        // Memory: TP*s sensors
        dramTemp = getAverageTemp(for: temps, keys: ["TP0s", "TP1s", "TP2s"])
        // ANE: ANE MTR Temp Sensor
        aneTemp = getAverageTemp(for: temps, keys: ["ANE MTR Temp Sensor"])
        // Storage
        storageTemp = getAverageTemp(for: temps, keys: ["NAND"])
        // Battery
        batteryTemp = getAverageTemp(for: temps, keys: ["gas gauge battery"])

        // Read fan speeds
        readFanSpeeds()

        // Record fan history
        fanLeftHistory.append(fanLeft)
        fanRightHistory.append(fanRight)
        if fanLeftHistory.count > maxFanHistoryCount {
            fanLeftHistory.removeFirst()
        }
        if fanRightHistory.count > maxFanHistoryCount {
            fanRightHistory.removeFirst()
        }

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
        let fanChartHeight: CGFloat = 160
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 20
        let tableHeight: CGFloat = 280
        let totalHeight = toolbarHeight + headerHeight + fanChartHeight + dividerHeight + tableHeight + 16
        let viewWidth: CGFloat = 280

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

        // Fan chart (two circles + line chart)
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
        nameColumn.width = 160
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
        chart.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }

        let chartWidth = chart.bounds.width
        let chartHeight = chart.bounds.height

        // Fan circles at top (radius = 25)
        // Leave space for RPM label above circle (radius + 6 + 12 + padding = ~45 from top)
        let circleRadius: CGFloat = 25
        let circleCenterY = chartHeight - 25 - circleRadius  // 25px from top for RPM label

        // Left fan (purple-ish)
        let leftX = chartWidth / 2 - circleRadius - 30
        let leftPercent = fanLeftMax > 0 ? Double(fanLeft) / Double(fanLeftMax) * 100 : 0
        let leftColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.8, alpha: 0.3)
        createFanCircle(in: chart, center: NSPoint(x: leftX, y: circleCenterY), radius: circleRadius,
                       percent: leftPercent, speed: fanLeft, color: leftColor, label: "L")

        // Right fan (blue-ish)
        let rightX = chartWidth / 2 + circleRadius + 30
        let rightPercent = fanRightMax > 0 ? Double(fanRight) / Double(fanRightMax) * 100 : 0
        let rightColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 0.9, alpha: 0.3)
        createFanCircle(in: chart, center: NSPoint(x: rightX, y: circleCenterY), radius: circleRadius,
                       percent: rightPercent, speed: fanRight, color: rightColor, label: "R")

        // Divider below circles (L/R label is at circleCenterY - radius - 20)
        let lrLabelY = circleCenterY - circleRadius - 20
        let dividerY = lrLabelY - 12  // 12px space between L/R and divider
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: chartWidth - 24, height: 1))
        divider.boxType = .separator
        chart.addSubview(divider)

        // Line chart at bottom
        let lineChartHeight = dividerY - 8
        let lineChart = FanLineChartView(frame: NSRect(x: 12, y: 4, width: chartWidth - 24, height: lineChartHeight))
        lineChart.setHistory(fanLeftHistory, fanRightHistory, maxSpeed: max(fanLeftMax, fanRightMax))
        lineChart.startAnimation()
        chart.addSubview(lineChart)
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

        var input = SMCKeyData()
        var output = SMCKeyData()

        let keyBytes = Array(key.utf8)
        input.key = UInt32(keyBytes[0]) << 24 |
                    UInt32(keyBytes[1]) << 16 |
                    UInt32(keyBytes[2]) << 8 |
                    UInt32(keyBytes[3])
        input.data8 = UInt8(kSMCReadKeyInfo)

        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

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
            let floatValue = withUnsafePointer(to: output.bytes) {
                $0.withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
            }
            return Double(floatValue)
        default:
            return Double(Int(output.bytes.0) << 6 | Int(output.bytes.1) >> 2)
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
            var input = SMCKeyData()
            var output = SMCKeyData()

            input.data8 = UInt8(kSMCGetKeyFromIndex)
            input.data32 = UInt32(i)

            let inputSize = MemoryLayout<SMCKeyData>.stride
            var outputSize = MemoryLayout<SMCKeyData>.stride

            let kr = IOConnectCallStructMethod(smcConnection, UInt32(kSMCKernelIndex), &input, inputSize, &output, &outputSize)
            guard kr == KERN_SUCCESS else { continue }

            // Extract key from output.key
            let key = String(bytes: [
                UInt8((output.key >> 24) & 0xFF),
                UInt8((output.key >> 16) & 0xFF),
                UInt8((output.key >> 8) & 0xFF),
                UInt8(output.key & 0xFF)
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

        // Read from SMC for additional sensors (GPU temps are more reliable via SMC)
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
                // M1 GPU temperatures (SMC keys, more reliable than HID)
                "Tg05": "GPU 1",
                "Tg0D": "GPU 2",
                "Tg0L": "GPU 3",
                "Tg0T": "GPU 4",
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
                L("sensor.cpu.ecore"),
                L("sensor.cpu.pcore"),
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
        // M1 Max actual HID sensor keys from log:
        // - PMU tdie0-10: CPU die temperatures (11 sensors, but M1 Max has 10 cores)
        // - PMU TP0g-3g: GPU temperatures (4 sensors)
        // - PMU TP0s-2s: Memory temperatures
        
        // CPU die temperatures (tdie = die temperature)
        // M1 Max: 8 P-cores + 2 E-cores = 10 cores
        // tdie0-3: E-cores, tdie4-11: P-cores (based on temperature pattern in log)
        if key.hasPrefix("PMU tdie") {
            let suffix = key.replacingOccurrences(of: "PMU tdie", with: "")
            if let num = Int(suffix), num < 10 {
                // M1 Max: E-cores first (tdie0-1), then P-cores (tdie2-9)
                // Based on typical Apple Silicon layout
                if num < 2 {
                    return "\(L("sensor.cpu.ecore")) \(num + 1)"
                } else {
                    return "\(L("sensor.cpu.pcore")) \(num - 1)"
                }
            }
            // tdie10 and beyond are extra sensors, skip
            return ""
        }

        // GPU temperatures (TP*g pattern) - Skip these, use SMC instead (Tg05, Tg0D, Tg0L, Tg0T)
        // HID only shows 3 GPUs, SMC shows all 4
        if key.hasPrefix("PMU TP") && key.hasSuffix("g") {
            return ""
        }

        // Memory temperatures (TP*s pattern)
        if key.hasPrefix("PMU TP") && key.hasSuffix("s") {
            return L("sensor.memory")
        }

        // Other known sensors
        if key.contains("NAND") { return L("sensor.storage") }
        if key.contains("gas gauge") { return L("sensor.battery") }

        // Skip PMU tdev, tcal and other unknown sensors
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

private struct SMCKeyData {
    // Exact copy from Stats SMC/smc.swift
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}

// MARK: - Fan Line Chart View

/// Fan speed line chart with smooth curves and scrolling animation
final class FanLineChartView: NSView {
    private var leftHistory: [Int] = []
    private var rightHistory: [Int] = []
    private var maxSpeed: Int = 6000
    private var displayLink: CVDisplayLink?
    private var lastUpdateTime: Date = Date()
    private let sampleInterval: TimeInterval = 2.0
    private var isRunning = false

    private let leftColor = NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.8, alpha: 1.0)
    private let rightColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 0.9, alpha: 1.0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        isRunning = false
        stopAnimation()
    }

    func setHistory(_ left: [Int], _ right: [Int], maxSpeed: Int) {
        self.leftHistory = left
        self.rightHistory = right
        self.maxSpeed = maxSpeed > 0 ? maxSpeed : 6000
        lastUpdateTime = Date()
        needsDisplay = true
    }

    func startAnimation() {
        guard displayLink == nil else { return }
        isRunning = true

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<FanLineChartView>.fromOpaque(userInfo).takeUnretainedValue()
            guard view.isRunning else { return kCVReturnSuccess }
            DispatchQueue.main.async {
                guard view.isRunning else { return }
                view.needsDisplay = true
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
        displayLink = link
    }

    func stopAnimation() {
        isRunning = false
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard leftHistory.count > 1 || rightHistory.count > 1 else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(true)

        let padding: CGFloat = 8
        let height = bounds.height - padding * 2
        let width = bounds.width - padding * 2
        let xRatio = width / CGFloat(60 - 1)

        // Smooth scroll animation
        let elapsed = Date().timeIntervalSince(lastUpdateTime)
        let progress = min(elapsed / sampleInterval, 1.0)
        let xOffset = progress * xRatio

        // Draw left fan line (purple)
        if leftHistory.count > 1 {
            drawLine(history: leftHistory, color: leftColor, padding: padding, height: height, xRatio: xRatio, xOffset: xOffset)
        }

        // Draw right fan line (blue)
        if rightHistory.count > 1 {
            drawLine(history: rightHistory, color: rightColor, padding: padding, height: height, xRatio: xRatio, xOffset: xOffset)
        }
    }

    private func drawLine(history: [Int], color: NSColor, padding: CGFloat, height: CGFloat, xRatio: CGFloat, xOffset: CGFloat) {
        var points: [CGPoint] = []

        for (i, speed) in history.enumerated() {
            let x = bounds.width - padding - CGFloat(history.count - 1 - i) * xRatio - xOffset
            let bottomPadding: CGFloat = 4
            let y = padding + CGFloat(speed) / CGFloat(maxSpeed) * (height - bottomPadding)
            points.append(CGPoint(x: x, y: y))
        }

        guard points.count > 1 else { return }

        let path = NSBezierPath()
        path.move(to: points[0])

        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            let midX = (prev.x + curr.x) / 2
            path.curve(to: curr, controlPoint1: CGPoint(x: midX, y: prev.y), controlPoint2: CGPoint(x: midX, y: curr.y))
        }

        path.lineWidth = 1.5
        color.setStroke()
        path.stroke()
    }
}
