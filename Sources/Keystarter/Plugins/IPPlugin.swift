// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Darwin

/// Queries local and public IP addresses.
/// Usage: "ip" shows local and public IPs
final class IPPlugin: Plugin {

    let keyword = ""
    let pluginDescription = "Query local and public IP addresses"

    // Cache public IP for 5 minutes (IP rarely changes)
    private let cacheKey = "keystarter.publicIP.cache"
    private let cacheTimeKey = "keystarter.publicIP.cacheTime"
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    init() {
        // Pre-fetch public IP in background on plugin initialization
        prefetchPublicIP()
    }

    private func getCachedIP() -> String? {
        guard let ip = UserDefaults.standard.string(forKey: cacheKey),
              let timeInterval = UserDefaults.standard.object(forKey: cacheTimeKey) as? TimeInterval else {
            log("Cache miss: no data in UserDefaults")
            return nil
        }
        let cacheTime = Date(timeIntervalSince1970: timeInterval)
        let age = Date().timeIntervalSince(cacheTime)
        if age < cacheDuration {
            log("Cache hit: IP=\(ip), age=\(Int(age))s")
            return ip
        }
        log("Cache expired: IP=\(ip), age=\(Int(age))s")
        return nil
    }

    private func setCachedIP(_ ip: String) {
        UserDefaults.standard.set(ip, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimeKey)
        UserDefaults.standard.synchronize()  // Ensure immediate save
        log("Cache saved: IP=\(ip)")
    }
    
    private func log(_ message: String) {
        guard LogSettings.shared.launcherLogEnabled else { return }
        LogSettings.write("[IPPlugin] \(message)", to: LogSettings.shared.launcherLogPath)
    }

    /// Pre-fetch public IP in background if cache is missing or expired
    private func prefetchPublicIP() {
        // Only fetch if cache is missing or expired
        guard getCachedIP() == nil else { return }

        fetchPublicIP { _ in
            // Cache is updated in fetchPublicIP callback
        }
    }

    func matchesDirect(_ input: String) -> Bool {
        return input.trimmingCharacters(in: .whitespaces).lowercased() == "ip"
    }

    func queryDirect(_ input: String) -> [PluginResult] {
        var results: [PluginResult] = []

        // Local IPs
        let localIPs = getLocalIPs()
        for (interface, ip) in localIPs {
            results.append(PluginResult(
                title: ip,
                subtitle: "Local IP (\(interface))",
                icon: NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            ))
        }

        if localIPs.isEmpty {
            results.append(PluginResult(
                title: "No local IP found",
                icon: NSImage(systemSymbolName: "network.slash", accessibilityDescription: nil)
            ))
        }

        // Public IP - use cache if available
        if let cached = getCachedIP() {
            // Cache hit - return immediately
            results.append(PluginResult(
                title: cached,
                subtitle: "Public IP (cached)",
                icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cached, forType: .string)
                }
            ))
        } else {
            // Cache miss - trigger background fetch and show placeholder
            // Next query will have cached value
            prefetchPublicIP()
            results.append(PluginResult(
                title: "Fetching public IP...",
                subtitle: "Please try again in a moment",
                icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            ))
        }

        return results
    }

    func query(_ input: String) -> [PluginResult] {
        return []
    }

    private func getLocalIPs() -> [(String, String)] {
        var results: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return results
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while ptr.pointee.ifa_next != nil {
            let interface = ptr.pointee

            // Skip if not up or not IPv4
            let flags = Int32(interface.ifa_flags)
            guard (flags & (IFF_UP | IFF_RUNNING)) != 0 else {
                ptr = interface.ifa_next!
                continue
            }

            let addr = interface.ifa_addr
            guard addr?.pointee.sa_family == UInt8(AF_INET) else {
                ptr = interface.ifa_next!
                continue
            }

            // Get interface name
            let name = String(cString: interface.ifa_name)

            // Skip loopback
            guard name != "lo0" else {
                ptr = interface.ifa_next!
                continue
            }

            // Convert address to string
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                          &hostname, socklen_t(hostname.count),
                          nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                results.append((name, ip))
            }

            ptr = interface.ifa_next!
        }

        return results
    }

    private func fetchPublicIP(completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.ipify.org") else {
            completion("Failed to fetch")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // 5 second timeout

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                // Return cached value if available, even if stale
                if let cached = self?.getCachedIP() {
                    completion(cached)
                } else {
                    completion("Failed to fetch")
                }
                return
            }

            if let ip = String(data: data, encoding: .utf8) {
                let trimmedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
                // Update cache
                self?.setCachedIP(trimmedIP)
                completion(trimmedIP)
            } else {
                completion("Failed to parse")
            }
        }
        task.resume()
    }
}
