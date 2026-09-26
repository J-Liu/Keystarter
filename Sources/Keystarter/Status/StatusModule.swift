// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Protocol for status bar modules.
protocol StatusModule: AnyObject {
    /// Unique identifier for the module.
    var identifier: String { get }
    
    /// Display name shown in settings.
    var displayName: String { get }
    
    /// Short name shown in status bar (e.g., "CPU").
    var shortName: String { get }
    
    /// Current value shown in status bar (e.g., "23%").
    var summaryValue: String { get }
    
    /// Full summary text for backwards compatibility.
    var summaryText: String { get }
    
    /// Refresh interval in seconds.
    var refreshInterval: TimeInterval { get }
    
    /// Refresh the summary data.
    func refreshSummary()
    
    /// Create the detail view for popover.
    func makeDetailView() -> NSView
}

extension StatusModule {
    var refreshInterval: TimeInterval { 2.0 }
}