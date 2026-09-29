// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CoreVideo

/// Memory process information.
struct MemoryProcessInfo {
    let pid: Int32
    let name: String
    let memoryUsage: UInt64
    let isApp: Bool
    let icon: NSImage?
    let user: String
    let threads: Int
    let ppid: Int32
}

/// Memory monitoring module.
final class MemoryModule: NSObject, StatusModule {

    var identifier: String { "memory" }
    var displayName: String { L("status.memory.displayName") }
    var shortName: String { "MEM" }

    private(set) var summaryText: String = "8.2"
    private(set) var summaryValue: String = "8.2"

    var refreshInterval: TimeInterval { 2.0 }

    private var processes: [MemoryProcessInfo] = []
    private var usedMemory: UInt64 = 0
    private var totalMemory: UInt64 = 0

    // Memory history for area chart (last 60 samples = 2 minutes)
    private var memoryHistory: [Double] = []
    private let maxHistoryCount = 60

    private weak var chartView: MemoryChartView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?

    func refreshSummary() {
        let (used, total) = getMemoryUsage()
        usedMemory = used
        totalMemory = total

        // Add to history
        let usedGB = Double(used) / 1_073_741_824.0
        memoryHistory.append(usedGB)
        if memoryHistory.count > maxHistoryCount {
            memoryHistory.removeFirst()
        }

        let value = String(format: "%.1f", usedGB)
        summaryText = value
        summaryValue = value

        processes = getProcessesByMemory(limit: 100)
    }

    func makeDetailView() -> NSView {
        // Calculate height
        let toolbarHeight = PopoverToolbar.height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 80
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 20
        let totalHeight = toolbarHeight + headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 400

        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))

        // Toolbar
        let toolbar = PopoverToolbar.create(title: displayName, width: viewWidth)
        toolbar.frame = NSRect(x: 0, y: totalHeight - toolbarHeight, width: viewWidth, height: toolbarHeight)
        container.addSubview(toolbar)

        // Header
        let headerView = NSTextField(labelWithString: "Memory Usage")
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - toolbarHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)

        // Memory usage area chart
        let chartY = totalHeight - toolbarHeight - headerHeight - chartHeight
        let chart = MemoryChartView(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chart.setTotalMemory(totalMemory)
        chart.setHistory(memoryHistory, usedMemory: usedMemory)
        chart.startAnimation()
        chartView = chart
        container.addSubview(chart)

        // Divider line
        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: viewWidth - 24, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)

        // Process list with columns: Name, PID, User, Threads, Memory
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

        let memColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("memory"))
        memColumn.width = 55
        memColumn.headerCell.title = "Memory"
        table.addTableColumn(memColumn)

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
        let (used, total) = getMemoryUsage()
        usedMemory = used
        totalMemory = total

        // Add to history
        let usedGB = Double(used) / 1_073_741_824.0
        memoryHistory.append(usedGB)
        if memoryHistory.count > maxHistoryCount {
            memoryHistory.removeFirst()
        }

        processes = getProcessesByMemory(limit: 100)

        chartView?.setHistory(memoryHistory, usedMemory: usedMemory)
        tableView?.reloadData()
    }

    // MARK: - Memory Data

    private func getMemoryUsage() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0

        // Get total memory
        var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
        var size = MemoryLayout<UInt64>.size
        sysctl(&mib, 2, &total, &size, nil, 0)

        // Get detailed memory statistics
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            // Use the same formula as Stats/Activity Monitor
            // used = active + inactive + speculative + wired + compressed - purgeable - external
            let pageSize = UInt64(vm_kernel_page_size)
            let active = UInt64(vmStats.active_count) * pageSize
            let inactive = UInt64(vmStats.inactive_count) * pageSize
            let speculative = UInt64(vmStats.speculative_count) * pageSize
            let wired = UInt64(vmStats.wire_count) * pageSize
            let compressed = UInt64(vmStats.compressor_page_count) * pageSize
            let purgeable = UInt64(vmStats.purgeable_count) * pageSize
            let external = UInt64(vmStats.external_page_count) * pageSize

            used = active + inactive + speculative + wired + compressed - purgeable - external
        }

        return (used, total)
    }

    private func getProcessesByMemory(limit: Int) -> [MemoryProcessInfo] {
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

        var processes: [MemoryProcessInfo] = []

        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }

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
            let threads = getProcessThreads(pid: pid)
            let memory = getProcessMemoryUsage(pid: pid)
            let ppid = proc.kp_eproc.e_ppid

            processes.append(MemoryProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                memoryUsage: memory,
                isApp: isApp,
                icon: appIcons[pid],
                user: user,
                threads: threads,
                ppid: ppid
            ))
        }

        // Sort by memory usage
        processes.sort { $0.memoryUsage > $1.memoryUsage }
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

    private func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        let mb = Double(bytes) / 1_048_576.0

        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 100 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension MemoryModule: NSTableViewDataSource, NSTableViewDelegate {

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

        case "threads":
            let label = NSTextField(labelWithString: "\(process.threads)")
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 27, height: 16)
            cell.addSubview(label)

        case "memory":
            let label = NSTextField(labelWithString: formatMemory(process.memoryUsage))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 4, y: 2, width: 47, height: 16)
            cell.addSubview(label)

        default:
            break
        }

        return cell
    }
}

