// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit

/// GPU process information.
struct GPUProcessInfo {
    let pid: Int32
    let name: String
    var gpuUsage: Double
    let memoryUsage: UInt64
    let isApp: Bool
    let icon: NSImage?
    let user: String
    let threads: Int
}

/// GPU monitoring module.
final class GPUModule: NSObject, StatusModule {
    
    var identifier: String { "gpu" }
    var displayName: String { L("status.gpu.displayName") }
    var shortName: String { "GPU" }
    
    private(set) var summaryText: String = "0%"
    private(set) var summaryValue: String = "0%"
    
    var refreshInterval: TimeInterval { 2.0 }
    
    private var processes: [GPUProcessInfo] = []
    private var gpuUsage: Double = 0
    private var rendererUtil: Double = 0
    private var tilerUtil: Double = 0
    private var vramUsed: UInt64 = 0
    private var vramTotal: UInt64 = 0
    
    // GPU time tracking for per-process usage
    private var prevGpuTimes: [Int32: UInt64] = [:]
    private var prevTimestamp: TimeInterval = 0
    private let gpuTimeLock = NSLock()
    
    private weak var chartView: NSView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?
    
    func refreshSummary() {
        let info = getGPUInfo()
        self.gpuUsage = info.device
        self.rendererUtil = info.renderer
        self.tilerUtil = info.tiler
        self.vramUsed = info.vramUsed
        self.vramTotal = info.vramTotal
        
        processes = getGPUProcesses(limit: 100)
        
        let value = String(format: "%.0f%%", info.device)
        summaryText = value
        summaryValue = value
    }
    
    func makeDetailView() -> NSView {
        // Calculate height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 100
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 30
        let totalHeight = headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 400
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)
        
        // GPU usage chart
        let chartY = totalHeight - headerHeight - chartHeight
        let chart = createUsageChart(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chartView = chart
        container.addSubview(chart)
        
        // Divider line
        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: viewWidth - 24, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)
        
