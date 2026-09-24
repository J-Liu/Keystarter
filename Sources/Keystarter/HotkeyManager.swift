// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Carbon

/// Manages global hotkeys using CGEvent tap.
/// Requires Accessibility permission.
final class HotkeyManager {

    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeys: [UInt16: (modifiers: NSEvent.ModifierFlags, callback: () -> Void)] = [:]
    private var permissionCheckTimer: Timer?
    private var isRegistered = false

    private init() {}

    /// Register a global hotkey with custom key and modifiers.
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        hotkeys[keyCode] = (modifiers: modifiers, callback: callback)

        tryRegister()

        // Start checking for permission changes
        startPermissionCheck()
    }

    /// Unregister a specific hotkey.
    func unregister(keyCode: UInt16) {
        hotkeys.removeValue(forKey: keyCode)

        if hotkeys.isEmpty {
            unregisterAll()
        }
    }

    /// Unregister all hotkeys.
    func unregisterAll() {
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
        hotkeys.removeAll()
        print("[HotkeyManager] All hotkeys unregistered")
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
        print("[HotkeyManager] Hotkeys registered: \(hotkeys.keys)")
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

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check if this matches any registered hotkey
        if let hotkey = hotkeys[keyCode] {
            let hasCommand = flags.contains(.maskCommand)
            let hasOption = flags.contains(.maskAlternate)
            let hasControl = flags.contains(.maskControl)
            let hasShift = flags.contains(.maskShift)

            let wantCommand = hotkey.modifiers.contains(.command)
            let wantOption = hotkey.modifiers.contains(.option)
            let wantControl = hotkey.modifiers.contains(.control)
            let wantShift = hotkey.modifiers.contains(.shift)

            if hasCommand == wantCommand &&
               hasOption == wantOption &&
               hasControl == wantControl &&
               hasShift == wantShift {
                // Match! Call callback and consume event
                DispatchQueue.main.async {
                    hotkey.callback()
                }
                return nil // Consume the event
            }
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        unregisterAll()
    }
}
