// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit

/// Disk process information.
struct DiskProcessInfo {
    let pid: Int32
    let name: String
    let isApp: Bool
    let icon: NSImage?
    let user: String
    let ppid: Int32
    var readSpeed: Double
    var writeSpeed: Double
}

/// Disk monitoring module.
final class DiskModule: NSObject, StatusModule {
    
    var identifier: String { "disk" }
    var displayName: String { L("status.disk.displayName") }
    var shortName: String { "DSK" }
    
    private(set) var summaryText: String = "R-- W--"
    private(set) var summaryValue: String = "--"
    
    // Public read/write speed text for status bar
    var readSpeedText: String { formatSpeed(readSpeed) }
    var writeSpeedText: String { formatSpeed(writeSpeed) }
    
    var refreshInterval: TimeInterval { 2.0 }
    
    private var previousReadBytes: UInt64 = 0
    private var previousWriteBytes: UInt64 = 0
    private var previousTime: Date = Date()
    
    // Per-process disk I/O tracking
    private var prevDiskIO: [Int32: (read: UInt64, write: UInt64, time: Date)] = [:]
    private var diskIOLock = NSLock()
    
    // History for charts
    private var readHistory: [Double] = []
    private var writeHistory: [Double] = []
    private let maxHistoryCount = 60
    
    private var processes: [DiskProcessInfo] = []
    private var readSpeed: Double = 0
    private var writeSpeed: Double = 0
    
    private weak var chartView: NSView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?
    
    func refreshSummary() {
        // Only update from summary if detail view is not open
        guard detailTimer == nil else { return }
        updateDiskData()
    }
    
    private func updateDiskData() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let (readBytes, writeBytes) = self.getDiskBytes()
            let now = Date()
            let elapsed = now.timeIntervalSince(self.previousTime)
            
            var newReadSpeed: Double = 0
            var newWriteSpeed: Double = 0
            
            if elapsed >= 0.5 {
                let readDelta = readBytes > self.previousReadBytes ? readBytes - self.previousReadBytes : 0
                let writeDelta = writeBytes > self.previousWriteBytes ? writeBytes - self.previousWriteBytes : 0
                
                newReadSpeed = Double(readDelta) / elapsed
                newWriteSpeed = Double(writeDelta) / elapsed
            }
            
            self.previousReadBytes = readBytes
            self.previousWriteBytes = writeBytes
            self.previousTime = now
            
            let newProcesses = self.getProcessesByDiskIO(limit: 100)
            
