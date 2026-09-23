// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Floating panel for clipboard history.
final class ClipboardPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = true
    }

    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        centerOnMouse()
        makeKeyAndOrderFront(nil)
    }

    private func centerOnMouse() {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }

        var x = mouseLoc.x - frame.width / 2
        var y = mouseLoc.y - frame.height

        // Adjust for screen edges
        if x < screenFrame.minX { x = screenFrame.minX + 10 }
        if x + frame.width > screenFrame.maxX { x = screenFrame.maxX - frame.width - 10 }
        if y < screenFrame.minY { y = screenFrame.minY + 10 }

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}