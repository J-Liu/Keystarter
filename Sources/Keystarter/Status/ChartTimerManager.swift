// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Shared timer for all chart views to reduce timer count and ensure consistent refresh.
final class ChartTimerManager {
    static let shared = ChartTimerManager()

    private var timer: Timer?
    private var registeredViews: NSHashTable<NSView> // Weak references

    private init() {
        registeredViews = NSHashTable.weakObjects()
    }

    /// Register a view to receive redraw notifications.
    func register(_ view: NSView) {
        registeredViews.add(view)
        startTimerIfNeeded()
    }

    /// Unregister a view from receiving redraw notifications.
    func unregister(_ view: NSView) {
        registeredViews.remove(view)
        stopTimersIfEmpty()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.notifyAll()
        }
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    private func stopTimersIfEmpty() {
        if registeredViews.allObjects.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func notifyAll() {
        for view in registeredViews.allObjects {
            view.needsDisplay = true
        }
    }
}