            DispatchQueue.main.async {
                // Update history arrays
                self.readHistory.append(newReadSpeed)
                self.writeHistory.append(newWriteSpeed)
                if self.readHistory.count > self.maxHistoryCount { self.readHistory.removeFirst() }
                if self.writeHistory.count > self.maxHistoryCount { self.writeHistory.removeFirst() }
                
                self.readSpeed = newReadSpeed
                self.writeSpeed = newWriteSpeed
                self.processes = newProcesses
                
                // Only update chart and notify if detail view is open
                if self.detailTimer != nil {
                    self.updateChart()
                    self.tableView?.reloadData()
                    NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "disk"])
                }
            }
        }
    }
    
    func makeDetailView() -> NSView {
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 100
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 30
        let totalHeight = headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 450  // Increased from 400 to show all columns
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)
        
        // Disk I/O chart (mirrored read/write)
        let chartY = totalHeight - headerHeight - chartHeight
        let chart = createDiskChart(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chartView = chart
        container.addSubview(chart)
        
        // Divider
        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: viewWidth - 24, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)
        
        // Process list: Name, PID, User, Write Speed, Read Speed
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
        
        let writeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("write"))
        writeColumn.width = 65
        writeColumn.headerCell.title = "Write"
        table.addTableColumn(writeColumn)
        
        let readColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("read"))
        readColumn.width = 65
        readColumn.headerCell.title = "Read"
        table.addTableColumn(readColumn)
        
        table.dataSource = self
        table.delegate = self
        
        scrollView.documentView = table
        tableView = table
        container.addSubview(scrollView)
        
        // Refresh on open
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
        updateDiskData()
    }
    
    private func updateChart() {
        guard let chart = chartView else { return }
        
        // Remove both subviews and sublayers
        chart.subviews.forEach { $0.removeFromSuperview() }
        chart.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        let chartWidth = chart.bounds.width
        let chartHeight = chart.bounds.height
        let chartPadding: CGFloat = 8
        let centerLineY = chartHeight / 2
        let halfHeight = chartHeight / 2 - chartPadding - 8
        let drawWidth = chartWidth - chartPadding * 2
        let stepX = drawWidth / CGFloat(maxHistoryCount - 1)
        
        // Find max for scaling
        let maxRead = readHistory.max() ?? 1
        let maxWrite = writeHistory.max() ?? 1
        let maxVal = max(maxRead, maxWrite, 1)
        
        // Draw center line
        let centerLine = NSView(frame: NSRect(x: chartPadding, y: centerLineY - 1, width: drawWidth, height: 2))
        centerLine.wantsLayer = true
        centerLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        chart.addSubview(centerLine)
        
        // Calculate points for read and write
        let readPoints: [CGPoint] = readHistory.enumerated().map { index, value in
            let x = chartWidth - chartPadding - CGFloat(readHistory.count - 1 - index) * stepX
            let y = centerLineY + min(value / maxVal, 1.0) * halfHeight
            return CGPoint(x: x, y: y)
        }
        
        let writePoints: [CGPoint] = writeHistory.enumerated().map { index, value in
            let x = chartWidth - chartPadding - CGFloat(writeHistory.count - 1 - index) * stepX
            let y = centerLineY - min(value / maxVal, 1.0) * halfHeight
            return CGPoint(x: x, y: y)
        }
        
        // Draw read chart (top half, above center line)
        if readPoints.count > 1 {
            // Area path
            let readAreaPath = CGMutablePath()
            readAreaPath.move(to: CGPoint(x: readPoints[0].x, y: centerLineY))
            readAreaPath.addLine(to: readPoints[0])
            
            // Build smooth curve directly
            for i in 1..<readPoints.count {
                let prev = readPoints[i - 1]
                let curr = readPoints[i]
                let midX = (prev.x + curr.x) / 2
                let midY = (prev.y + curr.y) / 2
                readAreaPath.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: prev.y))
                readAreaPath.addQuadCurve(to: curr, control: CGPoint(x: midX, y: midY))
            }
            
            readAreaPath.addLine(to: CGPoint(x: readPoints.last!.x, y: centerLineY))
            readAreaPath.closeSubpath()
            
            let readLayer = CAShapeLayer()
            readLayer.path = readAreaPath
            readLayer.fillColor = NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 0.2).cgColor
            chart.layer?.addSublayer(readLayer)
            
            // Smooth line
            let readLinePath = createSmoothPath(points: readPoints)
            let readLineLayer = CAShapeLayer()
            readLineLayer.path = readLinePath
            readLineLayer.fillColor = nil
            readLineLayer.strokeColor = NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 0.8).cgColor
            readLineLayer.lineWidth = 1.5
            readLineLayer.lineCap = .round
            readLineLayer.lineJoin = .round
            chart.layer?.addSublayer(readLineLayer)
        }
        
        // Draw write chart (bottom half, below center line)
        if writePoints.count > 1 {
            // Area path
            let writeAreaPath = CGMutablePath()
            writeAreaPath.move(to: CGPoint(x: writePoints[0].x, y: centerLineY))
            writeAreaPath.addLine(to: writePoints[0])
            
            // Build smooth curve directly
            for i in 1..<writePoints.count {
                let prev = writePoints[i - 1]
                let curr = writePoints[i]
                let midX = (prev.x + curr.x) / 2
                let midY = (prev.y + curr.y) / 2
                writeAreaPath.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: prev.y))
                writeAreaPath.addQuadCurve(to: curr, control: CGPoint(x: midX, y: midY))
            }
            
            writeAreaPath.addLine(to: CGPoint(x: writePoints.last!.x, y: centerLineY))
            writeAreaPath.closeSubpath()
            
            let writeLayer = CAShapeLayer()
            writeLayer.path = writeAreaPath
            writeLayer.fillColor = NSColor(red: 0.7, green: 0.4, blue: 0.5, alpha: 0.2).cgColor
            chart.layer?.addSublayer(writeLayer)
            
            // Smooth line
            let writeLinePath = createSmoothPath(points: writePoints)
            let writeLineLayer = CAShapeLayer()
            writeLineLayer.path = writeLinePath
            writeLineLayer.fillColor = nil
            writeLineLayer.strokeColor = NSColor(red: 0.7, green: 0.4, blue: 0.5, alpha: 0.8).cgColor
            writeLineLayer.lineWidth = 1.5
            writeLineLayer.lineCap = .round
            writeLineLayer.lineJoin = .round
            chart.layer?.addSublayer(writeLineLayer)
        }
        
        // Labels
        let readLabel = NSTextField(labelWithString: "R \(formatSpeed(readSpeed))")
        readLabel.font = NSFont.systemFont(ofSize: 10)
        readLabel.textColor = .secondaryLabelColor
        readLabel.frame = NSRect(x: chartWidth - 80, y: chartHeight - 16, width: 70, height: 12)
        chart.addSubview(readLabel)
        
        let writeLabel = NSTextField(labelWithString: "W \(formatSpeed(writeSpeed))")
        writeLabel.font = NSFont.systemFont(ofSize: 10)
        writeLabel.textColor = .secondaryLabelColor
        writeLabel.frame = NSRect(x: chartWidth - 80, y: 4, width: 70, height: 12)
        chart.addSubview(writeLabel)
    }
    
    private func createSmoothPath(points: [CGPoint]) -> CGMutablePath {
        let path = CGMutablePath()
        guard points.count > 1 else { return path }
        
        path.move(to: points[0])
        
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            
            // Calculate control points for smooth curve
            let midX = (prev.x + curr.x) / 2
            let midY = (prev.y + curr.y) / 2
            
            // Use quadratic bezier with midpoint as control
            path.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: prev.y))
            path.addQuadCurve(to: curr, control: CGPoint(x: midX, y: midY))
        }
        
        return path
    }
    
    private func createDiskChart(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        view.layer?.cornerRadius = 4
        
        let chartWidth = frame.width
        let chartHeight = frame.height
        let chartPadding: CGFloat = 8
        let centerLineY = chartHeight / 2
        
        // Center line
        let centerLine = NSView(frame: NSRect(x: chartPadding, y: centerLineY - 1, width: chartWidth - chartPadding * 2, height: 2))
        centerLine.wantsLayer = true
        centerLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.addSubview(centerLine)
        
        return view
    }
    
    // MARK: - Disk Data
    
    private func getDiskBytes() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        
        let masterPort = kIOMainPortDefault
        var iterator: io_iterator_t = 0
        
        // Try multiple storage driver classes for Apple Silicon compatibility
        let driverClasses = ["IOBlockStorageDriver", "IOBlockStorageDevice", "AppleAPFSDevice", "AppleAPFSContainer", "AppleSSD"]
        
        for driverClass in driverClasses {
            let matching = IOServiceMatching(driverClass)
            let result = IOServiceGetMatchingServices(masterPort, matching, &iterator)
            
            guard result == KERN_SUCCESS, iterator != 0 else { continue }
            
            defer { 
                IOObjectRelease(iterator) 
                iterator = 0
            }
            
            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let props = properties?.takeRetainedValue() as? [String: Any] else {
                    continue
                }
                
                // Check for Statistics dictionary
                if let statistics = props["Statistics"] as? [String: Any] {
                    // Keys are "Bytes (Read)" and "Bytes (Write)" on macOS
                    for readKey in ["Bytes (Read)", "BytesRead", "ReadBytes", "bytesRead"] {
                        if let num = statistics[readKey] as? NSNumber {
                            totalRead += num.uint64Value
                            break
                        } else if let val = statistics[readKey] as? UInt64 {
                            totalRead += val
                            break
                        }
                    }
                    
                    for writeKey in ["Bytes (Write)", "BytesWritten", "WriteBytes", "bytesWritten"] {
                        if let num = statistics[writeKey] as? NSNumber {
                            totalWrite += num.uint64Value
                            break
                        } else if let val = statistics[writeKey] as? UInt64 {
                            totalWrite += val
                            break
                        }
                    }
                }
                
                // Also check for direct properties (some drivers don't use Statistics)
                for readKey in ["Bytes Read", "TotalRead", "BytesRead", "Read Bytes"] {
                    if let num = props[readKey] as? NSNumber {
                        totalRead += num.uint64Value
                        break
                    } else if let val = props[readKey] as? UInt64 {
                        totalRead += val
                        break
                    }
                }
                
                for writeKey in ["Bytes Written", "TotalWrite", "BytesWritten", "Write Bytes"] {
                    if let num = props[writeKey] as? NSNumber {
                        totalWrite += num.uint64Value
                        break
                    } else if let val = props[writeKey] as? UInt64 {
                        totalWrite += val
                        break
                    }
                }
                
                // Check Device Characteristics for size info (not I/O but sometimes present)
                if let deviceChars = props["Device Characteristics"] as? [String: Any] {
                    for readKey in ["BytesRead", "ReadBytes"] {
                        if let num = deviceChars[readKey] as? NSNumber {
                            totalRead += num.uint64Value
                            break
                        }
                    }
                    for writeKey in ["BytesWritten", "WriteBytes"] {
                        if let num = deviceChars[writeKey] as? NSNumber {
                            totalWrite += num.uint64Value
                            break
                        }
                    }
                }
            }
            
            // If we found data, no need to try other classes
            if totalRead > 0 || totalWrite > 0 {
                break
            }
        }
        
        // Fallback: try iostat if IOKit returns nothing
        if totalRead == 0 && totalWrite == 0 {
            return getDiskBytesFromIostat()
        }
        
        return (totalRead, totalWrite)
    }
    
    private func getDiskBytesFromIostat() -> (read: UInt64, write: UInt64) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
        task.arguments = ["-d", "-c", "2"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse iostat output
                // Format: disk0  KB/t tps  MB/s
                // We need to find the main disk and parse values
                var totalReadMB: Double = 0
                var totalWriteMB: Double = 0
                
                for line in output.components(separatedBy: "\n") {
                    let parts = line.split(separator: " ").map { String($0) }
                    // Skip header lines
                    if parts.count >= 4, let _ = Double(parts[0].replacingOccurrences(of: "disk", with: "")) {
                        // This is a header line, skip
                        continue
                    }
                    // Look for lines with numbers
                    if parts.count >= 4 {
                        // Try to parse as MB/s values
                        // iostat -d shows: KB/t, tps, MB/s (read+write combined)
                        // For separate read/write, we'd need iostat -I
                        if let mbps = Double(parts.last ?? "0") {
                            // This is combined read+write in MB/s, estimate as 50/50
                            totalReadMB += mbps / 2.0
                            totalWriteMB += mbps / 2.0
                        }
                    }
                }
                
                // Convert MB/s to bytes (this is a rate, not total)
                // We can't get total bytes from iostat, so return 0
                // iostat gives rates, not cumulative bytes
            }
        } catch {
            // iostat failed
        }
        
        // iostat doesn't give us cumulative bytes, so this approach won't work
        // Return 0 and let the caller handle it
        return (0, 0)
    }
    
    private func getProcessesByDiskIO(limit: Int) -> [DiskProcessInfo] {
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
        
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 3, &procList, &size, nil, 0)
        
        var processes: [DiskProcessInfo] = []
        let now = Date()
        
        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            // Get process disk I/O
            let (readBytes, writeBytes) = getProcessDiskIO(pid: pid)
            
            var name: String
            if let path = getProcessPath(pid: pid) {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
                let comm = withUnsafePointer(to: proc.kp_proc.p_comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) { ptr in
                        String(cString: ptr)
                    }
                }
                name = comm
            }
            name = name.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.map { Character($0) }.map { String($0) }.joined()
            if name.isEmpty { name = "process" }
            
            let isApp = appPIDs.contains(pid)
            let uid = proc.kp_eproc.e_ucred.cr_uid
            let user = getProcessUser(uid: uid)
            let ppid = proc.kp_eproc.e_ppid
            
            // Calculate speeds
            var readSpeed: Double = 0
            var writeSpeed: Double = 0
            
            diskIOLock.lock()
            if let prev = prevDiskIO[pid] {
                let elapsed = now.timeIntervalSince(prev.time)
                if elapsed > 0 {
                    readSpeed = readBytes > prev.read ? Double(readBytes - prev.read) / elapsed : 0
                    writeSpeed = writeBytes > prev.write ? Double(writeBytes - prev.write) / elapsed : 0
                }
            }
            prevDiskIO[pid] = (readBytes, writeBytes, now)
            diskIOLock.unlock()
            
            // Include all processes regardless of activity
            processes.append(DiskProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                isApp: isApp,
                icon: appIcons[pid],
                user: user,
                ppid: ppid,
                readSpeed: readSpeed,
                writeSpeed: writeSpeed
            ))
        }
        
        // Sort by total activity
        processes.sort { ($0.readSpeed + $0.writeSpeed) > ($1.readSpeed + $1.writeSpeed) }
        return Array(processes.prefix(limit))
    }
    
    private func getProcessDiskIO(pid: Int32) -> (read: UInt64, write: UInt64) {
        // Use RUSAGE_INFO_V2 for disk I/O fields
        // In Swift, the rusage structures are tuples, and fields are accessed differently
        var rusage = rusage_info_current()
        let rusagePtr = withUnsafeMutablePointer(to: &rusage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { $0 }
        }
        let result = proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rusagePtr)
        guard result == 0 else { return (0, 0) }
        
        // ri_diskio_bytesread and ri_diskio_byteswritten should be available
        let bytesRead = rusage.ri_diskio_bytesread
        let bytesWritten = rusage.ri_diskio_byteswritten
        
        return (bytesRead, bytesWritten)
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
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_073_741_824 {
            return String(format: "%.1fG", bytesPerSec / 1_073_741_824)
        } else if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.1fK", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f", bytesPerSec)  // Raw bytes when < 1K
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension DiskModule: NSTableViewDataSource, NSTableViewDelegate {
    
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
                let typeIndicator: String
                if process.user == "root" || process.ppid == 1 {
                    typeIndicator = "🔧"
                } else {
                    typeIndicator = "👤"
                }
                let label = NSTextField(labelWithString: "\(typeIndicator) \(process.name)")
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
            
        case "write":
            let label = NSTextField(labelWithString: formatSpeed(process.writeSpeed))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 57, height: 16)
            cell.addSubview(label)
            
        case "read":
            let label = NSTextField(labelWithString: formatSpeed(process.readSpeed))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 57, height: 16)
            cell.addSubview(label)
            
        default:
            break
        }
        
        return cell
    }
}