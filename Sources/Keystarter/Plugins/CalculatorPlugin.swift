// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Evaluates mathematical expressions.
/// Supports "calc 2+3" or direct input like "2+3".
final class CalculatorPlugin: Plugin {

    let keyword = "calc"
    let pluginDescription = "Evaluate mathematical expressions"

    func query(_ input: String) -> [PluginResult] {
        return evaluate(input)
    }

    func matchesDirect(_ input: String) -> Bool {
        // Check if input looks like a math expression
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Must contain at least one operator
        let operators: Set<Character> = ["+", "-", "*", "/", "^", "(", ")"]
        let hasOperator = trimmed.contains(where: { operators.contains($0) })
        guard hasOperator else { return false }

        // Must start with digit, dot, or opening paren
        let firstChar = trimmed.first!
        guard firstChar.isNumber || firstChar == "." || firstChar == "(" else { return false }

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

        // Sanitize: only allow numbers, operators, dots, spaces, parens
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^() ")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return [PluginResult(title: "Invalid expression")]
        }

        // Replace ^ with ** for NSExpression power operator
        let normalized = trimmed.replacingOccurrences(of: "^", with: "**")

        let expr = NSExpression(format: normalized)
        guard let result = expr.expressionValue(with: nil, context: nil) else {
            return [PluginResult(title: "Invalid expression")]
        }

        // Format result
        let resultString: String
        if let num = result as? Double {
            // Show as integer if it's a whole number
            if num == num.rounded() && abs(num) < 1e15 {
                resultString = String(format: "%.0f", num)
            } else {
                resultString = String(format: "%g", num)
            }
        } else if let num = result as? Int {
            resultString = String(num)
        } else {
            resultString = "\(result)"
        }

        return [PluginResult(
            title: resultString,
            subtitle: "Press Enter to copy",
            icon: NSImage(systemSymbolName: "function", accessibilityDescription: nil),
            action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(resultString, forType: .string)
            }
        )]
    }
}
