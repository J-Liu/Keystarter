// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import Sparkle

/// Manages auto-update functionality using Sparkle.
final class UpdateManager {

    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController!

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
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Disable Sparkle's built-in automatic check - we handle it ourselves
        updaterController.updater.automaticallyChecksForUpdates = false
    }

    var checkFrequency: CheckFrequency {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "update.checkFrequency") ?? CheckFrequency.weekly.rawValue
            return CheckFrequency(rawValue: rawValue) ?? .weekly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "update.checkFrequency")
        }
    }

    private var lastUpdateCheck: String {
        get { UserDefaults.standard.string(forKey: "update.lastCheck") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "update.lastCheck") }
    }

    private func recordUpdateCheck() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lastUpdateCheck = formatter.string(from: Date())
    }

    func shouldCheckForUpdates() -> Bool {
        let frequency = checkFrequency
        if frequency == .never { return false }
        if frequency == .everyLaunch { return true }

        let lastCheck = lastUpdateCheck
        guard !lastCheck.isEmpty else { return true }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let lastDate = formatter.date(from: lastCheck) else { return true }

        let now = Date()
        let interval = now.timeIntervalSince(lastDate)
        let day: TimeInterval = 86400

        switch frequency {
        case .daily: return interval >= day
        case .weekly: return interval >= day * 7
        case .monthly: return interval >= day * 30
        default: return true
        }
    }

    /// Called at app launch to check for updates if needed
    func checkForUpdatesOnLaunch() {
        guard shouldCheckForUpdates() else { return }

        // Delay to let the app settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            // Use background check - only shows UI if update is found
            self?.updaterController.updater.checkForUpdatesInBackground()
            self?.recordUpdateCheck()
        }
    }

    /// Manual check with UI (from menu "Check for Updates...")
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
        recordUpdateCheck()
    }

    func startUpdater() {
        // Updater already started in init
    }
}