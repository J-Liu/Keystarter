// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Manages installed Alfred workflows.
final class AlfredWorkflowManager {

    static let shared = AlfredWorkflowManager()

    private let workflowsDir: String
    private var loadedWorkflows: [String: AlfredWorkflow] = [:]

    private init() {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/Keystarter/Workflows"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        workflowsDir = dir
    }

    /// Import an Alfred workflow (.alfredworkflow is a zip).
    func importWorkflow(from path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let destDir = workflowsDir + "/" + (name as NSString).deletingPathExtension

        // Remove existing
        try? FileManager.default.removeItem(atPath: destDir)

        // Unzip
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", "-d", destDir, path]
        task.currentDirectoryURL = URL(fileURLWithPath: workflowsDir)

        do {
            try task.run()
            task.waitUntilExit()
            loadWorkflow(at: destDir)
            return true
        } catch {
            print("[AlfredWorkflowManager] Import failed: \(error)")
            return false
        }
    }

    /// Load all workflows from the workflows directory.
    func loadAll() {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: workflowsDir) else {
            return
        }

        for name in contents {
            let path = workflowsDir + "/" + name
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                loadWorkflow(at: path)
            }
        }
    }

    /// Load a single workflow and register it as a plugin.
    private func loadWorkflow(at path: String) {
        guard let workflow = AlfredWorkflowParser.parse(path: path) else {
            print("[AlfredWorkflowManager] Failed to parse: \(path)")
            return
        }

        loadedWorkflows[workflow.bundleId] = workflow

        // Register as plugin
        let plugin = AlfredWorkflowPlugin(workflow: workflow)
        PluginManager.shared.register(plugin)

        print("[AlfredWorkflowManager] Loaded: \(workflow.name) (keywords: \(workflow.keywords.map { $0.keyword }))")
    }

    /// List all loaded workflows.
    func listWorkflows() -> [AlfredWorkflow] {
        Array(loadedWorkflows.values)
    }

    /// Get the workflows directory path.
    var workflowDirectory: String {
        workflowsDir
    }
}