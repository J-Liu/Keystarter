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
    let ppid: Int32
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

    // History for charts
    private var deviceHistory: [Double] = []
    private var rendererHistory: [Double] = []
    private var tilerHistory: [Double] = []
    private let maxHistoryCount = 60

    // GPU time tracking for per-process usage
    private var prevGpuTimes: [Int32: UInt64] = [:]
    private var prevTimestamp: TimeInterval = 0
    private let gpuTimeLock = NSLock()

    private weak var chartView: GPUChartView?
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

        // Update history on every refresh (app startup onwards)
        deviceHistory.append(info.device)
        rendererHistory.append(info.renderer)
        tilerHistory.append(info.tiler)
        if deviceHistory.count > maxHistoryCount {
            deviceHistory.removeFirst()
            rendererHistory.removeFirst()
            tilerHistory.removeFirst()
        }
    }

    func makeDetailView() -> NSView {
        let toolbarHeight = PopoverToolbar.height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 160
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 30
        let totalHeight = toolbarHeight + headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 400

        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))

        let toolbar = PopoverToolbar.create(title: displayName, width: viewWidth)
        toolbar.frame = NSRect(x: 0, y: totalHeight - toolbarHeight, width: viewWidth, height: toolbarHeight)
        container.addSubview(toolbar)

        let headerView = NSTextField(labelWithString: "GPU Usage")
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - toolbarHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)

        let chartY = totalHeight - toolbarHeight - headerHeight - chartHeight
        let chart = GPUChartView(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chart.setValues(device: gpuUsage, renderer: rendererUtil, tiler: tilerUtil)
        chart.setHistory(device: deviceHistory, renderer: rendererHistory, tiler: tilerHistory)
        chart.startAnimation()
        chartView = chart
        container.addSubview(chart)

        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: viewWidth - 24, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)

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

        let value = String(format: "%.0f%%", info.device)
        summaryText = value
        summaryValue = value

        // History is updated in refreshSummary, not here

        processes = getGPUProcesses(limit: 100)

        chartView?.setValues(device: gpuUsage, renderer: rendererUtil, tiler: tilerUtil)
        chartView?.setHistory(device: deviceHistory, renderer: rendererHistory, tiler: tilerHistory)

        tableView?.reloadData()

        NotificationCenter.default.post(name: .moduleDataUpdated, object: nil, userInfo: ["module": "gpu"])
    }

    // MARK: - GPU Data from IORegistry

    private func getGPUInfo() -> (device: Double, renderer: Double, tiler: Double, vramUsed: UInt64, vramTotal: UInt64) {
        var deviceUtil: Double = 0
        var rendererUtil: Double = 0
        var tilerUtil: Double = 0
        var vramUsed: UInt64 = 0
        var vramTotal: UInt64 = 0

        var iterator: io_iterator_t = 0
        var matching = IOServiceMatching("IOAccelerator")
        var result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        if result != KERN_SUCCESS || iterator == 0 {
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

            if let num = statistics["Device Utilization %"] as? NSNumber {
                deviceUtil = num.doubleValue
            } else if let val = statistics["Device Utilization %"] as? Double {
                deviceUtil = val
            } else if let val = statistics["Device Utilization %"] as? Int {
                deviceUtil = Double(val)
            }

            if let num = statistics["Renderer Utilization %"] as? NSNumber {
                rendererUtil = num.doubleValue
            } else if let val = statistics["Renderer Utilization %"] as? Double {
                rendererUtil = val
            } else if let val = statistics["Renderer Utilization %"] as? Int {
                rendererUtil = Double(val)
            }

            if let num = statistics["Tiler Utilization %"] as? NSNumber {
                tilerUtil = num.doubleValue
            } else if let val = statistics["Tiler Utilization %"] as? Double {
                tilerUtil = val
            } else if let val = statistics["Tiler Utilization %"] as? Int {
                tilerUtil = Double(val)
            }

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
        let gpuTimes = getProcessGPUTimesFromIORegistry()

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

        var processes: [GPUProcessInfo] = []

        for (pid, gpuTime) in gpuTimes {
            guard pid > 0 else { continue }

            var name: String
            if let appName = appNames[pid] {
                name = appName
            } else if let path = getProcessPath(pid: pid) {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
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
            let ppid = getProcessPPID(pid: pid)

            processes.append(GPUProcessInfo(
                pid: pid,
                name: name,
                gpuUsage: gpuTime,
                memoryUsage: memory,
                isApp: isApp,
                icon: appIcons[pid],
                user: user,
                threads: threads,
                ppid: ppid
            ))
        }

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

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(child, &className)
            let classNameString = String(cString: className)

            guard classNameString == "AGXDeviceUserClient" else { continue }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            guard let creator = props["IOUserClientCreator"] as? String else { continue }

            let parts = creator.split(separator: ",", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let pidPart = String(parts[0].trimmingCharacters(in: .whitespaces))
            guard pidPart.hasPrefix("pid "), let pid = Int32(pidPart.dropFirst(4)) else { continue }

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

        let now = Date().timeIntervalSince1970
        gpuTimeLock.lock()
        defer { gpuTimeLock.unlock() }

        var result: [Int32: Double] = [:]
        let timeDelta = now - prevTimestamp

        if timeDelta > 0 && prevTimestamp > 0 {
            for (pid, time) in currentTimes {
                if let prev = prevGpuTimes[pid] {
                    let delta = time > prev ? time - prev : 0
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

    private func getProcessPPID(pid: Int32) -> Int32 {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &proc, &size, nil, 0) == 0 {
            return proc.kp_eproc.e_ppid
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
                let typeIndicator = (process.user == "root" || process.ppid == 1) ? "🔧" : "👤"
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

// MARK: - GPU Line Chart View (with smooth scrolling animation)

private final class GPULineChartView: NSView {
    private var points: [Double?] = []
    private var color: NSColor
    private let sampleInterval: TimeInterval = 2.0
    private var displayLink: CVDisplayLink?
    private var lastUpdateTime: Date = Date()

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

    func startAnimation() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<GPULineChartView>.fromOpaque(userInfo).takeUnretainedValue()
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

        let height = self.frame.height
        let xRatio = self.frame.width / CGFloat(points.count - 1)

        let elapsed = Date().timeIntervalSince(lastUpdateTime)
        let progress = min(elapsed / sampleInterval, 1.0)
        let xOffset = progress * xRatio

        var linePoints: [CGPoint] = []
        for (i, v) in points.enumerated() {
            guard let v else { continue }

            let y = v / 100.0 * height
            let x = CGFloat(i) * xRatio - xOffset
            linePoints.append(CGPoint(x: x, y: y))
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

        linePath.lineWidth = 1.5
        color.setStroke()
        linePath.stroke()
    }
}

// MARK: - GPU Chart View (circles + line charts)

final class GPUChartView: NSView {
    private let deviceChart: GPULineChartView
    private let rendererChart: GPULineChartView
    private let tilerChart: GPULineChartView

    private let maxHistoryCount = 60

    private var currentDevice: Double = 0
    private var currentRenderer: Double = 0
    private var currentTiler: Double = 0

    override init(frame frameRect: NSRect) {
        let bigRadius: CGFloat = 28
        let circleCenterY = frameRect.height - 15 - bigRadius
        let labelY = circleCenterY - bigRadius - 20
        let dividerY = labelY - 7
        let lineChartHeight = dividerY - 8

        let lineFrame = NSRect(x: 0, y: 4, width: frameRect.width, height: lineChartHeight)

        self.deviceChart = GPULineChartView(frame: lineFrame, num: maxHistoryCount, color: NSColor.systemPurple.withAlphaComponent(0.8))
        self.rendererChart = GPULineChartView(frame: lineFrame, num: maxHistoryCount, color: NSColor.systemBlue.withAlphaComponent(0.6))
        self.tilerChart = GPULineChartView(frame: lineFrame, num: maxHistoryCount, color: NSColor.systemOrange.withAlphaComponent(0.6))

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 4

        addSubview(deviceChart)
        addSubview(rendererChart)
        addSubview(tilerChart)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        deviceChart.stopAnimation()
        rendererChart.stopAnimation()
        tilerChart.stopAnimation()
    }

    func setValues(device: Double, renderer: Double, tiler: Double) {
        currentDevice = device
        currentRenderer = renderer
        currentTiler = tiler
        needsDisplay = true
    }

    func setHistory(device: [Double], renderer: [Double], tiler: [Double]) {
        deviceChart.reinit(maxHistoryCount)
        rendererChart.reinit(maxHistoryCount)
        tilerChart.reinit(maxHistoryCount)

        for i in 0..<min(device.count, min(renderer.count, tiler.count)) {
            deviceChart.addValue(device[i])
            rendererChart.addValue(renderer[i])
            tilerChart.addValue(tiler[i])
        }
    }

    func startAnimation() {
        deviceChart.startAnimation()
        rendererChart.startAnimation()
        tilerChart.startAnimation()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let chartWidth = bounds.width
        let chartHeight = bounds.height

        let bigRadius: CGFloat = 28
        let smallRadius: CGFloat = 20
        let circleCenterY = chartHeight - 15 - bigRadius

        let centerX = chartWidth / 2
        drawPieChart(center: NSPoint(x: centerX, y: circleCenterY), radius: bigRadius,
                     value: currentDevice, color: NSColor.systemPurple, label: "Device")

        let leftX = centerX - bigRadius - smallRadius - 20
        drawPieChart(center: NSPoint(x: leftX, y: circleCenterY), radius: smallRadius,
                     value: currentRenderer, color: NSColor.systemBlue, label: "Renderer")

        let rightX = centerX + bigRadius + smallRadius + 20
        drawPieChart(center: NSPoint(x: rightX, y: circleCenterY), radius: smallRadius,
                     value: currentTiler, color: NSColor.systemOrange, label: "Tiler")

        let labelY = circleCenterY - bigRadius - 20
        let dividerY = labelY - 7
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: chartWidth - 24, height: 1))
        divider.boxType = .separator
        addSubview(divider)
    }

    private func drawPieChart(center: NSPoint, radius: CGFloat, value: Double, color: NSColor, label: String) {
        let circle = NSView(frame: NSRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        circle.wantsLayer = true
        circle.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        circle.layer?.cornerRadius = radius
        addSubview(circle)

        let pctLabel = NSTextField(labelWithString: String(format: "%.0f%%", value))
        pctLabel.font = .systemFont(ofSize: radius > 24 ? 13 : 10, weight: .semibold)
        pctLabel.textColor = NSColor.white
        pctLabel.alignment = .center
        let labelWidth = radius > 24 ? 50.0 : 35.0
        pctLabel.frame = NSRect(x: center.x - labelWidth / 2, y: center.y - 6,
                                width: labelWidth, height: 14)
        addSubview(pctLabel)

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: center.x - 45, y: center.y - radius - 18, width: 90, height: 14)
        addSubview(nameLabel)
    }
}