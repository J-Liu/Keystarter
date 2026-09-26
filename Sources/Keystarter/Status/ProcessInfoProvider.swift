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
    let isApp: Bool
}

/// Provider for process and system information.
final class ProcessInfoProvider {
    
    static let shared = ProcessInfoProvider()
    
    private init() {}
    
    // MARK: - CPU Usage
    
    private var prevTotalTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0
    private var prevCoreTotal: [UInt64] = []
    private var prevCoreActive: [UInt64] = []
    
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
        
        let user = UInt64(cpuLoad.cpu_ticks.0)
        let system = UInt64(cpuLoad.cpu_ticks.1)
        let idle = UInt64(cpuLoad.cpu_ticks.2)
        let nice = UInt64(cpuLoad.cpu_ticks.3)
        let totalTicks = user + system + idle + nice
        
        // Calculate delta from previous measurement
        let totalDelta = totalTicks > prevTotalTicks ? totalTicks - prevTotalTicks : 0
        let idleDelta = idle > prevIdleTicks ? idle - prevIdleTicks : 0
        
        prevTotalTicks = totalTicks
        prevIdleTicks = idle
        
        if totalDelta == 0 { return 0 }
        return Double(totalDelta - idleDelta) / Double(totalDelta) * 100.0
    }
    
    /// Get per-core CPU usage percentages.
    func getPerCoreCPUUsage() -> [Double] {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        
        guard result == KERN_SUCCESS, let info = cpuInfo else {
            return Array(repeating: 0.0, count: ProcessInfo.processInfo.processorCount)
        }
        
        var usages: [Double] = []
        let numCores = Int(numCPUs)
        let ticksPerCore = Int(CPU_STATE_MAX)
        var currentTotal: [UInt64] = []
        var currentActive: [UInt64] = []
        
        for i in 0..<numCores {
            let offset = i * ticksPerCore
            let user = UInt64(info[offset + Int(CPU_STATE_USER)])
            let system = UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[offset + Int(CPU_STATE_NICE)])
            let total = user + system + idle + nice
            let active = user + system + nice
            
            currentTotal.append(total)
            currentActive.append(active)
            
            // Calculate delta from previous
            let prevTotal = i < prevCoreTotal.count ? prevCoreTotal[i] : 0
            let prevActive = i < prevCoreActive.count ? prevCoreActive[i] : 0
            
            let totalDelta = total > prevTotal ? total - prevTotal : 0
            let activeDelta = active > prevActive ? active - prevActive : 0
            
            if totalDelta > 0 {
                usages.append(Double(activeDelta) / Double(totalDelta) * 100.0)
            } else {
                usages.append(0.0)
            }
        }
        
        prevCoreTotal = currentTotal
        prevCoreActive = currentActive
        
        // Free memory
        let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        
        return usages
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
        var processes: [AppProcessInfo] = []
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs = Set<Int32>()
        
        // Get all running apps
        var appNames: [Int32: String] = [:]
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            guard let url = app.bundleURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            appPIDs.insert(app.processIdentifier)
            appNames[app.processIdentifier] = name
        }
        
        // Get all PIDs using sysctl
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 3, &procList, &size, nil, 0)
        
        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            let name = String(cString: withUnsafePointer(to: proc.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) {
                    $0
                }
            })
            
            let cpuUsage = getProcessCPUUsage(pid: pid)
            let memoryUsage = getProcessMemoryUsage(pid: pid)
            let isApp = appPIDs.contains(pid)
            
            processes.append(AppProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                isApp: isApp
            ))
        }
        
        processes.sort { $0.cpuUsage > $1.cpuUsage }
        return Array(processes.prefix(limit))
    }
    
    /// Get list of processes sorted by memory usage.
    func getProcessesByMemory(limit: Int = 30) -> [AppProcessInfo] {
        var processes: [AppProcessInfo] = []
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs = Set<Int32>()
        
        // Get all running apps
        var appNames: [Int32: String] = [:]
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            guard let url = app.bundleURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            appPIDs.insert(app.processIdentifier)
            appNames[app.processIdentifier] = name
        }
        
        // Get all PIDs using sysctl
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 3, &procList, &size, nil, 0)
        
        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            let name = String(cString: withUnsafePointer(to: proc.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) {
                    $0
                }
            })
            
            let cpuUsage = getProcessCPUUsage(pid: pid)
            let memoryUsage = getProcessMemoryUsage(pid: pid)
            let isApp = appPIDs.contains(pid)
            
            processes.append(AppProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                isApp: isApp
            ))
        }
        
        processes.sort { $0.memoryUsage > $1.memoryUsage }
        return Array(processes.prefix(limit))
    }
    
    // MARK: - Private Helpers
    
    private var previousProcCPU: [Int32: (user: UInt64, system: UInt64, time: Date)] = [:]
    private let procCPULock = NSLock()
    
    private func getProcessCPUUsage(pid: Int32) -> Double {
        var rusage = rusage_info_current()
        let rusagePtr = withUnsafeMutablePointer(to: &rusage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { $0 }
        }
        let result = proc_pid_rusage(Int32(pid), RUSAGE_INFO_CURRENT, rusagePtr)
        
        guard result == 0 else { return 0 }
        
        let userTime = rusage.ri_user_time
        let systemTime = rusage.ri_system_time
        let total = userTime + systemTime
        
        // Calculate delta from previous
        procCPULock.lock()
        defer { procCPULock.unlock() }
        
        let now = Date()
        if let prev = previousProcCPU[pid] {
            let elapsed = now.timeIntervalSince(prev.time)
            if elapsed > 0 {
                let prevTotal = prev.user + prev.system
                let delta = total > prevTotal ? Double(total - prevTotal) : 0
                // ri_user_time is already in seconds (not nanoseconds on Apple Silicon)
                let cpuTime = delta
                let usage = (cpuTime / elapsed) * 100.0
                
                previousProcCPU[pid] = (userTime, systemTime, now)
                return min(usage, 100.0 * Double(ProcessInfo.processInfo.activeProcessorCount))
            }
        }
        
        previousProcCPU[pid] = (userTime, systemTime, now)
        return 0
    }
    
    private func getProcessMemoryUsage(pid: Int32) -> UInt64 {
        var rusage = rusage_info_current()
        let rusagePtr = withUnsafeMutablePointer(to: &rusage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { $0 }
        }
        let result = proc_pid_rusage(Int32(pid), RUSAGE_INFO_CURRENT, rusagePtr)
        
        guard result == 0 else { return 0 }
        return rusage.ri_resident_size
    }
}