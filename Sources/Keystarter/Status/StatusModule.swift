// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Protocol for status bar modules.
protocol StatusModule: AnyObject {
    /// Unique identifier for the module.
    var identifier: String { get }
    
    /// Display name shown in settings.
    var displayName: String { get }
    
    /// Short name shown in status bar (e.g., "CPU").
    var shortName: String { get }
    
    /// Current value shown in status bar (e.g., "23%").
    var summaryValue: String { get }
    
    /// Full summary text for backwards compatibility.
    var summaryText: String { get }
    
    /// Refresh interval in seconds.
    var refreshInterval: TimeInterval { get }
    
    /// Refresh the summary data.
    func refreshSummary()

    /// Create the detail view for popover.
    func makeDetailView() -> NSView

    /// Cleanup when popover closes (invalidate timers, etc.)
    func cleanup()
}

extension StatusModule {
    var refreshInterval: TimeInterval { 2.0 }
    func cleanup() {} // Default empty implementation
}

// MARK: - Safe Array Access

extension Array {
    /// Safe subscript that returns nil if index is out of bounds.
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Process Menu Helper

/// Creates a context menu for process table views.
func createProcessContextMenu(pid: Int32, processName: String) -> NSMenu {
    let menu = NSMenu()
    
    let killItem = NSMenuItem(title: L("status.process.kill"), action: nil, keyEquivalent: "")
    killItem.target = ProcessMenuHandler.shared
    killItem.representedObject = (pid, processName)
    killItem.action = #selector(ProcessMenuHandler.killProcess(_:))
    menu.addItem(killItem)
    
    let forceKillItem = NSMenuItem(title: L("status.process.forceKill"), action: nil, keyEquivalent: "")
    forceKillItem.target = ProcessMenuHandler.shared
    forceKillItem.representedObject = (pid, processName)
    forceKillItem.action = #selector(ProcessMenuHandler.forceKillProcess(_:))
    menu.addItem(forceKillItem)
    
    return menu
}

/// Handler for process menu actions.
final class ProcessMenuHandler {
    static let shared = ProcessMenuHandler()
    
    @objc func killProcess(_ sender: NSMenuItem) {
        guard let (pid, name) = sender.representedObject as? (Int32, String) else { return }
        killProcessByPID(pid, name: name, force: false)
    }
    
    @objc func forceKillProcess(_ sender: NSMenuItem) {
        guard let (pid, name) = sender.representedObject as? (Int32, String) else { return }
        killProcessByPID(pid, name: name, force: true)
    }
    
    private func killProcessByPID(_ pid: Int32, name: String, force: Bool) {
        let signal = force ? SIGKILL : SIGTERM
        let result = kill(pid, signal)
        
        if result != 0 {
            let error = String(cString: strerror(errno))
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = L("status.process.killFailed")
                alert.informativeText = "\(name) (PID: \(pid)): \(error)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: L("alert.ok"))
                alert.beginSheetModal(for: NSApp.keyWindow ?? NSApp.windows.first!)
            }
        }
    }
}

/// Table view with right-click context menu for processes.
final class ProcessTableView: NSTableView {
    /// Closure to get process info for a row. Returns (pid, name) or nil.
    var getProcessInfo: ((Int) -> (pid: Int32, name: String)?)?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        
        guard row >= 0, let info = getProcessInfo?(row) else {
            return nil
        }
        
        // Select the row before showing menu so user knows which process
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        
        return createProcessContextMenu(pid: info.pid, processName: info.name)
    }
}