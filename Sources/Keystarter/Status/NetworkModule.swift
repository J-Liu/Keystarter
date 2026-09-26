// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Network process information.
struct NetworkProcessInfo {
    let pid: Int32
    let name: String
    let isApp: Bool
    let icon: NSImage?
    let user: String
    let ppid: Int32
    var downloadSpeed: Double
    var uploadSpeed: Double
}

/// Network monitoring module.
final class NetworkModule: NSObject, StatusModule {
    
    var identifier: String { "network" }
    var displayName: String { L("status.network.displayName") }
    var shortName: String { "NET" }
    
    private(set) var summaryText: String = "↓-- ↑--"
    private(set) var summaryValue: String = "--"
    
    // Public speeds for status bar
    var downloadSpeedText: String { formatSpeed(downloadSpeed) }
    var uploadSpeedText: String { formatSpeed(uploadSpeed) }
    
    var refreshInterval: TimeInterval { 2.0 }
    
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var previousTime: Date = Date()
    
    // History for charts
    private var downloadHistory: [Double] = []
    private var uploadHistory: [Double] = []
    private let maxHistoryCount = 60
    
    private var processes: [NetworkProcessInfo] = []
    private var downloadSpeed: Double = 0
    private var uploadSpeed: Double = 0
    
    // Per-process tracking
    private var prevNetIO: [Int32: (in: UInt64, out: UInt64, time: Date)] = [:]
    private var netIOLock = NSLock()
    
    private weak var chartView: NSView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?
    
    func refreshSummary() {
        // Only update from summary if detail view is not open
        guard detailTimer == nil else { return }
        updateNetworkData()
    }
    
    private func updateNetworkData() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let (bytesIn, bytesOut) = self.getNetworkBytes()
            let now = Date()
            let elapsed = now.timeIntervalSince(self.previousTime)
            
            var newDownSpeed: Double = 0
            var newUpSpeed: Double = 0
            
            if elapsed >= 0.5 {
                let bytesInDelta = bytesIn > self.previousBytesIn ? bytesIn - self.previousBytesIn : 0
                let bytesOutDelta = bytesOut > self.previousBytesOut ? bytesOut - self.previousBytesOut : 0
                
                newDownSpeed = Double(bytesInDelta) / elapsed
                newUpSpeed = Double(bytesOutDelta) / elapsed
            }
            
            self.previousBytesIn = bytesIn
            self.previousBytesOut = bytesOut
            self.previousTime = now
            
            let newProcesses = self.getProcessesByNetwork(limit: 100)
            
            DispatchQueue.main.async {
                // Update history arrays
                self.downloadHistory.append(newDownSpeed)
                self.uploadHistory.append(newUpSpeed)
                if self.downloadHistory.count > self.maxHistoryCount { self.downloadHistory.removeFirst() }
                if self.uploadHistory.count > self.maxHistoryCount { self.uploadHistory.removeFirst() }
                
                self.downloadSpeed = newDownSpeed
                self.uploadSpeed = newUpSpeed
                self.processes = newProcesses
                
                // Only update chart and notify if detail view is open
                if self.detailTimer != nil {
                    self.updateChart()
                    self.tableView?.reloadData()
                    NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "network"])
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
        
        // Network chart (mirrored download/upload)
        let chartY = totalHeight - headerHeight - chartHeight
        let chart = createNetworkChart(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chartView = chart
        container.addSubview(chart)
        
        // Divider
        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: viewWidth - 24, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)
        
        // Process list: Name, PID, User, Upload Speed, Download Speed
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
        
