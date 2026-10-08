// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CoreVideo
import SystemConfiguration

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
    
    var refreshInterval: TimeInterval { 1.0 }
    
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
    
    private weak var chartView: NetworkChartView?
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
                    self.chartView?.setDownloadHistory(self.downloadHistory, uploadHistory: self.uploadHistory)
                    self.chartView?.needsDisplay = true
                    self.tableView?.reloadData()
                    NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "network"])
                }
            }
        }
    }
    
    func makeDetailView() -> NSView {
        let toolbarHeight = PopoverToolbar.height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 100
        let ipInfoHeight: CGFloat = 63  // IP info section (4 rows)
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 20
        let totalHeight = toolbarHeight + headerHeight + chartHeight + ipInfoHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 450

        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))

        // Toolbar
        let toolbar = PopoverToolbar.create(title: displayName, width: viewWidth)
        toolbar.frame = NSRect(x: 0, y: totalHeight - toolbarHeight, width: viewWidth, height: toolbarHeight)
        container.addSubview(toolbar)

        // Header
        let headerView = NSTextField(labelWithString: "Network I/O")
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - toolbarHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)

        // Network chart (mirrored download/upload)
        let chartY = totalHeight - toolbarHeight - headerHeight - chartHeight
        let chart = NetworkChartView(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        // Set existing history immediately
        chart.setDownloadHistory(downloadHistory, uploadHistory: uploadHistory)
        chart.startAnimation()
        chartView = chart
        container.addSubview(chart)

        // IP Info Section (between chart and divider)
        let ipY = chartY - ipInfoHeight
        let ipContainer = NSView(frame: NSRect(x: 12, y: ipY, width: viewWidth - 24, height: ipInfoHeight))
        ipContainer.wantsLayer = true
        ipContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        ipContainer.layer?.cornerRadius = 4

        // Get local IPs
        let (localIPv4, localIPv6) = getLocalIPAddresses()
        let macAddress = getMACAddress()

        // Local IP label
        let localLabel = NSTextField(labelWithString: "Local IP:")
        localLabel.font = .systemFont(ofSize: 11, weight: .medium)
        localLabel.textColor = .labelColor
        localLabel.frame = NSRect(x: 8, y: ipInfoHeight - 15, width: 70, height: 14)
        ipContainer.addSubview(localLabel)

        let localValue = NSTextField(labelWithString: localIPv4 ?? "N/A")
        localValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        localValue.frame = NSRect(x: 82, y: ipInfoHeight - 15, width: viewWidth - 110, height: 14)
        localValue.lineBreakMode = .byTruncatingMiddle
        ipContainer.addSubview(localValue)

        // MAC address label
        let macLabel = NSTextField(labelWithString: "MAC:")
        macLabel.font = .systemFont(ofSize: 11, weight: .medium)
        macLabel.textColor = .labelColor
        macLabel.frame = NSRect(x: 8, y: ipInfoHeight - 30, width: 70, height: 14)
        ipContainer.addSubview(macLabel)

        let macValue = NSTextField(labelWithString: macAddress ?? "N/A")
        macValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        macValue.frame = NSRect(x: 82, y: ipInfoHeight - 30, width: viewWidth - 110, height: 14)
        macValue.lineBreakMode = .byTruncatingMiddle
        ipContainer.addSubview(macValue)

        // Public IP label
        let publicLabel = NSTextField(labelWithString: "Public IP:")
        publicLabel.font = .systemFont(ofSize: 11, weight: .medium)
        publicLabel.textColor = .labelColor
        publicLabel.frame = NSRect(x: 8, y: ipInfoHeight - 45, width: 70, height: 14)
        ipContainer.addSubview(publicLabel)

        let publicValue = NSTextField(labelWithString: "Loading...")
        publicValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        publicValue.frame = NSRect(x: 82, y: ipInfoHeight - 45, width: viewWidth - 110, height: 14)
        publicValue.lineBreakMode = .byTruncatingMiddle
        ipContainer.addSubview(publicValue)

        // IPv6 label
        let ipv6Label = NSTextField(labelWithString: "IPv6:")
        ipv6Label.font = .systemFont(ofSize: 11, weight: .medium)
        ipv6Label.textColor = .labelColor
        ipv6Label.frame = NSRect(x: 8, y: ipInfoHeight - 60, width: 70, height: 14)
        ipContainer.addSubview(ipv6Label)

        let ipv6Value = NSTextField(labelWithString: localIPv6 ?? "N/A")
        ipv6Value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        ipv6Value.frame = NSRect(x: 82, y: ipInfoHeight - 60, width: viewWidth - 110, height: 14)
        ipv6Value.lineBreakMode = .byTruncatingMiddle
        ipContainer.addSubview(ipv6Value)

        container.addSubview(ipContainer)

        // Async fetch public IP
        getPublicIP { [weak publicValue] ip in
            publicValue?.stringValue = ip ?? "N/A"
        }

        // Divider
        let dividerY = ipY - dividerHeight + 4
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

        // Refresh immediately on open
        refreshDetail()
        startDetailTimer()

        return container
    }
    
    private func startDetailTimer() {
        detailTimer?.invalidate()
        detailTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshDetail()
        }
    }
    
    private func refreshDetail() {
        updateNetworkData()
    }
    
    // MARK: - Network Data

    /// Get local IP addresses (IPv4 and IPv6)
    func getLocalIPAddresses() -> (ipv4: String?, ipv6: String?) {
        var ipv4: String?
        var ipv6: String?

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (nil, nil)
        }

        var ptr = firstAddr
        while true {
            let addr = ptr.pointee

            if let name = addr.ifa_name {
                let ifaName = String(cString: name)
                // Skip loopback and down interfaces
                let flags = addr.ifa_flags
                if (flags & UInt32(IFF_LOOPBACK)) != 0 || (flags & UInt32(IFF_UP)) == 0 {
                    guard let next = addr.ifa_next else { break }
                    ptr = next
                    continue
                }

                if let sa = addr.ifa_addr {
                    let family = sa.pointee.sa_family

                    if family == UInt8(AF_INET) {
                        // IPv4
                        var addrStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var addrIn = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        inet_ntop(AF_INET, &addrIn.sin_addr, &addrStr, socklen_t(INET_ADDRSTRLEN))
                        let ip = String(cString: addrStr)
                        if ipv4 == nil && ifaName.hasPrefix("en") {
                            ipv4 = ip
                        }
                    } else if family == UInt8(AF_INET6) {
                        // IPv6
                        var addrStr = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        var addrIn6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                        inet_ntop(AF_INET6, &addrIn6.sin6_addr, &addrStr, socklen_t(INET6_ADDRSTRLEN))
                        let ip = String(cString: addrStr)
                        // Accept any non-link-local IPv6 on en interfaces
                        if ipv6 == nil && ifaName.hasPrefix("en") && !ip.hasPrefix("fe80::") {
                            ipv6 = ip
                        } else if ipv6 == nil && (ifaName.hasPrefix("awdl") || ifaName.hasPrefix("llw")) {
                            // Also check awdl/llw interfaces as fallback
                            ipv6 = ip
                        }
                    }
                }
            }

            guard let next = addr.ifa_next else { break }
            ptr = next
        }

        freeifaddrs(ifaddr)
        return (ipv4, ipv6)
    }

    /// Get MAC address of primary network interface using SystemConfiguration
    func getMACAddress() -> String? {
        let primaryInterface: String? = {
            guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
                  let name = global["PrimaryInterface"] as? String else {
                return nil
            }
            return name
        }()

        let targetInterface = primaryInterface ?? "en0"

        for interface in SCNetworkInterfaceCopyAll() as NSArray {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface as! SCNetworkInterface),
                  bsdName as String == targetInterface else { continue }

            if let address = SCNetworkInterfaceGetHardwareAddressString(interface as! SCNetworkInterface) {
                return address as String
            }
        }

        return nil
    }

    /// Get public IP address (async)
    func getPublicIP(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Try multiple services for reliability
            let services = [
                "https://api.ipify.org",
                "https://icanhazip.com",
                "https://ifconfig.me/ip"
            ]

            for service in services {
                guard let url = URL(string: service) else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 3.0
                request.setValue("Keystarter/1.0", forHTTPHeaderField: "User-Agent")

                do {
                    let data = try Data(contentsOf: url, options: [])
                    if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        // Validate IP format
                        if ip.contains(".") || ip.contains(":") {
                            DispatchQueue.main.async {
                                completion(ip)
                            }
                            return
                        }
                    }
                } catch {
                    continue
                }
            }

            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }

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

