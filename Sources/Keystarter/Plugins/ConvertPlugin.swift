// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Converts between units: currency, length, weight, temperature, area, volume, speed.
/// Usage: "100 usd to cny", "5 km to miles", "30 c to f"
final class ConvertPlugin: Plugin {

    let keyword = ""
    let pluginDescription = "Convert between units (currency, length, weight, temperature, etc.)"

    // MARK: - Currency

    private var exchangeRates: [String: Double] = [:]
    private var ratesLastFetch: Date?
    private let ratesCacheDuration: TimeInterval = 3600 // 1 hour

    // MARK: - Unit Definitions

    private enum UnitCategory {
        case length, weight, temperature, area, volume, speed, currency
    }

    private let units: [String: (category: UnitCategory, toBase: Double)] = [
        // Length (base: meter)
        "m": (.length, 1),
        "meter": (.length, 1),
        "meters": (.length, 1),
        "km": (.length, 1000),
        "kilometer": (.length, 1000),
        "kilometers": (.length, 1000),
        "cm": (.length, 0.01),
        "centimeter": (.length, 0.01),
        "centimeters": (.length, 0.01),
        "mm": (.length, 0.001),
        "millimeter": (.length, 0.001),
        "millimeters": (.length, 0.001),
        "mi": (.length, 1609.344),
        "mile": (.length, 1609.344),
        "miles": (.length, 1609.344),
        "ft": (.length, 0.3048),
        "foot": (.length, 0.3048),
        "feet": (.length, 0.3048),
        "in": (.length, 0.0254),
        "inch": (.length, 0.0254),
        "inches": (.length, 0.0254),
        "yd": (.length, 0.9144),
        "yard": (.length, 0.9144),
        "yards": (.length, 0.9144),

        // Weight (base: kilogram)
        "kg": (.weight, 1),
        "kilogram": (.weight, 1),
        "kilograms": (.weight, 1),
        "g": (.weight, 0.001),
        "gram": (.weight, 0.001),
        "grams": (.weight, 0.001),
        "mg": (.weight, 0.000001),
        "milligram": (.weight, 0.000001),
        "milligrams": (.weight, 0.000001),
        "lb": (.weight, 0.453592),
        "lbs": (.weight, 0.453592),
        "pound": (.weight, 0.453592),
        "pounds": (.weight, 0.453592),
        "oz": (.weight, 0.0283495),
        "ounce": (.weight, 0.0283495),
        "ounces": (.weight, 0.0283495),

        // Temperature (special handling)
        "c": (.temperature, 0),
        "celsius": (.temperature, 0),
        "f": (.temperature, 0),
        "fahrenheit": (.temperature, 0),
        "k": (.temperature, 0),
        "kelvin": (.temperature, 0),

        // Area (base: square meter)
        "m2": (.area, 1),
        "sqm": (.area, 1),
        "km2": (.area, 1000000),
        "sqkm": (.area, 1000000),
        "cm2": (.area, 0.0001),
        "sqcm": (.area, 0.0001),
        "mi2": (.area, 2589988.11),
        "sqmi": (.area, 2589988.11),
        "ft2": (.area, 0.092903),
        "sqft": (.area, 0.092903),
        "acre": (.area, 4046.86),
        "acres": (.area, 4046.86),
        "ha": (.area, 10000),
        "hectare": (.area, 10000),
        "hectares": (.area, 10000),

        // Volume (base: liter)
        "l": (.volume, 1),
        "liter": (.volume, 1),
        "liters": (.volume, 1),
        "ml": (.volume, 0.001),
        "milliliter": (.volume, 0.001),
        "milliliters": (.volume, 0.001),
        "gal": (.volume, 3.78541),
        "gallon": (.volume, 3.78541),
        "gallons": (.volume, 3.78541),
        "qt": (.volume, 0.946353),
        "quart": (.volume, 0.946353),
        "quarts": (.volume, 0.946353),
        "pt": (.volume, 0.473176),
        "pint": (.volume, 0.473176),
        "pints": (.volume, 0.473176),
        "cup": (.volume, 0.236588),
        "cups": (.volume, 0.236588),
        "floz": (.volume, 0.0295735),
        "oz_fl": (.volume, 0.0295735),

        // Speed (base: m/s)
        "m/s": (.speed, 1),
        "mps": (.speed, 1),
        "km/h": (.speed, 0.277778),
        "kph": (.speed, 0.277778),
        "mph": (.speed, 0.44704),
        "ft/s": (.speed, 0.3048),
        "fps": (.speed, 0.3048),
        "knot": (.speed, 0.514444),
        "knots": (.speed, 0.514444),
    ]

    // MARK: - Plugin Protocol

    func matchesDirect(_ input: String) -> Bool {
        return parseConversion(input) != nil
    }

    func queryDirect(_ input: String) -> [PluginResult] {
        guard let (value, fromUnit, toUnit) = parseConversion(input) else {
            return []
        }

        let fromLower = fromUnit.lowercased()
        let toLower = toUnit.lowercased()

        // Check if currency
        if isCurrency(fromLower) || isCurrency(toLower) {
            return convertCurrency(value: value, from: fromLower, to: toLower)
        }

        // Physical unit conversion
        guard let fromInfo = units[fromLower], let toInfo = units[toLower] else {
            return [PluginResult(title: "Unknown unit", icon: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil))]
        }

