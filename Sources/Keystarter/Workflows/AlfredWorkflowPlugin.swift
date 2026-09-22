// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Wraps an Alfred workflow as a Plugin.
final class AlfredWorkflowPlugin: Plugin {

    private let workflow: AlfredWorkflow
    private var executor: AlfredWorkflowExecutor?
    private var currentKeyword: AlfredKeyword?
    private var currentItems: [AlfredScriptFilterOutput.AlfredItem] = []

    init(workflow: AlfredWorkflow) {
        self.workflow = workflow
        self.executor = AlfredWorkflowExecutor(workflow: workflow)
    }

    var keyword: String {
        // Return first keyword if multiple exist
        workflow.keywords.first?.keyword ?? ""
    }

    var pluginDescription: String {
        workflow.description.isEmpty ? workflow.name : workflow.description
    }

    func query(_ input: String) -> [PluginResult] {
        guard let kw = workflow.keywords.first else { return [] }
        guard let executor = executor else { return [] }

        currentKeyword = kw

        // Find connected Script Filter
        guard let nextUID = workflow.connections[kw.uid]?.first,
              let nextObj = workflow.objects[nextUID] else {

            // No script filter, just keyword trigger
            return [PluginResult(
                title: kw.title,
                subtitle: "Press Enter to run",
                action: { [weak self] in
                    self?.executeChain(from: kw.uid, input: input)
                }
            )]
        }

        // Run Script Filter
        if nextObj.type == "alfred.workflow.input.scriptfilter" {
            guard let output = executor.runScriptFilter(uid: nextUID, input: input) else {
                return []
            }
            currentItems = output.items

            return output.items.map { item in
                PluginResult(
                    title: item.title,
                    subtitle: item.subtitle,
                    icon: loadIcon(item.icon, path: workflow.path),
                    action: { [weak self] in
                        self?.executeChain(from: nextUID, arg: item.arg, variables: item.variables)
                    }
                )
            }
        }

        return []
    }

    private func executeChain(from uid: String, input: String? = nil, arg: String? = nil, variables: [String: String]? = nil) {
        guard let executor = executor else { return }

        let nextArg = arg ?? input ?? ""

        // Find next node
        guard let nextUIDs = workflow.connections[uid], let nextUID = nextUIDs.first,
              let nextObj = workflow.objects[nextUID] else { return }

        switch nextObj.type {
        case "alfred.workflow.input.scriptfilter":
            // Run script filter and get results
            _ = executor.runScriptFilter(uid: nextUID, input: nextArg)

        case "alfred.workflow.action.script":
            executor.runScript(uid: nextUID, input: nextArg)
            executeChain(from: nextUID, input: nextArg)

        case "alfred.workflow.output.revealfinder":
            if let path = nextArg.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "file://" + path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case "alfred.workflow.output.openurl":
            executor.openURL(uid: nextUID, input: nextArg)

        case "alfred.workflow.output.clipboard":
            executor.copyToClipboard(uid: nextUID, input: nextArg)
            executeChain(from: nextUID, input: nextArg)

        default:
            // Unknown node type, try to continue
            executeChain(from: nextUID, input: nextArg)
        }
    }

    private func loadIcon(_ icon: AlfredScriptFilterOutput.AlfredItem.AlfredIcon?, path: String) -> NSImage? {
        guard let icon = icon else { return nil }
        guard let iconPath = icon.path else { return nil }

        let fullPath: String
        if iconPath.hasPrefix("/") {
            fullPath = iconPath
        } else {
            fullPath = path + "/" + iconPath
        }

        if icon.type == "fileicon" {
            return NSWorkspace.shared.icon(forFile: fullPath)
        } else {
            return NSImage(contentsOfFile: fullPath)
        }
    }
}