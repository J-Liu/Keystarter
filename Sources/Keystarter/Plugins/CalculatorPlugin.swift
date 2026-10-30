// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Darwin

/// Evaluates mathematical expressions.
/// Supports "calc 2+3" or direct input like "2+3".
/// Functions: sin, cos, tan, asin, acos, atan, sqrt, ln, log, log2, exp, abs, floor, ceil, round
/// Constants: pi, e
final class CalculatorPlugin: Plugin {

    let keyword = "calc"
    let pluginDescription = "Evaluate mathematical expressions"

    // Supported functions (lowercase for case-insensitive matching)
    private let functions: [String: (Double) -> Double] = [
        "sin": sin,
        "cos": cos,
        "tan": tan,
        "asin": asin,
        "acos": acos,
        "atan": atan,
        "sqrt": sqrt,
        "ln": log,  // natural log
        "log": log10,  // base 10
        "log2": log2,
        "exp": exp,
        "abs": { abs($0) },
        "floor": floor,
        "ceil": ceil,
        "round": round,
        "sinh": sinh,
        "cosh": cosh,
        "tanh": tanh
    ]

    // Constants
    private let constants: [String: Double] = [
        "pi": Double.pi,
        "e": M_E
    ]

    func query(_ input: String) -> [PluginResult] {
        return evaluate(input)
    }

    func matchesDirect(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Must start with digit, dot, opening paren, function name, or constant
        let firstChar = trimmed.first!
        guard firstChar.isNumber || firstChar == "." || firstChar == "(" || 
              firstChar.isLetter || firstChar == "-" else { return false }

        // Try to evaluate to see if it's valid
        return evaluate(trimmed).first?.title != "Invalid expression"
    }

    func queryDirect(_ input: String) -> [PluginResult] {
        return evaluate(input)
    }

    private func evaluate(_ expression: String) -> [PluginResult] {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return [PluginResult(title: "Enter an expression")]
        }

