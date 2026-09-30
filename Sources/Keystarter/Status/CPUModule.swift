// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// CPU monitoring module.
final class CPUModule: NSObject, StatusModule {

    var identifier: String { "cpu" }
    var displayName: String { L("status.cpu.displayName") }
    var shortName: String { "CPU" }

    private(set) var summaryText: String = "0"
    private(set) var summaryValue: String = "0"

    var refreshInterval: TimeInterval { 2.0 }

    private var processes: [AppProcessInfo] = []
    private var coreUsages: [CoreUsage] = []

    // History for line chart
    private var totalCPUHistory: [Double] = []
    private var systemCPUHistory: [Double] = []
    private var userCPUHistory: [Double] = []
    private let maxHistoryCount = 60

    private weak var chartView: CPUChartView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?

    func refreshSummary() {
        let usage = ProcessInfoProvider.shared.getTotalCPUUsage()
        let value = String(format: "%.0f", usage)
        summaryText = value
        summaryValue = value

        coreUsages = ProcessInfoProvider.shared.getPerCoreCPUUsage()
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 100)

        // Calculate system/user totals for history
        var systemTotal: Double = 0
        var userTotal: Double = 0
        for core in coreUsages {
            systemTotal += core.system
            userTotal += core.user
        }
        let coreCount = max(coreUsages.count, 1)
        systemTotal /= Double(coreCount)
        userTotal /= Double(coreCount)

