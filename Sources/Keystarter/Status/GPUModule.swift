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
    
    var refreshInterval: TimeInterval { 3.0 }
    
    private var processes: [GPUProcessInfo] = []
    private var gpuUsage: Double = 0
    private var vramUsed: UInt64 = 0
    private var vramTotal: UInt64 = 0
    
    // GPU energy tracking for per-process usage estimation
    private var prevGpuEnergy: [Int32: UInt64] = [:]
    private let gpuEnergyLock = NSLock()
    
    private weak var chartView: NSView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?
    
    func refreshSummary() {
        let (usage, vramUsed, vramTotal) = getGPUInfo()
        self.gpuUsage = usage
        self.vramUsed = vramUsed
        self.vramTotal = vramTotal
        
        processes = getGPUProcesses(limit: 100)
        
        let value = String(format: "%.0f%%", usage)
        summaryText = value
        summaryValue = value
    }
    
    func makeDetailView() -> NSView {
        // Calculate height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 80
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
        detailTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshDetail()
        }
    }
    
    private func refreshDetail() {
        let (usage, vramUsed, vramTotal) = getGPUInfo()
        self.gpuUsage = usage
        self.vramUsed = vramUsed
        self.vramTotal = vramTotal
        
        processes = getGPUProcesses(limit: 100)
        
        updateChart()
        tableView?.reloadData()
    }
    
    private func updateChart() {
        guard let chart = chartView else { return }
        
        chart.subviews.forEach { $0.removeFromSuperview() }
        
        let barWidth = chart.bounds.width - 24
        let maxBarHeight = chart.bounds.height - 28
        let barHeight = max(4, min(CGFloat(gpuUsage / 100.0) * maxBarHeight, maxBarHeight))
        
        // Usage bar
        let bar = NSView(frame: NSRect(x: 12, y: 16, width: barWidth, height: barHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.7).cgColor
        bar.layer?.cornerRadius = 2
        chart.addSubview(bar)
        
        // VRAM info
        let vramUsedGB = Double(vramUsed) / 1_073_741_824.0
        let vramTotalGB = Double(vramTotal) / 1_073_741_824.0
        let vramText = vramTotal > 0 ? String(format: "VRAM: %.1f/%.1f GB", vramUsedGB, vramTotalGB) : ""
        let vramLabel = NSTextField(labelWithString: vramText)
        vramLabel.font = .systemFont(ofSize: 10)
        vramLabel.textColor = .secondaryLabelColor
        vramLabel.alignment = .right
        vramLabel.frame = NSRect(x: barWidth - 100, y: chart.bounds.height - 12, width: 100, height: 10)
        chart.addSubview(vramLabel)
        
        // Percentage
        let pctLabel = NSTextField(labelWithString: String(format: "%.1f%%", gpuUsage))
        pctLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pctLabel.alignment = .center
        pctLabel.frame = NSRect(x: 12, y: chart.bounds.height - 16, width: 80, height: 12)
        chart.addSubview(pctLabel)
    }
    
    private func createUsageChart(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        view.layer?.cornerRadius = 4
        
        let barWidth = frame.width - 24
        let maxBarHeight = frame.height - 28
        let barHeight = max(4, min(CGFloat(gpuUsage / 100.0) * maxBarHeight, maxBarHeight))
        
        let bar = NSView(frame: NSRect(x: 12, y: 16, width: barWidth, height: barHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.7).cgColor
        bar.layer?.cornerRadius = 2
        view.addSubview(bar)
        
        let vramUsedGB = Double(vramUsed) / 1_073_741_824.0
        let vramTotalGB = Double(vramTotal) / 1_073_741_824.0
        let vramText = vramTotal > 0 ? String(format: "VRAM: %.1f/%.1f GB", vramUsedGB, vramTotalGB) : ""
        let vramLabel = NSTextField(labelWithString: vramText)
        vramLabel.font = .systemFont(ofSize: 10)
        vramLabel.textColor = .secondaryLabelColor
        vramLabel.alignment = .right
        vramLabel.frame = NSRect(x: barWidth - 100, y: frame.height - 12, width: 100, height: 10)
        view.addSubview(vramLabel)
        
        let pctLabel = NSTextField(labelWithString: String(format: "%.1f%%", gpuUsage))
        pctLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pctLabel.alignment = .center
        pctLabel.frame = NSRect(x: 12, y: frame.height - 16, width: 80, height: 12)
        view.addSubview(pctLabel)
        
        return view
    }
    
    // MARK: - GPU Data
    
    private func getGPUInfo() -> (usage: Double, vramUsed: UInt64, vramTotal: UInt64) {
        var gpuUsage: Double = 0
        var vramUsed: UInt64 = 0
        var vramTotal: UInt64 = 0
        
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        
        guard result == KERN_SUCCESS, iterator != 0 else {
            return (0, 0, 0)
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
            
            if let deviceUtil = statistics["Device Utilization"] as? Double {
                gpuUsage = deviceUtil * 100
            } else if let utilization = statistics["utilization"] as? Double {
                gpuUsage = utilization
            } else if let deviceUtil = statistics["Device Utilization"] as? Int {
                gpuUsage = Double(deviceUtil)
            } else if let activeTime = statistics["totalActiveTime"] as? UInt64,
                      let idleTime = statistics["totalIdleTime"] as? UInt64 {
                let total = activeTime + idleTime
                if total > 0 {
                    gpuUsage = Double(activeTime) / Double(total) * 100.0
                }
            }
            
            if let vramFree = statistics["vramFreeBytes"] as? UInt64,
               let vramTotalVal = statistics["vramTotalBytes"] as? UInt64 {
                vramUsed = vramTotalVal - vramFree
                vramTotal = vramTotalVal
            }
            
            break
        }
        
        return (gpuUsage, vramUsed, vramTotal)
    }
    
    private func getGPUProcesses(limit: Int) -> [GPUProcessInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs = Set<Int32>()
        var appNames: [Int32: String] = [:]
        var appIcons: [Int32: NSImage] = [:]
        
        for app in runningApps {
            guard let url = app.bundleURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let pid = app.processIdentifier
            if app.activationPolicy == .regular {
                appPIDs.insert(pid)
            }
            appNames[pid] = name
            if let icon = app.icon {
                appIcons[pid] = icon
            }
        }
        
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 3, &procList, &size, nil, 0)
        
        var processes: [GPUProcessInfo] = []
        
        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            var name: String
            if let path = getProcessPath(pid: pid) {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
                name = String(cString: withUnsafePointer(to: proc.kp_proc.p_comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) { $0 }
                })
            }
            name = name.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.map { Character($0) }.map { String($0) }.joined()
            if name.isEmpty { name = "process" }
            
            let isApp = appPIDs.contains(pid)
            let uid = proc.kp_eproc.e_ucred.cr_uid
            let user = getProcessUser(uid: uid)
            let threads = getProcessThreads(pid: pid)
            let memory = getProcessMemoryUsage(pid: pid)
            let gpuEnergy = getProcessGPUEnergy(pid: pid)
            
            processes.append(GPUProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                gpuUsage: gpuEnergy,
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
    
    private func getProcessPath(pid: Int32) -> String? {
        let maxPathSize = 4096
        var path = [CChar](repeating: 0, count: maxPathSize)
        let count = proc_pidpath(pid, &path, UInt32(maxPathSize))
        guard count > 0 else { return nil }
        return String(cString: path)
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
    
    private func getProcessGPUEnergy(pid: Int32) -> Double {
        // Use rusage_info_v4 to get GPU energy (private API)
        // ri_gpu_energy is at offset in rusage_info_v4
        var rusage = rusage_info_current()
        let rusagePtr = withUnsafeMutablePointer(to: &rusage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { $0 }
        }
        let result = proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
        guard result == 0 else { return 0 }
        
        // ri_gpu_energy is field 32 in rusage_info_v4 (nJ - nanojoules)
        // Access via memory offset since Swift doesn't have the struct definition
        let gpuEnergy: UInt64 = withUnsafePointer(to: rusage) {
            $0.withMemoryRebound(to: UInt64.self, capacity: 64) {
                $0[32]  // ri_gpu_energy offset
            }
        }
        
        // Calculate delta and convert to percentage
        gpuEnergyLock.lock()
        defer { gpuEnergyLock.unlock() }

        let prev = prevGpuEnergy[pid] ?? 0
        let delta = gpuEnergy > prev ? gpuEnergy - prev : 0
        prevGpuEnergy[pid] = gpuEnergy
        
        // Convert nJ to percentage (rough approximation)
        // This gives relative GPU activity, not exact usage
        return min(Double(delta) / 1_000_000_000.0, 100.0)  // Normalize to reasonable range
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