        // Process list with columns: Name, PID, User, Threads, GPU%
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: dividerY))
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
        nameColumn.headerCell.title = "Name"
        table.addTableColumn(nameColumn)
        
        let pidColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
        pidColumn.width = 55
        pidColumn.headerCell.title = "PID"
        table.addTableColumn(pidColumn)
        
        let userColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("user"))
        userColumn.width = 48
        userColumn.headerCell.title = "User"
        table.addTableColumn(userColumn)
        
        let threadsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("threads"))
        threadsColumn.width = 35
        threadsColumn.headerCell.title = "Thr"
        table.addTableColumn(threadsColumn)
        
        let gpuColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("gpu"))
        gpuColumn.width = 50
        gpuColumn.headerCell.title = "GPU"
        table.addTableColumn(gpuColumn)
        
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
        let info = getGPUInfo()
        self.gpuUsage = info.device
        self.rendererUtil = info.renderer
        self.tilerUtil = info.tiler
        self.vramUsed = info.vramUsed
        self.vramTotal = info.vramTotal

        // Update summary to keep in sync
        let value = String(format: "%.0f%%", info.device)
        summaryText = value
        summaryValue = value

        processes = getGPUProcesses(limit: 100)

        updateChart()
        tableView?.reloadData()

        // Notify controller to update status bar
        NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "gpu"])
    }
    
    private func updateChart() {
        guard let chart = chartView else { return }

        chart.subviews.forEach { $0.removeFromSuperview() }

        let chartWidth = chart.bounds.width
        let chartHeight = chart.bounds.height

        // Layout: left small, center large, right small
        let bigRadius: CGFloat = 28
        let smallRadius: CGFloat = 20

        // Center pie (Device) - larger
        let centerX = chartWidth / 2
        let centerY = chartHeight / 2 - 4
        createPieChart(in: chart, center: NSPoint(x: centerX, y: centerY), radius: bigRadius,
                       value: gpuUsage, color: NSColor.systemPurple, label: "Device")

        // Left pie (Renderer) - smaller
        let leftX = centerX - bigRadius - smallRadius - 20
        createPieChart(in: chart, center: NSPoint(x: leftX, y: centerY), radius: smallRadius,
                       value: rendererUtil, color: NSColor.systemBlue, label: "Renderer")

        // Right pie (Tiler) - smaller
        let rightX = centerX + bigRadius + smallRadius + 20
        createPieChart(in: chart, center: NSPoint(x: rightX, y: centerY), radius: smallRadius,
                       value: tilerUtil, color: NSColor.systemOrange, label: "Tiler")
    }

    private func createPieChart(in parent: NSView, center: NSPoint, radius: CGFloat,
                                value: Double, color: NSColor, label: String) {
        // Solid colored circle
        let circle = NSView(frame: NSRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        circle.wantsLayer = true
        circle.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        circle.layer?.cornerRadius = radius
        parent.addSubview(circle)

        // Center percentage label (white/light color)
        let pctLabel = NSTextField(labelWithString: String(format: "%.0f%%", value))
        pctLabel.font = .systemFont(ofSize: radius > 24 ? 13 : 10, weight: .semibold)
        pctLabel.textColor = NSColor.white
        pctLabel.alignment = .center
        let labelWidth = radius > 24 ? 50.0 : 35.0
        pctLabel.frame = NSRect(x: center.x - labelWidth / 2, y: center.y - 6,
                                width: labelWidth, height: 14)
        parent.addSubview(pctLabel)

        // Name label below
        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: center.x - 45, y: center.y - radius - 18, width: 90, height: 14)
        parent.addSubview(nameLabel)
    }

    private func createUsageChart(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        view.layer?.cornerRadius = 4

        let chartWidth = frame.width
        let chartHeight = frame.height

        let bigRadius: CGFloat = 30
        let smallRadius: CGFloat = 22

        // Center circle (Device)
        let centerX = chartWidth / 2
        let centerY = chartHeight / 2 + 4
        createPieChart(in: view, center: NSPoint(x: centerX, y: centerY), radius: bigRadius,
                       value: gpuUsage, color: NSColor.systemPurple, label: "Device")

        // Left circle (Renderer)
        let leftX = centerX - bigRadius - smallRadius - 24
        createPieChart(in: view, center: NSPoint(x: leftX, y: centerY), radius: smallRadius,
                       value: rendererUtil, color: NSColor.systemBlue, label: "Renderer")

        // Right circle (Tiler)
        let rightX = centerX + bigRadius + smallRadius + 24
        createPieChart(in: view, center: NSPoint(x: rightX, y: centerY), radius: smallRadius,
                       value: tilerUtil, color: NSColor.systemOrange, label: "Tiler")

        return view
    }
    
    // MARK: - GPU Data from IORegistry
    
    private func getGPUInfo() -> (device: Double, renderer: Double, tiler: Double, vramUsed: UInt64, vramTotal: UInt64) {
        var deviceUtil: Double = 0
        var rendererUtil: Double = 0
        var tilerUtil: Double = 0
        var vramUsed: UInt64 = 0
        var vramTotal: UInt64 = 0

        // Try IOAccelerator first, then AGXAccelerator
        var iterator: io_iterator_t = 0
        var matching = IOServiceMatching("IOAccelerator")
        var result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        if result != KERN_SUCCESS || iterator == 0 {
            // Try AGXAccelerator for Apple Silicon
            matching = IOServiceMatching("AGXAccelerator")
            result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        }

        guard result == KERN_SUCCESS, iterator != 0 else {
            return (0, 0, 0, 0, 0)
        }

        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = props["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            // Debug: log available keys
            if LogSettings.shared.monitorLogEnabled {
                let keys = statistics.keys.sorted().joined(separator: ", ")
                LogSettings.write("GPU PerformanceStatistics keys: \(keys)", to: LogSettings.shared.monitorLogPath)
            }

            // Get Device Utilization %
            if let num = statistics["Device Utilization %"] as? NSNumber {
                deviceUtil = num.doubleValue
                if LogSettings.shared.monitorLogEnabled {
                    LogSettings.write("GPU Device Utilization: \(deviceUtil)", to: LogSettings.shared.monitorLogPath)
                }
            } else if let val = statistics["Device Utilization %"] as? Double {
                deviceUtil = val
            } else if let val = statistics["Device Utilization %"] as? Int {
                deviceUtil = Double(val)
            }

            // Get Renderer Utilization %
            if let num = statistics["Renderer Utilization %"] as? NSNumber {
                rendererUtil = num.doubleValue
            } else if let val = statistics["Renderer Utilization %"] as? Double {
                rendererUtil = val
            } else if let val = statistics["Renderer Utilization %"] as? Int {
                rendererUtil = Double(val)
            }

            // Get Tiler Utilization %
            if let num = statistics["Tiler Utilization %"] as? NSNumber {
                tilerUtil = num.doubleValue
            } else if let val = statistics["Tiler Utilization %"] as? Double {
                tilerUtil = val
            } else if let val = statistics["Tiler Utilization %"] as? Int {
                tilerUtil = Double(val)
            }
            
            // VRAM (discrete GPUs only)
            if let vramFree = statistics["vramFreeBytes"] as? UInt64,
               let vramTotalVal = statistics["vramTotalBytes"] as? UInt64 {
                vramUsed = vramTotalVal - vramFree
                vramTotal = vramTotalVal
            }
            
            break
        }
        
        return (deviceUtil, rendererUtil, tilerUtil, vramUsed, vramTotal)
    }
    
    private func getGPUProcesses(limit: Int) -> [GPUProcessInfo] {
        // Get per-process GPU time from IORegistry AGXDeviceUserClient
        let gpuTimes = getProcessGPUTimesFromIORegistry()
        
        // Get running apps for icons and names
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs = Set<Int32>()
        var appNames: [Int32: String] = [:]
        var appIcons: [Int32: NSImage] = [:]
        
        for app in runningApps {
            guard let url = app.bundleURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let pid = app.processIdentifier
            appPIDs.insert(pid)
            appNames[pid] = name
            if let icon = app.icon {
                appIcons[pid] = icon
            }
        }
        
        // Build process list from GPU data
        var processes: [GPUProcessInfo] = []
        
        for (pid, gpuTime) in gpuTimes {
            guard pid > 0 else { continue }
            
            // Get process name
            var name: String
            if let appName = appNames[pid] {
                name = appName
            } else if let path = getProcessPath(pid: pid) {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
                // Fallback to comm name
                var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
                var proc = kinfo_proc()
                var size = MemoryLayout<kinfo_proc>.size
                if sysctl(&mib, 4, &proc, &size, nil, 0) == 0 {
                    let comm = withUnsafePointer(to: proc.kp_proc.p_comm) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) { ptr in
                            String(cString: ptr)
                        }
                    }
                    name = comm
                } else {
                    name = "process"
                }
            }
            
            name = name.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.map { Character($0) }.map { String($0) }.joined()
            if name.isEmpty { name = "process" }
            
            let isApp = appPIDs.contains(pid)
            let uid = getProcessUID(pid: pid)
            let user = getProcessUser(uid: uid)
            let threads = getProcessThreads(pid: pid)
            let memory = getProcessMemoryUsage(pid: pid)
            
            processes.append(GPUProcessInfo(
                pid: pid,
                name: name,
                gpuUsage: gpuTime,
                memoryUsage: memory,
                isApp: isApp,
                icon: appIcons[pid],
                user: user,
                threads: threads
            ))
        }
        
        // Sort by GPU usage
        processes.sort { $0.gpuUsage > $1.gpuUsage }
        return Array(processes.prefix(limit))
    }
    
    private func getProcessGPUTimesFromIORegistry() -> [Int32: Double] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AGXAccelerator")
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        
        let gpuService = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        
        guard gpuService != 0 else {
            return [:]
        }
        
        defer { IOObjectRelease(gpuService) }
        
        // Iterate over AGXDeviceUserClient children
        var childIter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(gpuService, kIOServicePlane, &childIter) == KERN_SUCCESS else {
            return [:]
        }
        
        defer { IOObjectRelease(childIter) }
        
        var currentTimes: [Int32: UInt64] = [:]
        var child = IOIteratorNext(childIter)
        
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(childIter)
            }
            
            // Get class name
            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(child, &className)
            let classNameString = String(cString: className)
            
            guard classNameString == "AGXDeviceUserClient" else { continue }
            
            // Get properties
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }
            
            // Extract PID from IOUserClientCreator
            guard let creator = props["IOUserClientCreator"] as? String else { continue }
            
            // Parse "pid XXX, process_name" format
            let parts = creator.split(separator: ",", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let pidPart = String(parts[0].trimmingCharacters(in: .whitespaces))
            guard pidPart.hasPrefix("pid "), let pid = Int32(pidPart.dropFirst(4)) else { continue }
            
            // Extract AppUsage data
            guard let appUsage = props["AppUsage"] as? [[String: Any]] else { continue }
            
            var processGPUTime: UInt64 = 0
            for usage in appUsage {
                if let gpuTime = usage["accumulatedGPUTime"] as? UInt64 {
                    processGPUTime += gpuTime
                }
            }
            
            if processGPUTime > 0 {
                currentTimes[pid] = processGPUTime
            }
        }
        
        // Calculate percentage from delta
        let now = Date().timeIntervalSince1970
        gpuTimeLock.lock()
        defer { gpuTimeLock.unlock() }
        
        var result: [Int32: Double] = [:]
        let timeDelta = now - prevTimestamp
        
        if timeDelta > 0 && prevTimestamp > 0 {
            for (pid, time) in currentTimes {
                if let prev = prevGpuTimes[pid] {
                    let delta = time > prev ? time - prev : 0
                    // accumulatedGPUTime is in nanoseconds
                    let deltaTimeS = Double(delta) / 1_000_000_000.0
                    let percentage = (deltaTimeS / timeDelta) * 100.0
                    result[pid] = percentage
                }
            }
        }
        
        prevGpuTimes = currentTimes
        prevTimestamp = now
        
        return result
    }
    
    private func getProcessPath(pid: Int32) -> String? {
        let maxPathSize = 4096
        var path = [CChar](repeating: 0, count: maxPathSize)
        let count = proc_pidpath(pid, &path, UInt32(maxPathSize))
        guard count > 0 else { return nil }
        return String(cString: path)
    }
    
    private func getProcessUID(pid: Int32) -> uid_t {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &proc, &size, nil, 0) == 0 {
            return proc.kp_eproc.e_ucred.cr_uid
        }
        return 0
    }
    
    private func getProcessUser(uid: uid_t) -> String {
        if let pw = getpwuid(uid) {
            return String(cString: pw.pointee.pw_name)
        }
        return "uid:\(uid)"
    }
    
    private func getProcessThreads(pid: Int32) -> Int {
        var info = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard size > 0 else { return 0 }
        return Int(info.pti_threadnum)
    }
    
    private func getProcessMemoryUsage(pid: Int32) -> UInt64 {
        var rusage = rusage_info_current()
        let rusagePtr = withUnsafeMutablePointer(to: &rusage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { $0 }
        }
        let result = proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rusagePtr)
        guard result == 0 else { return 0 }
        return rusage.ri_resident_size
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension GPUModule: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return processes.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < processes.count else { return nil }
        let process = processes[row]
        
        let cell = NSTableCellView()
        let colId = tableColumn?.identifier.rawValue ?? ""
        
        switch colId {
        case "name":
            if let icon = process.icon {
                let iconView = NSImageView(frame: NSRect(x: 4, y: 2, width: 16, height: 16))
                iconView.image = icon
                iconView.imageScaling = .scaleProportionallyDown
                cell.addSubview(iconView)
                
                let label = NSTextField(labelWithString: process.name)
                label.font = .systemFont(ofSize: 10)
                label.lineBreakMode = .byTruncatingTail
                label.frame = NSRect(x: 24, y: 2, width: 122, height: 16)
                cell.addSubview(label)
            } else {
                let label = NSTextField(labelWithString: process.name)
                label.font = .systemFont(ofSize: 10)
                label.lineBreakMode = .byTruncatingTail
                label.frame = NSRect(x: 4, y: 2, width: 142, height: 16)
                cell.addSubview(label)
            }
            
        case "pid":
            let label = NSTextField(labelWithString: "\(process.pid)")
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 47, height: 16)
            cell.addSubview(label)
            
        case "user":
            let label = NSTextField(labelWithString: process.user)
            label.font = .systemFont(ofSize: 10)
            label.textColor = process.user == "root" ? NSColor.systemRed : .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 4, y: 2, width: 40, height: 16)
            cell.addSubview(label)
            
        case "threads":
            let label = NSTextField(labelWithString: "\(process.threads)")
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 27, height: 16)
            cell.addSubview(label)
            
        case "gpu":
            let label = NSTextField(labelWithString: String(format: "%.1f%%", process.gpuUsage))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 42, height: 16)
            cell.addSubview(label)
            
        default:
            break
        }
        
        return cell
    }
}