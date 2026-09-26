// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AppKit

/// Process type classification.
enum ProcessType {
    case app
    case systemService
    case userService
    case unknown
}

/// Process information structure.
struct AppProcessInfo {
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: UInt64
    let isApp: Bool
    let icon: NSImage?
    let user: String
    let threads: Int
    let processType: ProcessType
}

/// Core CPU usage with user/system breakdown.
struct CoreUsage {
    let user: Double
    let system: Double
    let total: Double
}

/// Provider for process and system information.
final class ProcessInfoProvider {
    
    static let shared = ProcessInfoProvider()
    
    private init() {}
    
    // MARK: - CPU Usage
    
    private var prevTotalTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0
    private var prevCoreTotal: [UInt64] = []
    private var prevCoreUser: [UInt64] = []
    private var prevCoreSystem: [UInt64] = []
    
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
        
        let totalDelta = totalTicks > prevTotalTicks ? totalTicks - prevTotalTicks : 0
        let idleDelta = idle > prevIdleTicks ? idle - prevIdleTicks : 0
        
        prevTotalTicks = totalTicks
        prevIdleTicks = idle
        
        if totalDelta == 0 { return 0 }
        return Double(totalDelta - idleDelta) / Double(totalDelta) * 100.0
    }
    
    /// Get per-core CPU usage with user/system breakdown.
    func getPerCoreCPUUsage() -> [CoreUsage] {
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
            return Array(repeating: CoreUsage(user: 0, system: 0, total: 0), count: ProcessInfo.processInfo.processorCount)
        }
        
        var usages: [CoreUsage] = []
        let numCores = Int(numCPUs)
        let ticksPerCore = Int(CPU_STATE_MAX)
        var currentTotal: [UInt64] = []
        var currentUser: [UInt64] = []
        var currentSystem: [UInt64] = []
        
        for i in 0..<numCores {
            let offset = i * ticksPerCore
            let user = UInt64(info[offset + Int(CPU_STATE_USER)])
            let system = UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(info[offset + Int(CPU_STATE_NICE)])
            let total = user + system + idle + nice
            
            currentTotal.append(total)
            currentUser.append(user + nice)  // user includes nice
            currentSystem.append(system)
            
            let prevTotal = i < prevCoreTotal.count ? prevCoreTotal[i] : 0
            let prevUser = i < prevCoreUser.count ? prevCoreUser[i] : 0
            let prevSystem = i < prevCoreSystem.count ? prevCoreSystem[i] : 0
            
            let totalDelta = total > prevTotal ? total - prevTotal : 0
            let userDelta = (user + nice) > prevUser ? (user + nice) - prevUser : 0
            let systemDelta = system > prevSystem ? system - prevSystem : 0
            
            if totalDelta > 0 {
                let userPct = Double(userDelta) / Double(totalDelta) * 100.0
                let systemPct = Double(systemDelta) / Double(totalDelta) * 100.0
                usages.append(CoreUsage(user: userPct, system: systemPct, total: userPct + systemPct))
            } else {
                usages.append(CoreUsage(user: 0, system: 0, total: 0))
            }
        }
        
        prevCoreTotal = currentTotal
        prevCoreUser = currentUser
        prevCoreSystem = currentSystem
        
        // Free memory
        let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        
        return usages
    }
    
    // MARK: - Memory Usage
    
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
    
    /// Get list of processes with child processes aggregated into apps.
    func getProcessesByCPU(limit: Int = 100) -> [AppProcessInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs = Set<Int32>()
        var appNames: [Int32: String] = [:]
        var appIcons: [Int32: NSImage] = [:]
        
        for app in runningApps {
            // Include all apps with bundle URL, not just regular ones
            guard let url = app.bundleURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let pid = app.processIdentifier
            // Only mark regular apps as user-facing
            if app.activationPolicy == .regular {
                appPIDs.insert(pid)
            }
            appNames[pid] = name
            if let icon = app.icon {
                appIcons[pid] = icon
            }
        }
        
        // Get all processes with parent PID
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 3, &procList, &size, nil, 0)
        
        // Build process tree
        var parentMap: [Int32: Int32] = [:]
        var processCPU: [Int32: Double] = [:]
        var processMemory: [Int32: UInt64] = [:]
        var processNames: [Int32: String] = [:]
        var processUsers: [Int32: String] = [:]
        var processThreads: [Int32: Int] = [:]
        
        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            let ppid = proc.kp_eproc.e_ppid
            let uid = proc.kp_eproc.e_ucred.cr_uid
            parentMap[pid] = ppid
            
            // Get process name from path or comm
            var name: String
            if let path = getProcessPath(pid: pid) {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
                name = String(cString: withUnsafePointer(to: proc.kp_proc.p_comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) { $0 }
                })
            }
            // Filter out invalid characters (keep only printable ASCII: 32-126)
            name = name.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.map { Character($0) }.map { String($0) }.joined()
            if name.isEmpty { name = "process" }
            processNames[pid] = appNames[pid] ?? name
            processCPU[pid] = getProcessCPUUsage(pid: pid)
            processMemory[pid] = getProcessMemoryUsage(pid: pid)
            processUsers[pid] = getProcessUser(uid: uid)
            processThreads[pid] = getProcessThreads(pid: pid)
        }
        
        // Aggregate child processes into apps
        var aggregatedCPU: [Int32: Double] = [:]
        var aggregatedMemory: [Int32: UInt64] = [:]
        
        for (pid, _) in processCPU {
            // Find ancestor app
            var currentPid = pid
            var foundAppPid: Int32? = appPIDs.contains(pid) ? pid : nil
            var visited = Set<Int32>()
            
            while foundAppPid == nil, let ppid = parentMap[currentPid], !visited.contains(ppid) {
                visited.insert(ppid)
                if appPIDs.contains(ppid) {
                    foundAppPid = ppid
                    break
                }
                currentPid = ppid
            }
            
            if let appPid = foundAppPid {
                aggregatedCPU[appPid, default: 0] += processCPU[pid] ?? 0
                aggregatedMemory[appPid, default: 0] += processMemory[pid] ?? 0
            }
        }
        
        // Build result: apps with aggregated values
        var result: [AppProcessInfo] = []
        
        for pid in appPIDs {
            let user = processUsers[pid] ?? "?"
            let threads = processThreads[pid] ?? 0
            result.append(AppProcessInfo(
                pid: pid,
                name: appNames[pid] ?? "Unknown",
                cpuUsage: aggregatedCPU[pid] ?? 0,
                memoryUsage: aggregatedMemory[pid] ?? 0,
                isApp: true,
                icon: appIcons[pid],
                user: user,
                threads: threads,
                processType: .app
            ))
        }
        
        // Add standalone processes (not belonging to any app)
        for (pid, cpu) in processCPU {
            var belongsToApp = false
            var currentPid = pid
            var visited = Set<Int32>()
            
            if appPIDs.contains(pid) { belongsToApp = true }
            
            while !belongsToApp, let ppid = parentMap[currentPid], !visited.contains(ppid) {
                visited.insert(ppid)
                if appPIDs.contains(ppid) { belongsToApp = true; break }
                currentPid = ppid
            }
            
            if !belongsToApp {
                let user = processUsers[pid] ?? "?"
                let threads = processThreads[pid] ?? 0
                let ppid = parentMap[pid] ?? 0
                
                // Determine process type
                let processType: ProcessType
                if user == "root" || ppid == 1 {
                    processType = .systemService
                } else {
                    processType = .userService
                }
                
                result.append(AppProcessInfo(
                    pid: pid,
                    name: processNames[pid] ?? "Unknown",
                    cpuUsage: cpu,
                    memoryUsage: processMemory[pid] ?? 0,
                    isApp: false,
                    icon: nil,
                    user: user,
                    threads: threads,
                    processType: processType
                ))
            }
        }
        
        result.sort { $0.cpuUsage > $1.cpuUsage }
        return Array(result.prefix(limit))
    }
    
    func getProcessesByMemory(limit: Int = 100) -> [AppProcessInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var appPIDs = Set<Int32>()
        var appNames: [Int32: String] = [:]
        var appIcons: [Int32: NSImage] = [:]
        
        for app in runningApps {
            // Include all apps with bundle URL
            guard let url = app.bundleURL else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let pid = app.processIdentifier
            // Only mark regular apps as user-facing
            if app.activationPolicy == .regular {
                appPIDs.insert(pid)
            }
            appNames[pid] = name
            if let icon = app.icon {
                appIcons[pid] = icon
            }
        }
        
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        sysctl(&mib, 3, nil, &size, nil, 0)
        
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 3, &procList, &size, nil, 0)
        
        var processes: [AppProcessInfo] = []
        
        for proc in procList {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            
            // Get process name from path or comm
            var name: String
            if let path = getProcessPath(pid: pid) {
                name = URL(fileURLWithPath: path).lastPathComponent
            } else {
                name = String(cString: withUnsafePointer(to: proc.kp_proc.p_comm) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN + 1)) { $0 }
                })
            }
            // Filter out invalid characters (keep only printable ASCII: 32-126)
            name = name.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.map { Character($0) }.map { String($0) }.joined()
            if name.isEmpty { name = "process" }
            
            let isApp = appPIDs.contains(pid)
            let uid = proc.kp_eproc.e_ucred.cr_uid
            let user = getProcessUser(uid: uid)
            let threads = getProcessThreads(pid: pid)
            let ppid = proc.kp_eproc.e_ppid
            
            let processType: ProcessType
            if isApp {
                processType = .app
            } else if user == "root" || ppid == 1 {
                processType = .systemService
            } else {
                processType = .userService
            }
            
            processes.append(AppProcessInfo(
                pid: pid,
                name: appNames[pid] ?? name,
                cpuUsage: getProcessCPUUsage(pid: pid),
                memoryUsage: getProcessMemoryUsage(pid: pid),
                isApp: isApp,
                icon: appIcons[pid],
                user: user,
                threads: threads,
                processType: processType
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
        
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let timebaseToNs = Double(timebase.numer) / Double(timebase.denom)
        
        let userTime = rusage.ri_user_time
        let systemTime = rusage.ri_system_time
        let total = userTime + systemTime
        
        procCPULock.lock()
        defer { procCPULock.unlock() }
        
        let now = Date()
        if let prev = previousProcCPU[pid] {
            let elapsed = now.timeIntervalSince(prev.time)
            if elapsed > 0 {
                let prevTotal = prev.user + prev.system
                let delta = total > prevTotal ? Double(total - prevTotal) : 0
                let deltaNs = delta * timebaseToNs
                let cpuTimeSeconds = deltaNs / 1_000_000_000.0
                let usage = (cpuTimeSeconds / elapsed) * 100.0
                
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
    
    private func getProcessUser(uid: uid_t) -> String {
        // Get username from UID
        if let pw = getpwuid(uid) {
            return String(cString: pw.pointee.pw_name)
        }
        return "uid:\(uid)"
    }
    
    private func getProcessThreads(pid: Int32) -> Int {
        // Use proc_pidinfo to get thread info
        var info = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard size > 0 else { return 0 }
        return Int(info.pti_threadnum)
    }
    
    private func getProcessPath(pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN (4096)
        let maxPathSize = 4096
        var path = [CChar](repeating: 0, count: maxPathSize)
        let count = proc_pidpath(pid, &path, UInt32(maxPathSize))
        guard count > 0 else { return nil }
        return String(cString: path)
    }
}