// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Converts hex color codes to RGB and HSL values.
/// Usage: "#FF8800" or "#F80"
final class ColorPlugin: Plugin {

    let keyword = ""
    let pluginDescription = "Convert hex color codes to RGB and HSL"

    func matchesDirect(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        return isHexColor(trimmed)
    }

    func queryDirect(_ input: String) -> [PluginResult] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard isHexColor(trimmed) else { return [] }

        let (r, g, b) = hexToRGB(trimmed)
        let (h, s, l) = rgbToHSL(r, g, b)

        var results: [PluginResult] = []

        // RGB
        let rgbString = "RGB(\(r), \(g), \(b))"
        results.append(PluginResult(
            title: rgbString,
            subtitle: "Press Enter to copy RGB",
            icon: NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil),
            action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rgbString, forType: .string)
            }
        ))

        // HSL
        let hslString = "HSL(\(h), \(s)%, \(l)%)"
        results.append(PluginResult(
            title: hslString,
            subtitle: "Press Enter to copy HSL",
            icon: NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil),
            action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hslString, forType: .string)
            }
        ))

        // Hex (normalized)
        let hexString = normalizeHex(trimmed)
        results.append(PluginResult(
            title: hexString,
            subtitle: "Press Enter to copy hex",
            icon: NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil),
            action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hexString, forType: .string)
            }
        ))

        return results
    }

    func query(_ input: String) -> [PluginResult] {
        return []
    }

    private func isHexColor(_ input: String) -> Bool {
        let pattern = "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$"
        return input.range(of: pattern, options: .regularExpression) != nil
    }

    private func hexToRGB(_ hex: String) -> (Int, Int, Int) {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        var hexValue: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&hexValue)

        if clean.count == 3 {
            // #F80 -> #FF8800
            let r = Int((hexValue >> 8) & 0xF) * 17
            let g = Int((hexValue >> 4) & 0xF) * 17
            let b = Int(hexValue & 0xF) * 17
            return (r, g, b)
        } else {
            // #FF8800
            let r = Int((hexValue >> 16) & 0xFF)
            let g = Int((hexValue >> 8) & 0xFF)
            let b = Int(hexValue & 0xFF)
            return (r, g, b)
        }
    }

    private func rgbToHSL(_ r: Int, _ g: Int, _ b: Int) -> (Int, Int, Int) {
        let rNorm = Double(r) / 255.0
        let gNorm = Double(g) / 255.0
        let bNorm = Double(b) / 255.0

        let maxVal = max(rNorm, gNorm, bNorm)
        let minVal = min(rNorm, gNorm, bNorm)
        let delta = maxVal - minVal

        var h = 0.0
        var s = 0.0
        let l = (maxVal + minVal) / 2.0

        if delta != 0 {
            s = l > 0.5 ? delta / (2.0 - maxVal - minVal) : delta / (maxVal + minVal)

            if maxVal == rNorm {
                h = (gNorm - bNorm) / delta + (gNorm < bNorm ? 6 : 0)
            } else if maxVal == gNorm {
                h = (bNorm - rNorm) / delta + 2
            } else {
                h = (rNorm - gNorm) / delta + 4
            }
            h *= 60
        }

        return (Int(h.rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    private func normalizeHex(_ hex: String) -> String {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        if clean.count == 3 {
            // #F80 -> #FF8800
            let r = String(clean[clean.startIndex])
            let g = String(clean[clean.index(clean.startIndex, offsetBy: 1)])
            let b = String(clean[clean.index(clean.startIndex, offsetBy: 2)])
            return "#\(r)\(r)\(g)\(g)\(b)\(b)".uppercased()
        } else {
            return "#\(clean)".uppercased()
        }
    }
}