// MARK: - Network Chart View (Stats-style with two internal charts)

/// Single line chart view with smooth Bezier curves and animated scrolling
private final class NetworkLineChartView: NSView {
    private var points: [Double?] = []
    private var color: NSColor
    private var flipY: Bool = false
    private var lastUpdateTime: Date = Date()
    private var displayLink: CVDisplayLink?
    private let sampleInterval: TimeInterval = 2.0  // Match the 2-second sampling rate
    
    init(frame: NSRect, num: Int, color: NSColor) {
        self.points = Array(repeating: nil, count: max(num, 2))
        self.color = color
        super.init(frame: frame)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopAnimation()
    }
    
    func addValue(_ value: Double) {
        // Shift all points left and add new value at the end
        for i in 0..<(points.count - 1) {
            points[i] = points[i + 1]
        }
        points[points.count - 1] = value
        lastUpdateTime = Date()
    }
    
    func reinit(_ num: Int) {
        points = Array(repeating: nil, count: max(num, 2))
        lastUpdateTime = Date()
        needsDisplay = true
    }
    
    func setFlipY(_ value: Bool) {
        flipY = value
    }
    
    func startAnimation() {
        guard displayLink == nil else { return }
        
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<NetworkLineChartView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                view.needsDisplay = true
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        
        CVDisplayLinkStart(link)
        displayLink = link
    }
    