        guard fromInfo.category == toInfo.category else {
            return [PluginResult(title: "Incompatible units", icon: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil))]
        }

        let result: Double
        if fromInfo.category == .temperature {
            result = convertTemperature(value: value, from: fromLower, to: toLower)
        } else {
            // Convert to base, then to target
            let baseValue = value * fromInfo.toBase
            result = baseValue / toInfo.toBase
        }

        let resultString = formatNumber(result)
        let displayString = "\(resultString) \(toUnit)"

        return [PluginResult(
            title: displayString,
            subtitle: "Press Enter to copy",
            icon: NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil),
            action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayString, forType: .string)
            }
        )]
    }

    func query(_ input: String) -> [PluginResult] {
        return []
    }

    // MARK: - Parsing

    private func parseConversion(_ input: String) -> (Double, String, String)? {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()

        // Pattern: "100 usd to cny" or "5km to miles" or "30 c to f"
        let patterns = [
            "^([0-9.]+)\\s*([a-z2_/]+)\\s+(?:to|in)\\s+([a-z2_/]+)$",
            "^([0-9.]+)\\s*([a-z2_/]+)\\s+([a-z2_/]+)$"
        ]

        for pattern in patterns {
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                let match = String(trimmed[range])
                let parts = match.split(separator: " ").map { String($0) }

                if parts.count >= 3, let value = Double(parts[0]) {
                    let fromUnit = parts[1]
                    let toUnit = parts.count > 3 ? parts[3] : parts[2]
                    return (value, fromUnit, toUnit)
                }
            }
        }

        return nil
    }

    // MARK: - Currency

    private func isCurrency(_ code: String) -> Bool {
        let currencies = ["usd", "cny", "eur", "gbp", "jpy", "krw", "hkd", "sgd", "aud", "cad", "chf", "nzd", "thb", "inr", "rub", "brl", "mxn", "zar", "try", "pln", "sek", "nok", "dkk", "ils", "clp", "php", "idr", "myr", "vnd"]
        return currencies.contains(code)
    }

    private func convertCurrency(value: Double, from: String, to: String) -> [PluginResult] {
        // Check if we have cached rates
        if let lastFetch = ratesLastFetch,
           Date().timeIntervalSince(lastFetch) < ratesCacheDuration,
           !exchangeRates.isEmpty {
            return performCurrencyConversion(value: value, from: from, to: to)
        }

        // Fetch new rates
        fetchExchangeRates { [weak self] success in
            guard let self = self else { return }
            if success {
                _ = self.performCurrencyConversion(value: value, from: from, to: to)
                DispatchQueue.main.async {
                    // Trigger UI refresh
                    NotificationCenter.default.post(name: .currencyRatesUpdated, object: nil)
                }
            }
        }

        return [PluginResult(
            title: "Fetching exchange rates...",
            icon: NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        )]
    }

    private func performCurrencyConversion(value: Double, from: String, to: String) -> [PluginResult] {
        guard let fromRate = exchangeRates[from.uppercased()] else {
            return [PluginResult(title: "Unknown currency: \(from.uppercased())", icon: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil))]
        }

        guard let toRate = exchangeRates[to.uppercased()] else {
            return [PluginResult(title: "Unknown currency: \(to.uppercased())", icon: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil))]
        }

        // Convert to USD first, then to target
        let usdValue = value / fromRate
        let result = usdValue * toRate

        let resultString = formatNumber(result)
        let displayString = "\(resultString) \(to.uppercased())"

        return [PluginResult(
            title: displayString,
            subtitle: "Press Enter to copy",
            icon: NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: nil),
            action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayString, forType: .string)
            }
        )]
    }

    private func fetchExchangeRates(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            completion(false)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                completion(false)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rates = json["rates"] as? [String: Double] {
                    self.exchangeRates = rates
                    self.ratesLastFetch = Date()
                    completion(true)
                } else {
                    completion(false)
                }
            } catch {
                completion(false)
            }
        }
        task.resume()
    }

    // MARK: - Temperature

    private func convertTemperature(value: Double, from: String, to: String) -> Double {
        // Convert to Celsius first
        let celsius: Double
        switch from {
        case "c", "celsius":
            celsius = value
        case "f", "fahrenheit":
            celsius = (value - 32) * 5 / 9
        case "k", "kelvin":
            celsius = value - 273.15
        default:
            return 0
        }

        // Convert from Celsius to target
        switch to {
        case "c", "celsius":
            return celsius
        case "f", "fahrenheit":
            return celsius * 9 / 5 + 32
        case "k", "kelvin":
            return celsius + 273.15
        default:
            return 0
        }
    }

    // MARK: - Formatting

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        } else if abs(value) < 0.01 || abs(value) >= 10000 {
            return String(format: "%.2e", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let currencyRatesUpdated = Notification.Name("currencyRatesUpdated")
}
