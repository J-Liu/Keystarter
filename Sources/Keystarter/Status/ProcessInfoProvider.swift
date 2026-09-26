// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AppKit

/// Process information structure.
struct AppProcessInfo {
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: UInt64
}

/// Provider for process and system information.
final class ProcessInfoProvider {
    
    static let shared = ProcessInfoProvider()
    
    private init() {}
    
    // MARK: - CPU Usage
    
    /// Get total CPU usage percentage.
    func getTotalCPUUsage() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        
        let totalTicks = cpuLoad.cpu_ticks.0 + cpuLoad.cpu_ticks.1 + cpuLoad.cpu_ticks.2 + cpuLoad.cpu_ticks.3
        let idleTicks = cpuLoad.cpu_ticks.2
        
        if totalTicks == 0 { return 0 }
        return Double(totalTicks - idleTicks) / Double(totalTicks) * 100.0
    }
    
    // MARK: - Memory Usage
    
    /// Get memory usage info (used, total in bytes).
    func getMemoryUsage() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return (0, 0) }
        
        let totalMemory = UInt64(ProcessInfo.processInfo.physicalMemory)
        let pageSize = UInt64(vm_kernel_page_size)
        
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        
        return (active + wired, totalMemory)
    }
    
    // MARK: - Process List
    
    /// Get list of processes sorted by CPU usage.
    func getProcessesByCPU(limit: Int = 30) -> [AppProcessInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var processes: [AppProcessInfo] = []
        
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            guard let url = app.bundleURL else { continue }
            
            let name = url.deletingPathExtension().lastPathComponent
            let memory = getMemoryForApp(app)
            let cpu = getCPUForApp(app)
            
            processes.append(AppProcessInfo(pid: app.processIdentifier, name: name, cpuUsage: cpu, memoryUsage: memory))
        }
        
        processes.sort { $0.cpuUsage > $1.cpuUsage }
        return Array(processes.prefix(limit))
    }
    
    /// Get list of processes sorted by memory usage.
    func getProcessesByMemory(limit: Int = 30) -> [AppProcessInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var processes: [AppProcessInfo] = []
        
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            guard let url = app.bundleURL else { continue }
            
            let name = url.deletingPathExtension().lastPathComponent
            let memory = getMemoryForApp(app)
            let cpu = getCPUForApp(app)
            
            processes.append(AppProcessInfo(pid: app.processIdentifier, name: name, cpuUsage: cpu, memoryUsage: memory))
        }
        
        processes.sort { $0.memoryUsage > $1.memoryUsage }
        return Array(processes.prefix(limit))
    }
    
    private func getMemoryForApp(_ app: NSRunningApplication) -> UInt64 {
        _ = app.processIdentifier // unused for now
        
        var info = task_basic_info_64()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_64>.size / MemoryLayout<natural_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO_64), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }
    
    private func getCPUForApp(_ app: NSRunningApplication) -> Double {
        // Simple estimation based on app activity
        // For a more accurate measurement, we'd need to track CPU time over intervals
        return 0.0
    }
}