    func stopAnimation() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(true)
        
        // Find max value
        var maxValue: Double = 0
        for opt in points {
            if let p = opt, p > maxValue { maxValue = p }
        }
        if maxValue == 0 { maxValue = 1 }
        
        let offset: CGFloat = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        let height = self.frame.height - offset
        let xRatio = self.frame.width / CGFloat(points.count - 1)
        let zero = flipY ? 0 : self.frame.height
        
        // Calculate animation progress for smooth scrolling
        let elapsed = Date().timeIntervalSince(lastUpdateTime)
        let progress = min(elapsed / sampleInterval, 1.0)
        let xOffset = progress * xRatio  // Smoothly scroll left
        
        // Build line points with animation offset
        var linePoints: [CGPoint] = []
        for (i, v) in points.enumerated() {
            guard let v else { continue }
            
            var y = (v / maxValue) * height
            if !flipY {
                y = height - y
            }
            
            // Apply smooth scroll offset: points move left continuously
            let x = CGFloat(i) * xRatio - xOffset
            linePoints.append(CGPoint(x: x, y: y))
        }
        
        guard linePoints.count > 1 else { return }
        
        // Draw smooth curve using quadratic Bezier
        let linePath = NSBezierPath()
        linePath.move(to: linePoints[0])
        
        for i in 1..<linePoints.count {
            let prev = linePoints[i - 1]
            let curr = linePoints[i]
            
            // Control point at midpoint creates smooth curve
            let midX = (prev.x + curr.x) / 2
            linePath.curve(to: curr, controlPoint1: CGPoint(x: midX, y: prev.y), controlPoint2: CGPoint(x: midX, y: curr.y))
        }
        
        linePath.lineWidth = offset
        color.setStroke()
        linePath.stroke()
        
        // Draw filled area with gradient
        let areaPath = linePath.copy() as! NSBezierPath
        areaPath.line(to: CGPoint(x: linePoints[linePoints.count - 1].x, y: zero))
        areaPath.line(to: CGPoint(x: linePoints[0].x, y: zero))
        areaPath.close()
        
        let gradient = NSGradient(colors: [
            color.withAlphaComponent(0.3),
            color.withAlphaComponent(0.5)
        ])
        gradient?.draw(in: areaPath, angle: flipY ? 0 : 90)
    }
}

/// Network chart view with two internal charts - upload on top, download on bottom
final class NetworkChartView: NSView {
    private let uploadChart: NetworkLineChartView
    private let downloadChart: NetworkLineChartView
    
