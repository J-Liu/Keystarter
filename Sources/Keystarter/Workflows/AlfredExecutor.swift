// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AppKit

/// Alfred Script Filter JSON output format.
struct AlfredScriptFilterOutput: Decodable {
    let items: [AlfredItem]

    struct AlfredItem: Decodable {
        let uid: String?
        let title: String
        let subtitle: String?
        let arg: String?
        let icon: AlfredIcon?
        let variables: [String: String]?

        struct AlfredIcon: Decodable {
            let path: String?
            let type: String?  // "fileicon" or "image"
        }
    }
}

/// Executes Alfred workflow nodes.
final class AlfredWorkflowExecutor {

    private let workflow: AlfredWorkflow
    private var variables: [String: String] = [:]

    init(workflow: AlfredWorkflow) {
        self.workflow = workflow
    }

    /// Run a Script Filter and return results.
    func runScriptFilter(uid: String, input: String) -> AlfredScriptFilterOutput? {
        guard let obj = workflow.objects[uid] else { return nil }
        guard obj.type == "alfred.workflow.input.scriptfilter" else { return nil }

        let script = obj.config["script"] as? String ?? ""
        let scriptType = obj.config["scriptfiletype"] as? String ?? "bash"

        // Set environment variables
        var env = ProcessInfo.processInfo.environment
        env["alfred_workflow_name"] = workflow.name
        env["alfred_workflow_bundleid"] = workflow.bundleId
        env["alfred_workflow_data"] = workflow.path
        env["alfred_workflow_version"] = ""
        env["alfred_workflow_uid"] = workflow.bundleId
        for (key, value) in variables {
            env[key] = value
        }

        // Execute script
        let result = runScript(script: script, type: scriptType, input: input, env: env)
        guard let data = result.data(using: .utf8) else { return nil }

        return try? JSONDecoder().decode(AlfredScriptFilterOutput.self, from: data)
    }

    /// Run a script node.
    func runScript(uid: String, input: String) {
        guard let obj = workflow.objects[uid] else { return }

        let script = obj.config["script"] as? String ?? ""
        let scriptType = obj.config["scriptfiletype"] as? String ?? "bash"

        var env = ProcessInfo.processInfo.environment
        env["alfred_workflow_name"] = workflow.name
        env["alfred_workflow_bundleid"] = workflow.bundleId
        env["alfred_workflow_data"] = workflow.path
        for (key, value) in variables {
            env[key] = value
        }

        _ = runScript(script: script, type: scriptType, input: input, env: env)
    }

    /// Open URL node.
    func openURL(uid: String, input: String) {
        guard let obj = workflow.objects[uid] else { return }
        var urlString = obj.config["url"] as? String ?? ""

        // Replace {query} with input
        urlString = urlString.replacingOccurrences(of: "{query}", with: input)

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Copy to clipboard node.
    func copyToClipboard(uid: String, input: String) {
        guard let obj = workflow.objects[uid] else { return }
        let text = obj.config["clipboardtext"] as? String ?? input

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func runScript(script: String, type: String, input: String, env: [String: String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")

        // Build the script with input
        let fullScript: String
        if type == "python" || type == "python3" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            fullScript = script
        } else if type == "php" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/php")
            fullScript = script
        } else if type == "ruby" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
            fullScript = script
        } else {
            // bash/sh - default
            fullScript = script
        }

        // Replace {query} with escaped input
        let escapedInput = input.replacingOccurrences(of: "'", with: "'\\''")
        let scriptWithInput = fullScript.replacingOccurrences(of: "{query}", with: escapedInput)

        task.arguments = ["-c", scriptWithInput]

        // Set environment
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}