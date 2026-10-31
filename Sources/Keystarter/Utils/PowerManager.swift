// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import IOKit.pwr_mgt

/// Manages power assertions to prevent system sleep and display sleep.
final class PowerManager {

    static let shared = PowerManager()

    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0

    private var displayAssertionActive = false
    private var systemAssertionActive = false

    private init() {}

    /// Enable/disable display sleep prevention (screen stays on)
    var preventDisplaySleep: Bool {
        get { displayAssertionActive }
        set {
            if newValue && !displayAssertionActive {
                enableDisplayAssertion()
            } else if !newValue && displayAssertionActive {
                disableDisplayAssertion()
            }
        }
    }

    /// Enable/disable system sleep prevention (system stays awake)
    var preventSystemSleep: Bool {
        get { systemAssertionActive }
        set {
            if newValue && !systemAssertionActive {
                enableSystemAssertion()
            } else if !newValue && systemAssertionActive {
                disableSystemAssertion()
            }
        }
    }

    private func enableDisplayAssertion() {
        let reason = "Keystarter: Prevent display sleep" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayAssertion
        )
        if result == kIOReturnSuccess {
            displayAssertionActive = true
        }
    }

    private func disableDisplayAssertion() {
        if displayAssertionActive {
            IOPMAssertionRelease(displayAssertion)
            displayAssertionActive = false
        }
    }

    private func enableSystemAssertion() {
        let reason = "Keystarter: Prevent system sleep" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemAssertion
        )
        if result == kIOReturnSuccess {
            systemAssertionActive = true
        }
    }

    private func disableSystemAssertion() {
        if systemAssertionActive {
            IOPMAssertionRelease(systemAssertion)
            systemAssertionActive = false
        }
    }

    /// Load saved settings and apply them
    func loadSettings() {
        let preventDisplay = UserDefaults.standard.bool(forKey: "power.preventDisplaySleep")
        let preventSystem = UserDefaults.standard.bool(forKey: "power.preventSystemSleep")

        self.preventDisplaySleep = preventDisplay
        self.preventSystemSleep = preventSystem
    }
}