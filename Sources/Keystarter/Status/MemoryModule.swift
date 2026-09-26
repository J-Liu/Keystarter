// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Memory monitoring module.
final class MemoryModule: NSObject, StatusModule {
    
    var identifier: String { "memory" }
    var displayName: String { L("status.memory.displayName") }
    
    private(set) var summaryText: String = "MEM --"
    
    var icon: NSImage? {
        NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Memory")
    }
    
    private var processes: [AppProcessInfo] = []
    private var usedMemory: UInt64 = 0
    private var totalMemory: UInt64 = 0
    
    func refreshSummary() {
        let (used, total) = ProcessInfoProvider.shared.getMemoryUsage()
        usedMemory = used
        totalMemory = total
        
        let usedGB = Double(used) / 1_073_741_824.0
        let totalGB = Double(total) / 1_073_741_824.0
        
        summaryText = String(format: "MEM %.1f/%.0fG", usedGB, totalGB)
        
        // Also update process list
        processes = ProcessInfoProvider.shared.getProcessesByMemory(limit: 30)
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
        
        // Memory column
        let memColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("memory"))
        memColumn.width = 80
        tableView.addTableColumn(memColumn)
        
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
    
    private func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        let mb = Double(bytes) / 1_048_576.0
        
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", mb)
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
        
        if tableColumn?.identifier.rawValue == "name" {
            let label = NSTextField(labelWithString: process.name)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 8, y: 4, width: 180, height: 16)
            cell.addSubview(label)
        } else {
            let label = NSTextField(labelWithString: formatMemory(process.memoryUsage))
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.frame = NSRect(x: 0, y: 4, width: 64, height: 16)
            cell.addSubview(label)
        }
        
        return cell
    }
}