        let uploadColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("upload"))
        uploadColumn.width = 65
        uploadColumn.headerCell.title = "Upload"
        table.addTableColumn(uploadColumn)
        
        let downloadColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("download"))
        downloadColumn.width = 65
        downloadColumn.headerCell.title = "Download"
        table.addTableColumn(downloadColumn)
        
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
        updateNetworkData()
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
        let maxDown = downloadHistory.max() ?? 1
        let maxUp = uploadHistory.max() ?? 1
        let maxVal = max(maxDown, maxUp, 1)
        
        // Draw center line
        let centerLine = NSView(frame: NSRect(x: chartPadding, y: centerLineY - 1, width: drawWidth, height: 2))
        centerLine.wantsLayer = true
        centerLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        chart.addSubview(centerLine)
        
        // Calculate points
        let downPoints: [CGPoint] = downloadHistory.enumerated().map { index, value in
            let x = chartWidth - chartPadding - CGFloat(downloadHistory.count - 1 - index) * stepX
            let y = centerLineY + min(value / maxVal, 1.0) * halfHeight
            return CGPoint(x: x, y: y)
        }
        
        let upPoints: [CGPoint] = uploadHistory.enumerated().map { index, value in
            let x = chartWidth - chartPadding - CGFloat(uploadHistory.count - 1 - index) * stepX
            let y = centerLineY - min(value / maxVal, 1.0) * halfHeight
            return CGPoint(x: x, y: y)
        }
        
        // Draw download chart (top half, above center line) - light purple
        if downPoints.count > 1 {
            let downAreaPath = CGMutablePath()
            downAreaPath.move(to: CGPoint(x: downPoints[0].x, y: centerLineY))
            downAreaPath.addLine(to: downPoints[0])
            
            // Build smooth curve directly
            for i in 1..<downPoints.count {
                let prev = downPoints[i - 1]
                let curr = downPoints[i]
                let midX = (prev.x + curr.x) / 2
                let midY = (prev.y + curr.y) / 2
                downAreaPath.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: prev.y))
                downAreaPath.addQuadCurve(to: curr, control: CGPoint(x: midX, y: midY))
            }
            
            downAreaPath.addLine(to: CGPoint(x: downPoints.last!.x, y: centerLineY))
            downAreaPath.closeSubpath()
            
            let downLayer = CAShapeLayer()
            downLayer.path = downAreaPath
            downLayer.fillColor = NSColor(red: 0.6, green: 0.4, blue: 0.7, alpha: 0.2).cgColor
            chart.layer?.addSublayer(downLayer)
            
            let downLinePath = createSmoothPath(points: downPoints)
            let downLineLayer = CAShapeLayer()
            downLineLayer.path = downLinePath
            downLineLayer.fillColor = nil
            downLineLayer.strokeColor = NSColor(red: 0.6, green: 0.4, blue: 0.7, alpha: 0.8).cgColor
            downLineLayer.lineWidth = 1.5
            downLineLayer.lineCap = .round
            downLineLayer.lineJoin = .round
            chart.layer?.addSublayer(downLineLayer)
        }
        
        // Draw upload chart (bottom half, below center line) - light red
        if upPoints.count > 1 {
            let upAreaPath = CGMutablePath()
            upAreaPath.move(to: CGPoint(x: upPoints[0].x, y: centerLineY))
            upAreaPath.addLine(to: upPoints[0])
            
            // Build smooth curve directly
            for i in 1..<upPoints.count {
                let prev = upPoints[i - 1]
                let curr = upPoints[i]
                let midX = (prev.x + curr.x) / 2
                let midY = (prev.y + curr.y) / 2
                upAreaPath.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: prev.y))
                upAreaPath.addQuadCurve(to: curr, control: CGPoint(x: midX, y: midY))
            }
            
            upAreaPath.addLine(to: CGPoint(x: upPoints.last!.x, y: centerLineY))
            upAreaPath.closeSubpath()
            
            let upLayer = CAShapeLayer()
            upLayer.path = upAreaPath
            upLayer.fillColor = NSColor(red: 0.75, green: 0.35, blue: 0.35, alpha: 0.2).cgColor
            chart.layer?.addSublayer(upLayer)
            
            let upLinePath = createSmoothPath(points: upPoints)
            let upLineLayer = CAShapeLayer()
            upLineLayer.path = upLinePath
            upLineLayer.fillColor = nil
            upLineLayer.strokeColor = NSColor(red: 0.75, green: 0.35, blue: 0.35, alpha: 0.8).cgColor
            upLineLayer.lineWidth = 1.5
            upLineLayer.lineCap = .round
            upLineLayer.lineJoin = .round
            chart.layer?.addSublayer(upLineLayer)
        }
        
        // Labels
        let downLabel = NSTextField(labelWithString: "↓ \(formatSpeed(downloadSpeed))")
        downLabel.font = NSFont.systemFont(ofSize: 10)
        downLabel.textColor = .secondaryLabelColor
        downLabel.frame = NSRect(x: chartWidth - 80, y: chartHeight - 16, width: 70, height: 12)
        chart.addSubview(downLabel)
        
        let upLabel = NSTextField(labelWithString: "↑ \(formatSpeed(uploadSpeed))")
        upLabel.font = NSFont.systemFont(ofSize: 10)
        upLabel.textColor = .secondaryLabelColor
        upLabel.frame = NSRect(x: chartWidth - 80, y: 4, width: 70, height: 12)
        chart.addSubview(upLabel)
    }
    
    private func createSmoothPath(points: [CGPoint]) -> CGMutablePath {
        let path = CGMutablePath()
        guard points.count > 1 else { return path }
        
        path.move(to: points[0])
        
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            
            let midX = (prev.x + curr.x) / 2
            let midY = (prev.y + curr.y) / 2
            
            path.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: prev.x, y: prev.y))
            path.addQuadCurve(to: curr, control: CGPoint(x: midX, y: midY))
        }
        
        return path
    }
    
    private func createNetworkChart(frame: NSRect) -> NSView {
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
    
    // MARK: - Network Data
    
    private func getNetworkBytes() -> (in: UInt64, out: UInt64) {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }
        
        var ptr = firstAddr
        while true {
            let addr = ptr.pointee
            
            if let name = addr.ifa_name {
                let ifaName = String(cString: name)
                if ifaName.hasPrefix("en") || ifaName.hasPrefix("awdl") || ifaName.hasPrefix("llw") {
                    if let data = addr.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        bytesIn += UInt64(networkData.ifi_ibytes)
                        bytesOut += UInt64(networkData.ifi_obytes)
                    }
                }
            }
            
            guard let next = addr.ifa_next else { break }
            ptr = next
        }
        
        freeifaddrs(ifaddr)
        return (bytesIn, bytesOut)
    }
    
    private func getProcessesByNetwork(limit: Int) -> [NetworkProcessInfo] {
        // Use nettop for per-process network stats
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        var nettopData: [(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64)] = []
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                nettopData = parseNettopOutput(output)
            }
        } catch {
            // nettop failed
        }
        
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
        
        var processes: [NetworkProcessInfo] = []
        let now = Date()
        
        for (pid, name, bytesIn, bytesOut) in nettopData {
            // Get additional info
            let uid = getProcessUID(pid: pid)
            let user = getProcessUser(uid: uid)
            let ppid = getProcessPPID(pid: pid)
            let isApp = appPIDs.contains(pid)
            
            // Calculate speeds from deltas
            var downloadSpeed: Double = 0
            var uploadSpeed: Double = 0
            
            netIOLock.lock()
            if let prev = prevNetIO[pid] {
                let elapsed = now.timeIntervalSince(prev.time)
                if elapsed > 0 {
                    downloadSpeed = bytesIn > prev.in ? Double(bytesIn - prev.in) / elapsed : 0
                    uploadSpeed = bytesOut > prev.out ? Double(bytesOut - prev.out) / elapsed : 0
                }
            }
            prevNetIO[pid] = (bytesIn, bytesOut, now)
            netIOLock.unlock()
            
            // Include all processes regardless of activity
            processes.append(NetworkProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                isApp: isApp,
                icon: appIcons[pid],
                user: user,
                ppid: ppid,
                downloadSpeed: downloadSpeed,
                uploadSpeed: uploadSpeed
            ))
        }
        
        processes.sort { ($0.downloadSpeed + $0.uploadSpeed) > ($1.downloadSpeed + $1.uploadSpeed) }
        return Array(processes.prefix(limit))
    }
    
    private func parseNettopOutput(_ output: String) -> [(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64)] {
        var results: [(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64)] = []
        var seenPids = Set<Int32>()
        
        for line in output.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { continue }
            
            // Parse process name (format: "AppName.123" where 123 is PID)
            let processInfo = parts[0]
            guard let dotIndex = processInfo.lastIndex(of: ".") else { continue }
            
            let pidString = String(processInfo[processInfo.index(after: dotIndex)...])
            guard let pid = Int32(pidString) else { continue }
            
            if seenPids.contains(pid) { continue }
            seenPids.insert(pid)
            
            let name = String(processInfo[..<dotIndex])
            let bytesIn = UInt64(parts[1]) ?? 0
            let bytesOut = UInt64(parts[2]) ?? 0
            
            results.append((pid, name, bytesIn, bytesOut))
        }
        
        return results
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
    
    private func getProcessPPID(pid: Int32) -> Int32 {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &proc, &size, nil, 0) == 0 {
            return proc.kp_eproc.e_ppid
        }
        return 0
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

extension NetworkModule: NSTableViewDataSource, NSTableViewDelegate {
    
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
            
        case "upload":
            let label = NSTextField(labelWithString: formatSpeed(process.uploadSpeed))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 57, height: 16)
            cell.addSubview(label)
            
        case "download":
            let label = NSTextField(labelWithString: formatSpeed(process.downloadSpeed))
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