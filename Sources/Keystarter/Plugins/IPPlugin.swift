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
        // No prefetch - IP plugin always fetches fresh on query
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

        // Public IP - always fetch fresh (no cache), but update cache if changed
        let cachedIP = getCachedIP()
        results.append(PluginResult(
            title: "Fetching public IP...",
            subtitle: "Please try again in a moment",
            icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        ))
        
        // Fetch fresh IP in background
        fetchPublicIP { [weak self] ip in
            guard let self = self else { return }
            // Update cache if different from cached value
            if ip != cachedIP {
                self.setCachedIP(ip)
            }
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

    private let ipServices = [
        "https://api.ipify.org",
        "https://icanhazip.com",
        "https://ipecho.net/plain",
        "https://ifconfig.me"
    ]

    private func fetchPublicIP(completion: @escaping (String) -> Void) {
        fetchFromServices(index: 0, completion: completion)
    }
    
    private func fetchFromServices(index: Int, completion: @escaping (String) -> Void) {
        guard index < ipServices.count else {
            log("All IP services failed")
            // Return cached value if available, even if stale
            if let cached = getCachedIP() {
                completion(cached)
            } else {
                completion("Failed to fetch")
            }
            return
        }
        
        let serviceURL = ipServices[index]
        log("Fetching public IP from \(serviceURL)")
        
        guard let url = URL(string: serviceURL) else {
            log("Failed to create URL: \(serviceURL)")
            fetchFromServices(index: index + 1, completion: completion)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // 5 second timeout

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            guard let data = data, error == nil else {
                self.log("Network error from \(serviceURL): \(error?.localizedDescription ?? "unknown")")
                // Try next service
                self.fetchFromServices(index: index + 1, completion: completion)
                return
            }

            if let ip = String(data: data, encoding: .utf8) {
                let trimmedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
                self.log("Fetched IP from \(serviceURL): \(trimmedIP)")
                // Update cache
                self.setCachedIP(trimmedIP)
                completion(trimmedIP)
            } else {
                self.log("Failed to parse response from \(serviceURL)")
                self.fetchFromServices(index: index + 1, completion: completion)
            }
        }
        task.resume()
    }
}
