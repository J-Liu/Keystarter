// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// A button that records keyboard shortcuts.
/// Uses its own event monitor to capture keys reliably.
final class HotkeyRecorderButton: NSButton {

    /// Class-level flag so SettingsWindow knows not to intercept keys.
    static var isAnyRecording = false

    var onKeyRecorded: ((HotkeyRecorderButton) -> Void)?
    private var isRecording = false
    private var recordedKeyCode: UInt16 = 0
    private var recordedModifiers: NSEvent.ModifierFlags = []
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        self.bezelStyle = .rounded
        self.title = "Click to record"
        self.target = self
        self.action = #selector(startRecording)
    }

    override var acceptsFirstResponder: Bool { true }

    func setShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        recordedKeyCode = keyCode
        recordedModifiers = modifiers
        self.title = formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    @objc private func startRecording() {
        isRecording = true
        HotkeyRecorderButton.isAnyRecording = true
        self.title = "Press shortcut..."
        self.state = .on
        window?.makeFirstResponder(self)

        // Use our own event monitor to capture keys reliably
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            self.handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        HotkeyRecorderButton.isAnyRecording = false
        self.state = .off
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Esc cancels recording
        if keyCode == 53 {
            stopRecording()
            if recordedKeyCode != 0 {
                self.title = formatShortcut(keyCode: recordedKeyCode, modifiers: recordedModifiers)
            } else {
                self.title = "Click to record"
            }
            return
        }

        // Require at least one modifier
        if !modifiers.contains(.command) && !modifiers.contains(.option) &&
           !modifiers.contains(.control) && !modifiers.contains(.shift) {
            NSSound.beep()
            return
        }

        recordedKeyCode = keyCode
        recordedModifiers = modifiers
        self.title = formatShortcut(keyCode: keyCode, modifiers: modifiers)
        stopRecording()
        onKeyRecorded?(self)
    }

    override func keyDown(with event: NSEvent) {
        // Handled by event monitor
    }

    private func formatShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyChar = keyCodeToString(keyCode)
        parts.append(keyChar)

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 102: return "F11"
        case 103: return "F13"
        case 104: return "F16"
        case 105: return "F14"
        case 106: return "F10"
        case 107: return "F12"
        case 109: return "F15"
        case 110: return "F17"
        case 111: return "F18"
        case 112: return "F19"
        case 113: return "F20"
        case 114: return "F1"
        case 115: return "F2"
        case 116: return "F4"
        case 117: return "⌦"
        case 120: return "F1"
        case 121: return "F2"
        case 122: return "F3"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "?"
        }
    }

    var keyCode: UInt16 { recordedKeyCode }
    var modifiers: NSEvent.ModifierFlags { recordedModifiers }
}
