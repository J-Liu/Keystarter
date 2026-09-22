// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AppKit

/// Represents a parsed Alfred workflow.
struct AlfredWorkflow {
    let bundleId: String
    let name: String
    let description: String
    let path: String
    let keywords: [AlfredKeyword]
    let connections: [String: [String]]
    let objects: [String: AlfredObject]
}

/// A keyword trigger node.
struct AlfredKeyword {
    let uid: String
    let keyword: String
    let title: String
    let withInput: Bool
}

/// An object (node) in the workflow graph.
struct AlfredObject {
    let uid: String
    let type: String
    let config: [String: Any]
}

/// Parses an Alfred workflow's info.plist.
final class AlfredWorkflowParser {

    /// Parse a workflow directory.
    static func parse(path: String) -> AlfredWorkflow? {
        let plistPath = path + "/info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath) else {
            return nil
        }

        var format: PropertyListSerialization.PropertyListFormat = .xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            return nil
        }

        let bundleId = plist["bundleid"] as? String ?? ""
        let name = plist["name"] as? String ?? ""
        let description = plist["description"] as? String ?? ""

        var keywords: [AlfredKeyword] = []
        var objects: [String: AlfredObject] = [:]

        // Parse objects (nodes)
        if let items = plist["objects"] as? [[String: Any]] {
            for item in items {
                guard let uid = item["uid"] as? String else { continue }
                let type = item["type"] as? String ?? ""
                let config = item["config"] as? [String: Any] ?? [:]

                objects[uid] = AlfredObject(uid: uid, type: type, config: config)

                // Extract keyword triggers
                if type == "alfred.workflow.input.keyword" {
                    let keyword = config["keyword"] as? String ?? ""
                    let title = config["title"] as? String ?? ""
                    let withInput = config["withinput"] as? Int == 1
                    keywords.append(AlfredKeyword(uid: uid, keyword: keyword, title: title, withInput: withInput))
                }
            }
        }

        // Parse connections (edges)
        let connections = plist["connections"] as? [String: [[String: Any]]] ?? [:]
        var connectionMap: [String: [String]] = [:]
        for (from, targets) in connections {
            connectionMap[from] = targets.compactMap { $0["destinationuid"] as? String }
        }

        return AlfredWorkflow(
            bundleId: bundleId,
            name: name,
            description: description,
            path: path,
            keywords: keywords,
            connections: connectionMap,
            objects: objects
        )
    }
}