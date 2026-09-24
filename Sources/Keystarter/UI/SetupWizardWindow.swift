// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

/// First launch setup wizard.
/// Step 1: Record hotkey
/// Step 2: Request permissions (directly triggers system dialog)
/// Step 3: Done
final class SetupWizardWindow: NSWindow {

    private var hotkeyRecorder: HotkeyRecorderButton!
    private var stepLabel: NSTextField!
    private var descriptionLabel: NSTextField!
    private var nextButton: NSButton!
    private var skipButton: NSButton!
    private var currentStep = 0

    var onComplete: (() -> Void)?

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let width: CGFloat = 500
        let height: CGFloat = 350
        let x = screenFrame.midX - width / 2
        let y = screenFrame.midY - height / 2
        let frame = NSRect(x: x, y: y, width: width, height: height)

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Welcome to Keystarter"
        self.isReleasedWhenClosed = false

        setupUI()
        showStep(0)
    }

    private func setupUI() {
        guard let contentView = contentView else { return }

        // Step label
        stepLabel = NSTextField(labelWithString: "Step 1 of 3")
        stepLabel.frame = NSRect(x: 20, y: 290, width: 460, height: 24)
        stepLabel.font = .systemFont(ofSize: 14, weight: .medium)
        stepLabel.textColor = .secondaryLabelColor
        contentView.addSubview(stepLabel)

        // Description label
        descriptionLabel = NSTextField(wrappingLabelWithString: "")
        descriptionLabel.frame = NSRect(x: 20, y: 200, width: 460, height: 80)
        descriptionLabel.font = .systemFont(ofSize: 16)
        descriptionLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(descriptionLabel)

        // Hotkey recorder (hidden initially)
        hotkeyRecorder = HotkeyRecorderButton(frame: NSRect(x: 175, y: 150, width: 150, height: 36))
        hotkeyRecorder.isHidden = true
        contentView.addSubview(hotkeyRecorder)

        // Skip button
        skipButton = NSButton(frame: NSRect(x: 20, y: 20, width: 80, height: 32))
        skipButton.title = "Skip"
        skipButton.bezelStyle = .rounded
        skipButton.target = self
        skipButton.action = #selector(skipSetup)
        contentView.addSubview(skipButton)

        // Next button
        nextButton = NSButton(frame: NSRect(x: 360, y: 20, width: 120, height: 32))
        nextButton.title = "Next"
        nextButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(nextStep)
        contentView.addSubview(nextButton)
    }

    private func showStep(_ step: Int) {
        currentStep = step

        switch step {
        case 0:
            stepLabel.stringValue = "Step 1 of 3: Hotkey"
            descriptionLabel.stringValue = "Set a global hotkey to open Keystarter from anywhere.\n\nDefault: ⌘ Space"
            hotkeyRecorder.isHidden = false
            hotkeyRecorder.setShortcut(keyCode: UInt16(49), modifiers: .command)
            nextButton.title = "Next"

        case 1:
            stepLabel.stringValue = "Step 2 of 3: Permissions"
            descriptionLabel.stringValue = "Keystarter needs Accessibility permission to work.\n\nClick Next to open System Settings."
            hotkeyRecorder.isHidden = true
            nextButton.title = "Grant Permission"

        case 2:
            stepLabel.stringValue = "Step 3 of 3: Done"
            descriptionLabel.stringValue = "Setup complete!\n\nYou can now use Keystarter."
            hotkeyRecorder.isHidden = true
            nextButton.title = "Finish"

        default:
            break
        }
    }

    @objc private func nextStep() {
        switch currentStep {
        case 0:
            // Save hotkey
            if let delegate = NSApp.delegate as? AppDelegate {
                let keyCode = hotkeyRecorder.keyCode
                let modifiers = hotkeyRecorder.modifiers
                UserDefaults.standard.set(Int(keyCode), forKey: "hotkey.keyCode")
                UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "hotkey.modifiers")
                delegate.updateHotkey(keyCode: keyCode, modifiers: modifiers)
            }
            showStep(1)

        case 1:
            // Directly trigger system permission dialog, no custom alert
            _ = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeRetainedValue(): true
            ] as CFDictionary)
            PermissionManager.shared.setLoginItem(enabled: true)
            showStep(2)

        case 2:
            finishSetup()

        default:
            break
        }
    }

    @objc private func skipSetup() {
        finishSetup()
    }

    private func finishSetup() {
        PermissionManager.shared.markLaunched()
        close()
        onComplete?()
    }
}