    private let downloadColor = NSColor(red: 0.6, green: 0.4, blue: 0.7, alpha: 1.0)  // Purple for download
    private let uploadColor = NSColor(red: 0.75, green: 0.35, blue: 0.35, alpha: 1.0)  // Red for upload
    private let maxHistoryCount = 60
    
    private var currentUploadSpeed: Double = 0
    private var currentDownloadSpeed: Double = 0
    
    override init(frame frameRect: NSRect) {
        let safeHeight = max(frameRect.height, 2)
        let topFrame = NSRect(x: 0, y: safeHeight / 2, width: frameRect.width, height: safeHeight / 2)
        let bottomFrame = NSRect(x: 0, y: 0, width: frameRect.width, height: safeHeight / 2)
        
        // Upload chart is on top (topFrame), download chart is on bottom (bottomFrame)
        self.uploadChart = NetworkLineChartView(frame: topFrame, num: maxHistoryCount, color: uploadColor)
        self.downloadChart = NetworkLineChartView(frame: bottomFrame, num: maxHistoryCount, color: downloadColor)
        
        super.init(frame: frameRect)
        
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 4
        
        // Upload chart grows down from top (flipY = true)
        self.uploadChart.setFlipY(true)
        // Download chart grows up from bottom (flipY = false)
        self.downloadChart.setFlipY(false)
        
        addSubview(self.uploadChart)
        addSubview(self.downloadChart)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopAnimation()
    }
    
    func startAnimation() {
        uploadChart.startAnimation()
        downloadChart.startAnimation()
    }
    
    func stopAnimation() {
        uploadChart.stopAnimation()
        downloadChart.stopAnimation()
    }
    
    func setDownloadHistory(_ download: [Double], uploadHistory upload: [Double]) {
        // Store current speeds for display
        currentDownloadSpeed = download.last ?? 0
        currentUploadSpeed = upload.last ?? 0
        
        // Clear and reinitialize charts
        self.uploadChart.reinit(maxHistoryCount)
        self.downloadChart.reinit(maxHistoryCount)
        
        // Add all values
        for i in 0..<min(download.count, upload.count) {
            self.downloadChart.addValue(download[i])
            self.uploadChart.addValue(upload[i])
        }
        
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw speed labels
        let padding: CGFloat = 6
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        
        // Upload label (top right)
        let uploadLabel = "↑ \(formatSpeed(currentUploadSpeed))"
        let uploadAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: uploadColor
        ]
        let uploadStr = NSAttributedString(string: uploadLabel, attributes: uploadAttrs)
        let uploadSize = uploadStr.size()
        uploadStr.draw(at: CGPoint(x: bounds.width - padding - uploadSize.width, y: bounds.height - padding - uploadSize.height))
        
        // Download label (bottom right)
        let downloadLabel = "↓ \(formatSpeed(currentDownloadSpeed))"
        let downloadAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: downloadColor
        ]
        let downloadStr = NSAttributedString(string: downloadLabel, attributes: downloadAttrs)
        let downloadSize = downloadStr.size()
        downloadStr.draw(at: CGPoint(x: bounds.width - padding - downloadSize.width, y: padding))
        
        // Draw center separator line
        let centerLineY = bounds.height / 2
        let linePath = NSBezierPath()
        linePath.move(to: CGPoint(x: padding, y: centerLineY))
        linePath.line(to: CGPoint(x: bounds.width - padding, y: centerLineY))
        linePath.lineWidth = 0.5
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        linePath.stroke()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        
        let safeHeight = max(newSize.height, 2)
        let halfHeight = safeHeight / 2
        let topFrame = NSRect(x: 0, y: halfHeight, width: newSize.width, height: halfHeight)
        let bottomFrame = NSRect(x: 0, y: 0, width: newSize.width, height: halfHeight)
        
        uploadChart.frame = topFrame
        downloadChart.frame = bottomFrame
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_073_741_824 {
            return String(format: "%.1fG", bytesPerSec / 1_073_741_824)
        } else if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.1fK", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f", bytesPerSec)
        }
    }
}