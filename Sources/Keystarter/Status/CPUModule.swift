// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// CPU monitoring module.
final class CPUModule: NSObject, StatusModule {
    
    var identifier: String { "cpu" }
    var displayName: String { L("status.cpu.displayName") }
    
    private(set) var summaryText: String = "CPU --%"
    
    var icon: NSImage? {
        NSImage(systemSymbolName: "cpu", accessibilityDescription: "CPU")
    }
    
    private var processes: [AppProcessInfo] = []
    private var previousTotalTime: UInt64 = 0
    private var previousIdleTime: UInt64 = 0
    
    func refreshSummary() {
        let usage = ProcessInfoProvider.shared.getTotalCPUUsage()
        summaryText = String(format: "CPU %.0f%%", usage)
        
        // Also update process list
        processes = ProcessInfoProvider.shared.getProcessesByCPU(limit: 30)
    }
    
    func makeDetailView() -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        
        // Process name column
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 200
        tableView.addTableColumn(nameColumn)
        
        // CPU column
        let cpuColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cpu"))
        cpuColumn.width = 80
        tableView.addTableColumn(cpuColumn)
        
        tableView.dataSource = self
        tableView.delegate = self
        
        scrollView.documentView = tableView
        
        // Header
        let headerView = NSTextField(labelWithString: displayName)
        headerView.font = .systemFont(ofSize: 14, weight: .semibold)
        headerView.frame = NSRect(x: 16, y: 380, width: 200, height: 20)
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        container.addSubview(headerView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 320, height: 380)
        container.addSubview(scrollView)
        
        return container
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
            let label = NSTextField(labelWithString: process.name)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 8, y: 4, width: 180, height: 16)
            cell.addSubview(label)
        } else {
            let label = NSTextField(labelWithString: String(format: "%.1f%%", process.cpuUsage))
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 0, y: 4, width: 64, height: 16)
            cell.addSubview(label)
        }
        
        return cell
    }
}