        // Update history on every refresh (app startup onwards)
        totalCPUHistory.append(usage)
        systemCPUHistory.append(systemTotal)
        userCPUHistory.append(userTotal)
        if totalCPUHistory.count > maxHistoryCount {
            totalCPUHistory.removeFirst()
            systemCPUHistory.removeFirst()
            userCPUHistory.removeFirst()
        }
    }

    func makeDetailView() -> NSView {
        let toolbarHeight = PopoverToolbar.height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 120
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 20
        let totalHeight = toolbarHeight + headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        let viewWidth: CGFloat = 400

        let container = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: totalHeight))

        let toolbar = PopoverToolbar.create(title: displayName, width: viewWidth)
        toolbar.frame = NSRect(x: 0, y: totalHeight - toolbarHeight, width: viewWidth, height: toolbarHeight)
        container.addSubview(toolbar)

        let headerView = NSTextField(labelWithString: "CPU Usage")
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - toolbarHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)

        let chartY = totalHeight - toolbarHeight - headerHeight - chartHeight
        let chart = CPUChartView(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chart.setCoreUsages(coreUsages)
        chart.setHistory(total: totalCPUHistory, system: systemCPUHistory, user: userCPUHistory)
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

        let cpuColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cpu"))
        cpuColumn.width = 50
        cpuColumn.headerCell.title = "CPU"
        table.addTableColumn(cpuColumn)

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
        coreUsages = ProcessInfoProvider.shared.getPerCoreCPUUsage()
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 100)

        // History is updated in refreshSummary, not here

        chartView?.setCoreUsages(coreUsages)
        chartView?.setHistory(total: totalCPUHistory, system: systemCPUHistory, user: userCPUHistory)

        tableView?.reloadData()
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension CPUModule: NSTableViewDataSource, NSTableViewDelegate {

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
                switch process.processType {
                case .systemService:
                    typeIndicator = "🔧"
                case .userService:
                    typeIndicator = "👤"
                case .app, .unknown:
                    typeIndicator = "⚠️"
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

        case "cpu":
            let pctText = String(format: "%.1f%%", process.cpuUsage)
            let label = NSTextField(labelWithString: pctText)
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

// MARK: - CPU Line Chart View (with smooth scrolling animation)

private final class CPULineChartView: NSView {
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
            let view = Unmanaged<CPULineChartView>.fromOpaque(userInfo).takeUnretainedValue()
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

// MARK: - CPU Chart View (bar chart + line charts)

final class CPUChartView: NSView {
    private let systemChart: CPULineChartView
    private let userChart: CPULineChartView

    private let maxHistoryCount = 60
    private var currentCoreUsages: [CoreUsage] = []

    override init(frame frameRect: NSRect) {
        let barChartHeight: CGFloat = 70
        let dividerY = frameRect.height - barChartHeight - 12
        let lineChartHeight = dividerY - 8

        let lineFrame = NSRect(x: 0, y: 4, width: frameRect.width, height: lineChartHeight)

        self.systemChart = CPULineChartView(frame: lineFrame, num: maxHistoryCount, color: NSColor.systemRed.withAlphaComponent(0.6))
        self.userChart = CPULineChartView(frame: lineFrame, num: maxHistoryCount, color: NSColor.systemBlue.withAlphaComponent(0.6))

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        layer?.cornerRadius = 4

        addSubview(systemChart)
        addSubview(userChart)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        systemChart.stopAnimation()
        userChart.stopAnimation()
    }

    func setCoreUsages(_ usages: [CoreUsage]) {
        currentCoreUsages = usages
        needsDisplay = true
    }

    func setHistory(total: [Double], system: [Double], user: [Double]) {
        systemChart.reinit(maxHistoryCount)
        userChart.reinit(maxHistoryCount)

        for i in 0..<min(system.count, user.count) {
            systemChart.addValue(system[i])
            userChart.addValue(user[i])
        }
    }

    func startAnimation() {
        systemChart.startAnimation()
        userChart.startAnimation()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Clear existing subviews (keep line charts)
        subviews.forEach { subview in
            if subview !== systemChart && subview !== userChart {
                subview.removeFromSuperview()
            }
        }

        let chartWidth = bounds.width
        let chartHeight = bounds.height

        let coreCount = currentCoreUsages.count
        guard coreCount > 0 else { return }

        // Per-core bars at top
        let barChartHeight: CGFloat = 70
        let barSpacing: CGFloat = 4
        let barWidth = (chartWidth - CGFloat(coreCount - 1) * barSpacing) / CGFloat(coreCount)
        let maxBarHeight = barChartHeight - 28

        for (index, usage) in currentCoreUsages.enumerated() {
            let x = CGFloat(index) * (barWidth + barSpacing)
            let barY = chartHeight - barChartHeight + 16

            let totalHeight = max(2, min(CGFloat(usage.total / 100.0) * maxBarHeight, maxBarHeight))
            let systemHeight = min(CGFloat(usage.system / 100.0) * maxBarHeight, totalHeight - 2)
            let userHeight = totalHeight - systemHeight

            if systemHeight > 0 {
                let systemBar = NSView(frame: NSRect(x: x, y: barY, width: barWidth, height: systemHeight))
                systemBar.wantsLayer = true
                systemBar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
                systemBar.layer?.cornerRadius = 2
                addSubview(systemBar)
            }

            if userHeight > 0 {
                let userBar = NSView(frame: NSRect(x: x, y: barY + systemHeight, width: barWidth, height: userHeight))
                userBar.wantsLayer = true
                userBar.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
                userBar.layer?.cornerRadius = 2
                addSubview(userBar)
            }

            let coreLabel = NSTextField(labelWithString: "\(index)")
            coreLabel.font = .systemFont(ofSize: 9)
            coreLabel.alignment = .center
            coreLabel.textColor = .secondaryLabelColor
            coreLabel.frame = NSRect(x: x, y: chartHeight - barChartHeight + 2, width: barWidth, height: 12)
            addSubview(coreLabel)

            let pctLabel = NSTextField(labelWithString: String(format: "%.0f", usage.total))
            pctLabel.font = .systemFont(ofSize: 8)
            pctLabel.alignment = .center
            pctLabel.textColor = .secondaryLabelColor
            pctLabel.frame = NSRect(x: x, y: chartHeight - 12, width: barWidth, height: 10)
            addSubview(pctLabel)
        }

        // Divider
        let dividerY = chartHeight - barChartHeight - 12
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: chartWidth - 24, height: 1))
        divider.boxType = .separator
        addSubview(divider)
    }
}