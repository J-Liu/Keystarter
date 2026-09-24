// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Darwin

/// Queries local and public IP addresses.
/// Usage: "ip" shows local and public IPs
final class IPPlugin: Plugin {

    let keyword = ""
    let pluginDescription = "Query local and public IP addresses"

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

        // Public IP (async)
        results.append(PluginResult(
            title: "Loading public IP...",
            subtitle: "Fetching from external service",
            icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        ))

        // Fetch public IP asynchronously
        fetchPublicIP { publicIP in
            DispatchQueue.main.async {
                // Update the last result with public IP
                if let index = results.lastIndex(where: { $0.title == "Loading public IP..." }) {
                    results[index] = PluginResult(
                        title: publicIP,
                        subtitle: "Public IP",
                        icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                        action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(publicIP, forType: .string)
                        }
                    )
                }
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

    private func fetchPublicIP(completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.ipify.org") else {
            completion("Failed to fetch")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion("Failed to fetch")
                return
            }

            if let ip = String(data: data, encoding: .utf8) {
                completion(ip.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                completion("Failed to parse")
            }
        }
        task.resume()
    }
}
