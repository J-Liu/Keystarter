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
    private var coreUsages: [Double] = []
    
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
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 30)
    }
    
    func makeDetailView() -> NSView {
        // Calculate height
        let headerHeight: CGFloat = 24
        let chartHeight: CGFloat = 80
        let dividerHeight: CGFloat = 12
        let rowHeight: CGFloat = 20
        let rowCount = 30
        let totalHeight = headerHeight + chartHeight + dividerHeight + CGFloat(rowCount) * rowHeight + 16
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: totalHeight))
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 12, weight: .semibold)
        headerView.frame = NSRect(x: 12, y: totalHeight - 20, width: 200, height: 16)
        container.addSubview(headerView)
        
        // Per-core bar chart
        let chartY = totalHeight - headerHeight - chartHeight
        let chart = createCoreChart(frame: NSRect(x: 12, y: chartY, width: 336, height: chartHeight))
        chartView = chart
        container.addSubview(chart)
        
        // Divider line
        let dividerY = chartY - dividerHeight + 4
        let divider = NSBox(frame: NSRect(x: 12, y: dividerY, width: 336, height: 1))
        divider.boxType = .separator
        container.addSubview(divider)
        
        // Process list
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: dividerY))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let table = NSTableView(frame: scrollView.bounds)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 240
        table.addTableColumn(nameColumn)
        
        let cpuColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cpu"))
        cpuColumn.width = 100
        table.addTableColumn(cpuColumn)
        
        table.dataSource = self
        table.delegate = self
        
        scrollView.documentView = table
        tableView = table
        container.addSubview(scrollView)
        
        // Start refresh timer for detail view
        startDetailTimer()
        
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
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 30)
        
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
            let barHeight = max(2, min(CGFloat(usage / 100.0) * maxBarHeight, maxBarHeight))
            
            // Bar
            let bar = NSView(frame: NSRect(x: x, y: 16, width: barWidth, height: barHeight))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
            bar.layer?.cornerRadius = 2
            chart.addSubview(bar)
            
            // Core number
            let coreLabel = NSTextField(labelWithString: "\(index)")
            coreLabel.font = .systemFont(ofSize: 9)
            coreLabel.alignment = .center
            coreLabel.textColor = .secondaryLabelColor
            coreLabel.frame = NSRect(x: x, y: 2, width: barWidth, height: 12)
            chart.addSubview(coreLabel)
            
            // Percentage
            let pctLabel = NSTextField(labelWithString: String(format: "%.0f", usage))
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
            let barHeight = max(2, min(CGFloat(usage / 100.0) * maxBarHeight, maxBarHeight))
            
            // Bar
            let bar = NSView(frame: NSRect(x: x, y: 16, width: barWidth, height: barHeight))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
            bar.layer?.cornerRadius = 2
            view.addSubview(bar)
            
            // Core number
            let coreLabel = NSTextField(labelWithString: "\(index)")
            coreLabel.font = .systemFont(ofSize: 9)
            coreLabel.alignment = .center
            coreLabel.textColor = .secondaryLabelColor
            coreLabel.frame = NSRect(x: x, y: 2, width: barWidth, height: 12)
            view.addSubview(coreLabel)
            
            // Percentage
            let pctLabel = NSTextField(labelWithString: String(format: "%.0f", usage))
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
        
        if tableColumn?.identifier.rawValue == "name" {
            let displayName: String
            if process.isApp {
                displayName = process.name
            } else {
                displayName = "⚠️ \(process.name) pid:\(process.pid)"
            }
            
            let label = NSTextField(labelWithString: displayName)
            label.font = .systemFont(ofSize: 10)
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 2, y: 2, width: 236, height: 16)
            cell.addSubview(label)
        } else {
            let pctText = String(format: "%.1f%%", process.cpuUsage)
            let label = NSTextField(labelWithString: pctText)
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 2, y: 2, width: 96, height: 16)
            cell.addSubview(label)
        }
        
        return cell
    }
}