// MARK: - Memory Chart View with smooth curves

/// Memory chart view with smooth Bezier curves
final class MemoryChartView: NSView {
    private var history: [Double] = []
    private var totalMemory: UInt64 = 0
    private var usedMemory: UInt64 = 0
    private let maxHistoryCount = 60
    
    private let chartColor = NSColor(red: 0.75, green: 0.55, blue: 0.65, alpha: 1.0)
    
    // Animation
    private var displayLink: CVDisplayLink?
    private var lastUpdateTime: Date = Date()
    private let sampleInterval: TimeInterval = 2.0
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 4
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopAnimation()
    }
    
    func startAnimation() {
        guard displayLink == nil else { return }
        
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let link = link else { return }
        displayLink = link
        
        // Use weak reference to avoid retain cycle
        let weakSelf = Unmanaged.passUnretained(self).toOpaque()
        
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<MemoryChartView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                view.needsDisplay = true
            }
            return kCVReturnSuccess
        }, weakSelf)
        
        CVDisplayLinkStart(link)
        lastUpdateTime = Date()
    }
    
    func stopAnimation() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
    }
    
    func setTotalMemory(_ total: UInt64) {
        self.totalMemory = total
    }
    
    func setHistory(_ history: [Double], usedMemory: UInt64) {
        self.history = history
        self.usedMemory = usedMemory
        lastUpdateTime = Date()
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard history.count > 1 else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(true)
        
        let totalGB = Double(totalMemory) / 1_073_741_824.0
        let usedGB = Double(usedMemory) / 1_073_741_824.0
        
        let padding: CGFloat = 8
        let labelHeight: CGFloat = 24
        let height = bounds.height - labelHeight - padding
        let width = bounds.width - padding * 2
        let xRatio = width / CGFloat(maxHistoryCount - 1)
        
        // Calculate smooth scroll offset
        let elapsed = Date().timeIntervalSince(lastUpdateTime)
        let progress = min(elapsed / sampleInterval, 1.0)
        let xOffset = progress * xRatio  // Smoothly scroll left
        
        // Build line points - newest on right edge, grows from right to left
        var linePoints: [CGPoint] = []
        for (i, value) in history.enumerated() {
            // i=0 is oldest, i=count-1 is newest
            // Newest should be at right edge (bounds.width - padding)
            // Oldest moves left as more data comes in
            let x = bounds.width - padding - CGFloat(history.count - 1 - i) * xRatio - xOffset
            let y = padding + min(value / totalGB, 1.0) * height
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
        
        // Draw filled area with gradient
        let areaPath = linePath.copy() as! NSBezierPath
        areaPath.line(to: CGPoint(x: linePoints[linePoints.count - 1].x, y: padding))
        areaPath.line(to: CGPoint(x: linePoints[0].x, y: padding))
        areaPath.close()
        
        let gradient = NSGradient(colors: [
            chartColor.withAlphaComponent(0.2),
            chartColor.withAlphaComponent(0.4)
        ])
        gradient?.draw(in: areaPath, angle: 90)
        
        // Draw line
        linePath.lineWidth = 1.5
        chartColor.withAlphaComponent(0.9).setStroke()
        linePath.stroke()
        
        // Draw labels
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        
        let usageLabel = NSAttributedString(string: String(format: "%.1f GB", usedGB), attributes: valueAttrs)
        let totalLabel = NSAttributedString(string: String(format: "/ %.0f GB", totalGB), attributes: totalAttrs)
        
        let usageSize = usageLabel.size()
        let totalSize = totalLabel.size()
        
        usageLabel.draw(at: CGPoint(x: bounds.width - padding - usageSize.width, y: bounds.height - padding - usageSize.height))
        totalLabel.draw(at: CGPoint(x: bounds.width - padding - totalSize.width, y: bounds.height - padding - usageSize.height - totalSize.height - 2))
    }
}
