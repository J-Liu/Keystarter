// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// User-configurable appearance settings.
enum AppearanceSettings {

    static var windowWidth: CGFloat = 800
    static var windowHeight: CGFloat = 400
    static var cornerRadius: CGFloat = 12
    static var opacity: CGFloat = 0.95  // 0.0 - 1.0

    /// Visual effect material.
    enum Material: String, CaseIterable {
        case hudWindow = "hudWindow"
        case popover = "popover"
        case menu = "menu"
        case titlebar = "titlebar"
        case ultraDark = "ultraDark"

        var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .hudWindow: return .hudWindow
            case .popover: return .popover
            case .menu: return .menu
            case .titlebar: return .titlebar
            case .ultraDark: return .underWindowBackground
            }
        }
    }

    static var material: Material = .hudWindow

    /// Load settings from UserDefaults.
    static func load() {
        let defaults = UserDefaults.standard
        cornerRadius = CGFloat(defaults.float(forKey: "appearance.cornerRadius"))
        if cornerRadius == 0 { cornerRadius = 12 }

        opacity = CGFloat(defaults.float(forKey: "appearance.opacity"))
        if opacity == 0 { opacity = 0.95 }

        if let materialName = defaults.string(forKey: "appearance.material"),
           let mat = Material(rawValue: materialName) {
            material = mat
        }
    }

    /// Save settings to UserDefaults.
    static func save() {
        let defaults = UserDefaults.standard
        defaults.set(Float(cornerRadius), forKey: "appearance.cornerRadius")
        defaults.set(Float(opacity), forKey: "appearance.opacity")
        defaults.set(material.rawValue, forKey: "appearance.material")
    }
}