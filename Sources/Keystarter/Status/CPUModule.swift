// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// CPU monitoring module.
final class CPUModule: NSObject, StatusModule {
    
    var identifier: String { "cpu" }
    var displayName: String { L("status.cpu.displayName") }
    var shortName: String { "CPU" }
    
    private(set) var summaryText: String = "0%"
    private(set) var summaryValue: String = "0%"
    
    var refreshInterval: TimeInterval { 2.0 }
    
    private var processes: [AppProcessInfo] = []
    private var coreUsages: [CoreUsage] = []
    
    // Detail view components for real-time update
    private weak var chartView: NSView?
    private weak var tableView: NSTableView?
    private var detailTimer: Timer?
    
    func refreshSummary() {
        let usage = ProcessInfoProvider.shared.getTotalCPUUsage()
        let value = String(format: "%.0f%%", usage)
        summaryText = value
        summaryValue = value
        
        coreUsages = ProcessInfoProvider.shared.getPerCoreCPUUsage()
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 100)
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
        
        // Per-core bar chart
        let chartY = totalHeight - headerHeight - chartHeight
        let chart = createCoreChart(frame: NSRect(x: 12, y: chartY, width: viewWidth - 24, height: chartHeight))
        chartView = chart
        container.addSubview(chart)
        
        // Divider line
        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: viewWidth - 24, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)
        
        // Process list: Name(150), PID(60), User(50), Threads(30), CPU(50)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: dividerY))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Table with header
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: viewWidth - 16, height: CGFloat(rowCount) * rowHeight * 2))
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        
        // Setup columns with header titles
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
        // Refresh data
        coreUsages = ProcessInfoProvider.shared.getPerCoreCPUUsage()
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 100)
        
        // Update chart
        updateChart()
        
        // Update table
        tableView?.reloadData()
    }
    
    private func updateChart() {
        guard let chart = chartView else { return }
        
        // Remove old bars
        chart.subviews.forEach { $0.removeFromSuperview() }
        
        let coreCount = coreUsages.count
        guard coreCount > 0 else { return }
        
        let barSpacing: CGFloat = 4
        let barWidth = (chart.bounds.width - CGFloat(coreCount - 1) * barSpacing) / CGFloat(coreCount)
        let maxBarHeight = chart.bounds.height - 28
        
        for (index, usage) in coreUsages.enumerated() {
            let x = CGFloat(index) * (barWidth + barSpacing)
            
            // Calculate bar heights
            let totalHeight = max(2, min(CGFloat(usage.total / 100.0) * maxBarHeight, maxBarHeight))
            let systemHeight = min(CGFloat(usage.system / 100.0) * maxBarHeight, totalHeight - 2)
            let userHeight = totalHeight - systemHeight
            
            // System bar (red, bottom)
            if systemHeight > 0 {
                let systemBar = NSView(frame: NSRect(x: x, y: 16, width: barWidth, height: systemHeight))
                systemBar.wantsLayer = true
                systemBar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
                systemBar.layer?.cornerRadius = 2
                chart.addSubview(systemBar)
            }
            
            // User bar (blue, top)
            if userHeight > 0 {
                let userBar = NSView(frame: NSRect(x: x, y: 16 + systemHeight, width: barWidth, height: userHeight))
                userBar.wantsLayer = true
                userBar.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
                userBar.layer?.cornerRadius = 2
                chart.addSubview(userBar)
            }
            
            // Core number
            let coreLabel = NSTextField(labelWithString: "\(index)")
            coreLabel.font = .systemFont(ofSize: 9)
            coreLabel.alignment = .center
            coreLabel.textColor = .secondaryLabelColor
            coreLabel.frame = NSRect(x: x, y: 2, width: barWidth, height: 12)
            chart.addSubview(coreLabel)
            
            // Percentage
            let pctLabel = NSTextField(labelWithString: String(format: "%.0f", usage.total))
            pctLabel.font = .systemFont(ofSize: 8)
            pctLabel.alignment = .center
            pctLabel.textColor = .secondaryLabelColor
            pctLabel.frame = NSRect(x: x, y: chart.bounds.height - 12, width: barWidth, height: 10)
            chart.addSubview(pctLabel)
        }
    }
    
    private func createCoreChart(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        
        let coreCount = coreUsages.count
        guard coreCount > 0 else { return view }
        
        let barSpacing: CGFloat = 4
        let barWidth = (frame.width - CGFloat(coreCount - 1) * barSpacing) / CGFloat(coreCount)
        let maxBarHeight = frame.height - 28
        
        for (index, usage) in coreUsages.enumerated() {
            let x = CGFloat(index) * (barWidth + barSpacing)
            
            // Calculate bar heights
            let totalHeight = max(2, min(CGFloat(usage.total / 100.0) * maxBarHeight, maxBarHeight))
            let systemHeight = min(CGFloat(usage.system / 100.0) * maxBarHeight, totalHeight - 2)
            let userHeight = totalHeight - systemHeight
            
            // System bar (red, bottom)
            if systemHeight > 0 {
                let systemBar = NSView(frame: NSRect(x: x, y: 16, width: barWidth, height: systemHeight))
                systemBar.wantsLayer = true
                systemBar.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
                systemBar.layer?.cornerRadius = 2
                view.addSubview(systemBar)
            }
            
            // User bar (blue, top)
            if userHeight > 0 {
                let userBar = NSView(frame: NSRect(x: x, y: 16 + systemHeight, width: barWidth, height: userHeight))
                userBar.wantsLayer = true
                userBar.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
                userBar.layer?.cornerRadius = 2
                view.addSubview(userBar)
            }
            
            // Core number
            let coreLabel = NSTextField(labelWithString: "\(index)")
            coreLabel.font = .systemFont(ofSize: 9)
            coreLabel.alignment = .center
            coreLabel.textColor = .secondaryLabelColor
            coreLabel.frame = NSRect(x: x, y: 2, width: barWidth, height: 12)
            view.addSubview(coreLabel)
            
            // Percentage
            let pctLabel = NSTextField(labelWithString: String(format: "%.0f", usage.total))
            pctLabel.font = .systemFont(ofSize: 8)
            pctLabel.alignment = .center
            pctLabel.textColor = .secondaryLabelColor
            pctLabel.frame = NSRect(x: x, y: frame.height - 12, width: barWidth, height: 10)
            view.addSubview(pctLabel)
        }
        
        return view
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
                // App with icon
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
                // Non-app process with type indicator
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