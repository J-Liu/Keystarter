// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Protocol for status bar modules.
protocol StatusModule: AnyObject {
    /// Unique identifier for the module.
    var identifier: String { get }
    
    /// Display name shown in settings.
    var displayName: String { get }
    
    /// Current summary text shown in status bar.
    var summaryText: String { get }
    
    /// Icon shown in status bar (optional).
    var icon: NSImage? { get }
    
    /// Refresh the summary data.
    func refreshSummary()
    
    /// Create the detail view for popover.
    func makeDetailView() -> NSView
}