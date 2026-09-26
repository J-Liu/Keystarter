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
        
        for i in 0..<numCores {
            let offset = i * ticksPerCore
            let user = UInt64(info[offset + Int(CPU_STATE_USER)])
            let system = UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[offset + Int(CPU_STATE_NICE)])
            let total = user + system + idle + nice
            
            if total > 0 {
                let usage = Double(user + system + nice) / Double(total) * 100.0
                usages.append(usage)
            } else {
                usages.append(0.0)
            }
        }
        
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
    
    private var previousCPUInfo: [Int32: (user: UInt64, system: UInt64, time: Date)] = [:]
    private let cpuLock = NSLock()
    
    private func getProcessCPUUsage(pid: Int32) -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let task = task_for_pid(mach_task_self_, pid, nil)
        guard task == KERN_SUCCESS else { return 0 }
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0 }
        
        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            
            if kr == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUser += UInt64(info.user_time.seconds) * 1_000_000 + UInt64(info.user_time.microseconds)
                totalSystem += UInt64(info.system_time.seconds) * 1_000_000 + UInt64(info.system_time.microseconds)
            }
        }
        
        // Free thread list
        let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        
        // Calculate delta from previous measurement
        cpuLock.lock()
        defer { cpuLock.unlock() }
        
        let now = Date()
        if let prev = previousCPUInfo[pid] {
            let elapsed = now.timeIntervalSince(prev.time)
            if elapsed > 0 {
                let userDelta = totalUser > prev.user ? Double(totalUser - prev.user) : 0
                let systemDelta = totalSystem > prev.system ? Double(totalSystem - prev.system) : 0
                let cpuTime = (userDelta + systemDelta) / 1_000_000.0
                let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
                let usage = (cpuTime / elapsed / cores) * 100.0
                
                previousCPUInfo[pid] = (totalUser, totalSystem, now)
                return min(usage, 100.0)
            }
        }
        
        previousCPUInfo[pid] = (totalUser, totalSystem, now)
        return 0
    }
    
    private func getProcessMemoryUsage(pid: Int32) -> UInt64 {
        var info = task_basic_info_64()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_64>.size / MemoryLayout<natural_t>.size)
        
        let task = task_for_pid(mach_task_self_, pid, nil)
        guard task == KERN_SUCCESS else { return 0 }
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO_64), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }
}