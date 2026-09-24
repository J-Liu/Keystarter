// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import Sparkle

/// Manages auto-update functionality using Sparkle.
final class UpdateManager {

    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    enum CheckFrequency: String, CaseIterable {
        case everyLaunch = "everyLaunch"
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
        case never = "never"

        var displayName: String {
            switch self {
            case .everyLaunch: return L("settings.update.frequency.everyLaunch")
            case .daily: return L("settings.update.frequency.daily")
            case .weekly: return L("settings.update.frequency.weekly")
            case .monthly: return L("settings.update.frequency.monthly")
            case .never: return L("settings.update.frequency.never")
            }
        }

        var seconds: TimeInterval? {
            switch self {
            case .everyLaunch: return 0
            case .daily: return 86400
            case .weekly: return 604800
            case .monthly: return 2592000
            case .never: return nil
            }
        }
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var checkFrequency: CheckFrequency {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "update.checkFrequency") ?? CheckFrequency.weekly.rawValue
            return CheckFrequency(rawValue: rawValue) ?? .weekly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "update.checkFrequency")
            updateCheckInterval()
        }
    }

    private func updateCheckInterval() {
        switch checkFrequency {
        case .everyLaunch:
            updaterController.updater.automaticallyChecksForUpdates = true
            updaterController.updater.updateCheckInterval = 0
        case .daily, .weekly, .monthly:
            updaterController.updater.automaticallyChecksForUpdates = true
            if let seconds = checkFrequency.seconds {
                updaterController.updater.updateCheckInterval = seconds
            }
        case .never:
            updaterController.updater.automaticallyChecksForUpdates = false
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func startUpdater() {
        updateCheckInterval()
    }
}
