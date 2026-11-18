// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import IOKit
import CoreServices
import CoreVideo

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

    private var previousReadBytes: Int64 = 0
    private var previousWriteBytes: Int64 = 0
    private var previousTime: Date = Date()

    // Per-process disk I/O tracking
    private var prevDiskIO: [Int32: (read: UInt64, write: UInt64, time: Date)] = [:]
    private var diskIOLock = NSLock()

    // History for charts
    private var readHistory: [Double] = []
    private var writeHistory: [Double] = []
    private let maxHistoryCount = 60

    private var processes: [DiskProcessInfo] = []
    private let processQueue = DispatchQueue(label: "com.keystarter.disk.processes", qos: .userInitiated)
    private var isRefreshPaused: Bool = false
    private var readSpeed: Double = 0
    private var writeSpeed: Double = 0

    private weak var chartView: DiskChartView?
    private weak var tableView: NSTableView?
    private var lastProcessDataTime: Date?

    func refreshSummary() {
        // Fetch process data periodically (every 5 seconds) to keep it fresh
        let now = Date()
        let shouldFetchProcesses: Bool
        if let lastTime = lastProcessDataTime {
            shouldFetchProcesses = now.timeIntervalSince(lastTime) >= 5
        } else {
            shouldFetchProcesses = true  // First time
        }
        if shouldFetchProcesses {
            lastProcessDataTime = now
        }
        updateDiskData(includeProcesses: shouldFetchProcesses)
    }

    private func updateDiskData(includeProcesses: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let (readBytes, writeBytes) = self.getDiskBytesFromDASession()
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

            // Only fetch per-process data when explicitly requested
            var newProcesses: [DiskProcessInfo] = []
            if includeProcesses {
                newProcesses = self.getProcessesByDiskIO(limit: 100)
            }

            DispatchQueue.main.async {
                // Update history arrays
                self.readHistory.append(newReadSpeed)
                self.writeHistory.append(newWriteSpeed)
                if self.readHistory.count > self.maxHistoryCount { self.readHistory.removeFirst() }
                if self.writeHistory.count > self.maxHistoryCount { self.writeHistory.removeFirst() }

                self.readSpeed = newReadSpeed
                self.writeSpeed = newWriteSpeed
                // Only update processes if we fetched new data
                if includeProcesses {
                    self.processQueue.sync { self.processes = newProcesses }
                }

                // Update UI if we have process data (detail view requested it)
                if includeProcesses {
                    // Chart reads data directly from module's history arrays via closures
                    // Just update current speeds for display
                    self.chartView?.updateCurrentSpeeds(read: newReadSpeed, write: newWriteSpeed)
                    if !self.isRefreshPaused {
                        self.tableView?.reloadData()
                    }
                    NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "disk"])
                }
            }
        }
    }

    func makeDetailView() -> NSView {
        let toolbarHeight = PopoverToolbar.height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 100
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 20
        let totalHeight = toolbarHeight + headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 450  // Increased from 400 to show all columns

        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))

        // Toolbar
        let toolbar = PopoverToolbar.create(title: displayName, width: viewWidth)
        toolbar.frame = NSRect(x: 0, y: totalHeight - toolbarHeight, width: viewWidth, height: toolbarHeight)
        container.addSubview(toolbar)

        // Header
        let headerView = NSTextField(labelWithString: "Disk I/O")
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - toolbarHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)

        // Disk I/O chart (mirrored read/write)
        let chartY = totalHeight - toolbarHeight - headerHeight - chartHeight
        let chart = DiskChartView(
            frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight),
            readHistoryProvider: { [weak self] in self?.readHistory ?? [] },
            writeHistoryProvider: { [weak self] in self?.writeHistory ?? [] }
        )
        chart.startAnimation()
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

        let table = ProcessTableView(frame: NSRect(x: 0, y: 0, width: viewWidth - 16, height: CGFloat(rowCount) * rowHeight * 2))
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.getProcessInfo = { [weak self] row in
            guard let self = self else { return nil }
            let process = self.processQueue.sync { self.processes[safe: row] }
            guard let process = process else { return nil }
            return (process.pid, process.name)
        }
        table.pauseCallback = { [weak self] in
            self?.isRefreshPaused = true
        }
        table.resumeCallback = { [weak self] in
            self?.isRefreshPaused = false
        }

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

        // Show existing data immediately
        tableView?.reloadData()
        refreshDetail()

        return container
    }

    func cleanup() {
        chartView?.stopAnimation()
    }

    func refreshDetail() {
        updateDiskData(includeProcesses: true)
    }

    // MARK: - Disk Data using DASession (Stats approach)

    private func getDiskBytesFromDASession() -> (read: Int64, write: Int64) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return getDiskBytesFromIOKit()
        }

        var totalRead: Int64 = 0
        var totalWrite: Int64 = 0

        let keys: [URLResourceKey] = [.volumeNameKey]
        guard let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return getDiskBytesFromIOKit()
        }

        for url in paths {
            // Only process root and /Volumes paths
            guard url.pathComponents.count == 1 || (url.pathComponents.count > 1 && url.pathComponents[1] == "Volumes") else {
                continue
            }

            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
                continue
            }

            defer {
                // Don't release disk here as we're not using it directly
            }

            // Get the BSD name to find the IOKit object
            guard let diskName = DADiskGetBSDName(disk) else { continue }
            let bsdName = String(cString: diskName)

            // Get IOKit service for this disk
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
            if service == 0 { continue }
            defer { IOObjectRelease(service) }

            // Get parent device to read statistics
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }

            // Get properties
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(parent, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { continue }
            guard let props = properties?.takeRetainedValue() as? [String: Any] else { continue }

            // Read Statistics
            if let statistics = props["Statistics"] as? [String: Any] {
                if let read = statistics["Bytes (Read)"] as? Int64 {
                    totalRead += read
                } else if let read = statistics["Bytes (Read)"] as? NSNumber {
                    totalRead += read.int64Value
                }
                if let write = statistics["Bytes (Write)"] as? Int64 {
                    totalWrite += write
                } else if let write = statistics["Bytes (Write)"] as? NSNumber {
                    totalWrite += write.int64Value
                }
            }
        }

        if totalRead > 0 || totalWrite > 0 {
            return (totalRead, totalWrite)
        }

        // Fallback to IOKit approach
        return getDiskBytesFromIOKit()
    }

    private func getDiskBytesFromIOKit() -> (read: Int64, write: Int64) {
        var totalRead: Int64 = 0
        var totalWrite: Int64 = 0

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
                            totalRead += num.int64Value
                            break
                        } else if let val = statistics[readKey] as? Int64 {
                            totalRead += val
                            break
                        }
                    }

                    for writeKey in ["Bytes (Write)", "BytesWritten", "WriteBytes", "bytesWritten"] {
                        if let num = statistics[writeKey] as? NSNumber {
                            totalWrite += num.int64Value
                            break
                        } else if let val = statistics[writeKey] as? Int64 {
                            totalWrite += val
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

        return (totalRead, totalWrite)
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
        return processQueue.sync { processes.count }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let process = processQueue.sync { processes[safe: row] }
        guard let process = process else { return nil }

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

// MARK: - Disk Chart View

/// Single line chart view
private final class DiskLineChartView: NSView {
    private let dataProvider: () -> [Double]
    private let colorProvider: () -> NSColor
    private var flipY: Bool = false
    private var oldValues: [Double] = []
    private var lastUpdateTime: Date = Date()
    private var shiftOffset: CGFloat = 0
    private var leftShiftOffset: CGFloat = 0
    private var leftShiftValue: Double = 0

    init(frame: NSRect, dataProvider: @escaping () -> [Double], colorProvider: @escaping () -> NSColor) {
        self.dataProvider = dataProvider
        self.colorProvider = colorProvider
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFlipY(_ value: Bool) {
        flipY = value
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(true)

        let values = dataProvider()
        let displayCount = 60
        guard values.count > 1 else { return }

        let offset: CGFloat = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        let height = self.frame.height - offset
        let stepX = self.frame.width / CGFloat(displayCount - 1)
        let zero = flipY ? 0 : self.frame.height

        // Detect data change
        if values != oldValues {
            // Check if leftmost point is being removed
            if !oldValues.isEmpty && oldValues.count == displayCount && values.count == displayCount && oldValues.first != values.first {
                leftShiftOffset = stepX
                leftShiftValue = oldValues.first ?? 0
            }
            if !oldValues.isEmpty { shiftOffset = stepX }
            oldValues = values
            lastUpdateTime = Date()
        }

        let elapsed = Date().timeIntervalSince(lastUpdateTime)
        let progress = min(elapsed / 2.0, 1.0)
        let currentShift = shiftOffset * (1.0 - progress)
        let leftProgress = min(elapsed / 2.0, 1.0)
        let currentLeftShift = leftShiftOffset * (1.0 - leftProgress)

        var maxValue: Double = 0
        for v in values {
            if v > maxValue { maxValue = v }
        }
        if maxValue == 0 { maxValue = 1 }

        var linePoints: [CGPoint] = []
        for (i, v) in values.enumerated() {
            var y = (v / maxValue) * height
            if !flipY {
                y = height - y
            }
            let x = self.frame.width - CGFloat(values.count - 1 - i) * stepX + currentShift
            linePoints.append(CGPoint(x: x, y: y))
        }

        // Draw leftmost point sliding out
        if leftShiftOffset > 0 && currentLeftShift > 0 {
            let leftAlpha = 1.0 - leftProgress
            var leftY = (leftShiftValue / maxValue) * height
            if !flipY {
                leftY = height - leftY
            }
            let leftX = -currentLeftShift
            let leftPoint = CGPoint(x: leftX, y: leftY)
            if linePoints.count > 0 {
                let firstPoint = linePoints[0]
                let leftPath = NSBezierPath()
                leftPath.move(to: leftPoint)
                let midX = (leftPoint.x + firstPoint.x) / 2
                leftPath.curve(to: firstPoint, controlPoint1: CGPoint(x: midX, y: leftPoint.y), controlPoint2: CGPoint(x: midX, y: firstPoint.y))
                colorProvider().withAlphaComponent(leftAlpha).setStroke()
                leftPath.lineWidth = offset
                leftPath.stroke()
            }
        }

        guard linePoints.count > 1 else { return }

        let linePath = NSBezierPath()
        linePath.move(to: linePoints[0])
        for i in 1..<linePoints.count {
            let prev = linePoints[i - 1]
            let curr = linePoints[i]
            let midX = (prev.x + curr.x) / 2
            linePath.curve(to: curr, controlPoint1: CGPoint(x: midX, y: prev.y), controlPoint2: CGPoint(x: midX, y: curr.y))
        }

        linePath.lineWidth = offset
        colorProvider().setStroke()
        linePath.stroke()

        let areaPath = linePath.copy() as! NSBezierPath
        areaPath.line(to: CGPoint(x: linePoints[linePoints.count - 1].x, y: zero))
        areaPath.line(to: CGPoint(x: linePoints[0].x, y: zero))
        areaPath.close()

        let color = colorProvider()
        let gradient = NSGradient(colors: [color.withAlphaComponent(0.3), color.withAlphaComponent(0.5)])
        gradient?.draw(in: areaPath, angle: flipY ? 0 : 90)
    }
}

/// Disk chart view with two internal charts
final class DiskChartView: NSView {
    private let writeChart: DiskLineChartView
    private let readChart: DiskLineChartView

    private var currentReadSpeed: Double = 0
    private var currentWriteSpeed: Double = 0

    init(frame frameRect: NSRect, readHistoryProvider: @escaping () -> [Double], writeHistoryProvider: @escaping () -> [Double]) {
        let safeHeight = max(frameRect.height, 2)
        let topFrame = NSRect(x: 0, y: safeHeight / 2, width: frameRect.width, height: safeHeight / 2)
        let bottomFrame = NSRect(x: 0, y: 0, width: frameRect.width, height: safeHeight / 2)

        self.writeChart = DiskLineChartView(frame: topFrame, dataProvider: writeHistoryProvider, colorProvider: { NSColor.systemPurple.withAlphaComponent(0.8) })
        self.readChart = DiskLineChartView(frame: bottomFrame, dataProvider: readHistoryProvider, colorProvider: { NSColor.systemBlue.withAlphaComponent(0.6) })

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 4

        self.writeChart.setFlipY(true)
        self.readChart.setFlipY(false)

        addSubview(self.writeChart)
        addSubview(self.readChart)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopAnimation()
    }

    func startAnimation() {
        ChartTimerManager.shared.register(self)
    }

    func stopAnimation() {
        ChartTimerManager.shared.unregister(self)
    }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            super.needsDisplay = newValue
            if newValue {
                writeChart.needsDisplay = true
                readChart.needsDisplay = true
            }
        }
    }

    func updateCurrentSpeeds(read: Double, write: Double) {
        currentReadSpeed = read
        currentWriteSpeed = write
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw speed labels
        let padding: CGFloat = 6
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)

        let writeColor = NSColor.systemPurple.withAlphaComponent(0.8)
        let readColor = NSColor.systemBlue.withAlphaComponent(0.6)

        // Write label (top right)
        let writeLabel = "W \(formatSpeed(currentWriteSpeed))"
        let writeAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: writeColor
        ]
        let writeStr = NSAttributedString(string: writeLabel, attributes: writeAttrs)
        let writeSize = writeStr.size()
        writeStr.draw(at: CGPoint(x: bounds.width - padding - writeSize.width, y: bounds.height - padding - writeSize.height))

        // Read label (bottom right)
        let readLabel = "R \(formatSpeed(currentReadSpeed))"
        let readAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: readColor
        ]
        let readStr = NSAttributedString(string: readLabel, attributes: readAttrs)
        let readSize = readStr.size()
        readStr.draw(at: CGPoint(x: bounds.width - padding - readSize.width, y: padding))

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

        writeChart.frame = topFrame
        readChart.frame = bottomFrame
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
