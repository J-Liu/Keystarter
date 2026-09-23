// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

/// Manages a single global hotkey using CGEvent tap.
/// Requires Accessibility permission.
final class HotkeyManager {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let callback: () -> Void
    private var targetKeyCode: UInt16 = 49 // Space
    private var targetModifiers: NSEvent.ModifierFlags = .command
    private var permissionCheckTimer: Timer?
    private var isRegistered = false

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    /// Register the global hotkey with custom key and modifiers.
    func register(keyCode: UInt16 = 49, modifiers: NSEvent.ModifierFlags = .command) {
        targetKeyCode = keyCode
        targetModifiers = modifiers

        tryRegister()

        // Start checking for permission changes
        startPermissionCheck()
    }

    /// Try to register the event tap.
    private func tryRegister() {
        // Check accessibility permission
        let trusted = AXIsProcessTrusted()

        if !trusted {
            print("[HotkeyManager] Accessibility permission not granted yet")
            return
        }

        // Already registered
        if isRegistered {
            return
        }

        // Create event tap for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // Callback for event tap
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            print("[HotkeyManager] Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        isRegistered = true
        print("[HotkeyManager] Hotkey registered")
    }

    /// Start periodic permission check.
    private func startPermissionCheck() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tryRegister()
        }
    }

    /// Stop permission check.
    private func stopPermissionCheck() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// Handle keyboard event.
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If tap is disabled by system, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check if this matches our hotkey
        if keyCode == Int64(targetKeyCode) {
            let hasCommand = flags.contains(.maskCommand)
            let hasOption = flags.contains(.maskAlternate)
            let hasControl = flags.contains(.maskControl)
            let hasShift = flags.contains(.maskShift)

            let wantCommand = targetModifiers.contains(.command)
            let wantOption = targetModifiers.contains(.option)
            let wantControl = targetModifiers.contains(.control)
            let wantShift = targetModifiers.contains(.shift)

            if hasCommand == wantCommand &&
               hasOption == wantOption &&
               hasControl == wantControl &&
               hasShift == wantShift {
                // Match! Call callback and consume event
                DispatchQueue.main.async { [weak self] in
                    self?.callback()
                }
                return nil // Consume the event
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Unregister the global hotkey.
    func unregister() {
        stopPermissionCheck()

        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        isRegistered = false
        print("[HotkeyManager] Hotkey unregistered")
    }

    deinit {
        unregister()
    }
}