        // Parse and evaluate
        do {
            let result = try parseAndEvaluate(trimmed)
            let resultString = formatResult(result)

            return [PluginResult(
                title: resultString,
                subtitle: "Press Enter to copy",
                icon: NSImage(systemSymbolName: "function", accessibilityDescription: nil),
                detailText: "\(trimmed) = \(resultString)\n\n────────────────────────\nFunctions: sin, cos, tan, ln, log, sqrt...\nConstants: pi, e\nDouble-click to open Calculator",
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(resultString, forType: .string)
                    if let url = URL(string: "open -a Calculator") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )]
        } catch {
            return [PluginResult(title: "Invalid expression")]
        }
    }

    private func parseAndEvaluate(_ expr: String) throws -> Double {
        var index = expr.startIndex
        return try parseExpression(expr, &index)
    }

    // Parse expression (handles + and -)
    private func parseExpression(_ expr: String, _ index: inout String.Index) throws -> Double {
        var result = try parseTerm(expr, &index)

        while index < expr.endIndex {
            skipWhitespace(expr, &index)
            guard index < expr.endIndex else { break }

            let op = expr[index]
            if op == "+" {
                index = expr.index(after: index)
                result += try parseTerm(expr, &index)
            } else if op == "-" {
                index = expr.index(after: index)
                result -= try parseTerm(expr, &index)
            } else {
                break
            }
        }

        return result
    }

    // Parse term (handles * and /)
    private func parseTerm(_ expr: String, _ index: inout String.Index) throws -> Double {
        var result = try parsePower(expr, &index)

        while index < expr.endIndex {
            skipWhitespace(expr, &index)
            guard index < expr.endIndex else { break }

            let op = expr[index]
            if op == "*" {
                index = expr.index(after: index)
                // Check for ** (power)
                if index < expr.endIndex && expr[index] == "*" {
                    index = expr.index(after: index)
                    let exponent = try parsePower(expr, &index)
                    result = pow(result, exponent)
                } else {
                    result *= try parsePower(expr, &index)
                }
            } else if op == "/" {
                index = expr.index(after: index)
                let divisor = try parsePower(expr, &index)
                guard divisor != 0 else { throw ParseError.divisionByZero }
                result /= divisor
            } else {
                break
            }
        }

        return result
    }

    // Parse power (handles ^)
    private func parsePower(_ expr: String, _ index: inout String.Index) throws -> Double {
        var result = try parseUnary(expr, &index)

        skipWhitespace(expr, &index)
        if index < expr.endIndex && expr[index] == "^" {
            index = expr.index(after: index)
            let exponent = try parsePower(expr, &index)
            result = pow(result, exponent)
        }

        return result
    }

    // Parse unary (handles - prefix)
    private func parseUnary(_ expr: String, _ index: inout String.Index) throws -> Double {
        skipWhitespace(expr, &index)

        if index < expr.endIndex && expr[index] == "-" {
            index = expr.index(after: index)
            let value = try parsePrimary(expr, &index)
            return -value
        }

        return try parsePrimary(expr, &index)
    }

    // Parse primary (numbers, parentheses, functions, constants)
    private func parsePrimary(_ expr: String, _ index: inout String.Index) throws -> Double {
        skipWhitespace(expr, &index)

        guard index < expr.endIndex else { throw ParseError.unexpectedEnd }

        // Parentheses
        if expr[index] == "(" {
            index = expr.index(after: index)
            let result = try parseExpression(expr, &index)
            skipWhitespace(expr, &index)
            guard index < expr.endIndex && expr[index] == ")" else {
                throw ParseError.missingClosingParen
            }
            index = expr.index(after: index)
            return result
        }

        // Function or constant
        if expr[index].isLetter {
            let name = parseIdentifier(expr, &index)
            let lowerName = name.lowercased()

            // Check if it's a constant
            if let constant = constants[lowerName] {
                return constant
            }

            // Check if it's a function
            if let function = functions[lowerName] {
                skipWhitespace(expr, &index)
                guard index < expr.endIndex && expr[index] == "(" else {
                    throw ParseError.missingFunctionArgs
                }
                index = expr.index(after: index)
                let arg = try parseExpression(expr, &index)
                skipWhitespace(expr, &index)
                guard index < expr.endIndex && expr[index] == ")" else {
                    throw ParseError.missingClosingParen
                }
                index = expr.index(after: index)
                return function(arg)
            }

            throw ParseError.unknownFunction
        }

        // Number
        return try parseNumber(expr, &index)
    }

    private func parseIdentifier(_ expr: String, _ index: inout String.Index) -> String {
        let start = index
        while index < expr.endIndex && (expr[index].isLetter || expr[index].isNumber) {
            index = expr.index(after: index)
        }
        return String(expr[start..<index])
    }

    private func parseNumber(_ expr: String, _ index: inout String.Index) throws -> Double {
        let start = index

        // Integer part
        while index < expr.endIndex && expr[index].isNumber {
            index = expr.index(after: index)
        }

        // Decimal part
        if index < expr.endIndex && expr[index] == "." {
            index = expr.index(after: index)
            while index < expr.endIndex && expr[index].isNumber {
                index = expr.index(after: index)
            }
        }

        // Exponent
        if index < expr.endIndex && (expr[index] == "e" || expr[index] == "E") {
            index = expr.index(after: index)
            if index < expr.endIndex && (expr[index] == "+" || expr[index] == "-") {
                index = expr.index(after: index)
            }
            while index < expr.endIndex && expr[index].isNumber {
                index = expr.index(after: index)
            }
        }

        let numStr = String(expr[start..<index])
        guard let num = Double(numStr) else {
            throw ParseError.invalidNumber
        }

        return num
    }

    private func skipWhitespace(_ expr: String, _ index: inout String.Index) {
        while index < expr.endIndex && expr[index].isWhitespace {
            index = expr.index(after: index)
        }
    }

    private func formatResult(_ num: Double) -> String {
        if num.isNaN || num.isInfinite {
            return "Undefined"
        }
        if num == num.rounded() && abs(num) < 1e15 {
            return String(format: "%.0f", num)
        }
        return String(format: "%g", num)
    }

    enum ParseError: Error {
        case unexpectedEnd
        case invalidNumber
        case missingClosingParen
        case missingFunctionArgs
        case unknownFunction
        case divisionByZero
    }
}
