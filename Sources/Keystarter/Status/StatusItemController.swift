// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Controller for the status bar item.
final class StatusItemController: NSObject {

    static let shared = StatusItemController()

    private var statusItems: [String: NSStatusItem] = [:]
    private var popover: NSPopover?
    private var currentPopoverModule: String?

    private var modules: [StatusModule] = []

    private var refreshTimer: Timer?
    private var lastRefreshTimes: [String: Date] = [:]
    private let dataQueue = DispatchQueue(label: "com.keystarter.status.data", qos: .utility)
    private var eventMonitor: Any?

    override init() {
        super.init()
        log("StatusItemController started")
        loadEnabledModules()
        log("Loaded \(modules.count) modules: \(modules.map { $0.identifier }.joined(separator: ", "))")
        setupStatusItem()
        initialRefresh()
        startRefreshTimer()

        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .statusModuleSettingsChanged,
            object: nil
        )

        // Listen for module data updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(moduleDataUpdated),
            name: .moduleDataUpdated,
            object: nil
        )
    }

    deinit {
    }

    private func log(_ message: String) {
        guard LogSettings.shared.monitorLogEnabled else { return }
        LogSettings.write(message, to: LogSettings.shared.monitorLogPath)
    }

    /// Perform initial refresh immediately on all modules.
    private func initialRefresh() {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            for module in self.modules {
                module.refreshSummary()
                DispatchQueue.main.async {
                    self.updateModuleLabel(module)
                    self.lastRefreshTimes[module.identifier] = Date()
                }
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        // Create separate status item for each module (reverse order so first module appears leftmost)
        for module in modules.reversed() {
            // Width based on module type
            let itemWidth: CGFloat
            switch module.identifier {
            case "network":
                itemWidth = 42
            case "disk":
                itemWidth = 46
            case "sensor":
                itemWidth = 23
            case "memory":
                itemWidth = 23
            default:
                itemWidth = 23
            }
            let item = NSStatusBar.system.statusItem(withLength: itemWidth)

            // Sensor module: single line, others: two lines
            let attrString = NSMutableAttributedString()

            if module.identifier == "sensor" {
                // Single line for sensor
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.alignment = .center
                paraStyle.lineSpacing = 0
                paraStyle.paragraphSpacing = 0

                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont(name: "Tahoma", size: 11)!,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle
                ]
                attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
            } else {
                // Two lines for others
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.alignment = .center
                paraStyle.lineSpacing = -3
                paraStyle.paragraphSpacing = -3

                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7, weight: .light),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle
                ]
                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont(name: "Tahoma", size: 11)!,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle
                ]

                attrString.append(NSAttributedString(string: module.shortName + "\n", attributes: nameAttrs))
                attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
            }

            item.button?.attributedTitle = attrString
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier(module.identifier)
            item.button?.toolTip = module.displayName

            statusItems[module.identifier] = item
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let identifier = sender.identifier?.rawValue else {
            log("Click: no identifier")
            return
        }

        log("Status item clicked: \(identifier)")

        // Toggle: if same module's popover is open, close it
        if currentPopoverModule == identifier {
            popover?.close()
            currentPopoverModule = nil
            log("Popover closed (toggle)")
            return
        }

        guard let module = modules.first(where: { $0.identifier == identifier }) else {
            log("No module found: \(identifier)")
            return
        }
        showPopover(for: module, from: sender)
    }

    private func addModuleView(_ module: StatusModule) {
        // Recalculate layout
        relayoutModuleViews()
    }

    private func removeModuleView(_ identifier: String) {
        relayoutModuleViews()
    }

    private func relayoutModuleViews() {
        // Remove old status items
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()

        // Recreate status items for current modules (reverse order so first module appears leftmost)
        for module in modules.reversed() {
            // Width based on module type
            let itemWidth: CGFloat
            switch module.identifier {
            case "network":
                itemWidth = 42
            case "disk":
                itemWidth = 46
            case "sensor":
                itemWidth = 23
            case "memory":
                itemWidth = 23
            default:
                itemWidth = 23
            }
            let item = NSStatusBar.system.statusItem(withLength: itemWidth)

            // Sensor module: single line, others: two lines
            let attrString = NSMutableAttributedString()

            if module.identifier == "sensor" {
                // Single line for sensor
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.alignment = .center
                paraStyle.lineSpacing = 0
                paraStyle.paragraphSpacing = 0

                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont(name: "Tahoma", size: 11)!,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle
                ]
                attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
            } else {
                // Two lines for others
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.alignment = .center
                paraStyle.lineSpacing = -3
                paraStyle.paragraphSpacing = -3

                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7, weight: .light),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle
                ]
                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont(name: "Tahoma", size: 11)!,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paraStyle
                ]

                attrString.append(NSAttributedString(string: module.shortName + "\n", attributes: nameAttrs))
                attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
            }

            item.button?.attributedTitle = attrString
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier(module.identifier)
            item.button?.toolTip = module.displayName

            statusItems[module.identifier] = item
        }
    }

    // MARK: - Module Management

    private func loadEnabledModules() {
        let defaults = UserDefaults.standard

        // Register default values (enabled by default)
        defaults.register(defaults: [
            "status.cpu.enabled": true,
            "status.gpu.enabled": true,
            "status.sensor.enabled": true,
            "status.memory.enabled": true,
            "status.disk.enabled": true,
            "status.network.enabled": true
        ])

        // Load modules in specified order: CPU, GPU, TMP, Memory, Disk, Network
        if defaults.bool(forKey: "status.cpu.enabled") {
            modules.append(CPUModule())
        }

        if defaults.bool(forKey: "status.gpu.enabled") {
            modules.append(GPUModule())
        }

        if defaults.bool(forKey: "status.sensor.enabled") {
            modules.append(SensorModule())
        }

        if defaults.bool(forKey: "status.memory.enabled") {
            modules.append(MemoryModule())
        }

        if defaults.bool(forKey: "status.disk.enabled") {
            modules.append(DiskModule())
        }

        if defaults.bool(forKey: "status.network.enabled") {
            modules.append(NetworkModule())
        }
    }

    func enableModule(_ identifier: String) {
        guard !modules.contains(where: { $0.identifier == identifier }) else { return }

        let module: StatusModule
        switch identifier {
        case "cpu":
            module = CPUModule()
        case "memory":
            module = MemoryModule()
        case "network":
            module = NetworkModule()
        case "disk":
            module = DiskModule()
        case "gpu":
            module = GPUModule()
        case "sensor":
            module = SensorModule()
        default:
            return
        }

        modules.append(module)
        addModuleView(module)
        log("Module enabled: \(identifier)")

        // Refresh on background queue to avoid UI lag
        dataQueue.async { [weak self] in
            module.refreshSummary()
            DispatchQueue.main.async {
                self?.updateModuleLabel(module)
            }
        }
    }

    func disableModule(_ identifier: String) {
        modules.removeAll { $0.identifier == identifier }
        removeModuleView(identifier)
        log("Module disabled: \(identifier)")
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        // Use 1 second timer, check each module's interval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshIfNeeded()
        }
    }

    private func refreshIfNeeded() {
        let now = Date()
        let modulesToRefresh = modules.filter { module in
            let lastRefresh = lastRefreshTimes[module.identifier] ?? .distantPast
            let elapsed = now.timeIntervalSince(lastRefresh)
            return elapsed >= module.refreshInterval
        }

        guard !modulesToRefresh.isEmpty else { return }

        // Collect data on background queue
        dataQueue.async { [weak self] in
            guard let self = self else { return }

            for module in modulesToRefresh {
                module.refreshSummary()
            }

            // Update UI on main queue
            DispatchQueue.main.async {
                for module in modulesToRefresh {
                    self.updateModuleLabel(module)
                    self.lastRefreshTimes[module.identifier] = now
                }
            }
        }
    }

    private func updateModuleLabel(_ module: StatusModule) {
        guard let item = statusItems[module.identifier],
              let button = item.button else { return }

        let attrString = NSMutableAttributedString()

        // Sensor module: single line
        if module.identifier == "sensor" {
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = 0
            paraStyle.paragraphSpacing = 0

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Tahoma", size: 11)!,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
        } else if module.identifier == "disk", let diskModule = module as? DiskModule {
            // Disk: two-line speed display
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = -3
            paraStyle.paragraphSpacing = -3

            let topAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .light),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            let bottomAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .light),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]

            attrString.append(NSAttributedString(string: "W " + diskModule.writeSpeedText + "\n", attributes: topAttrs))
            attrString.append(NSAttributedString(string: "R " + diskModule.readSpeedText, attributes: bottomAttrs))
        } else if module.identifier == "network", let networkModule = module as? NetworkModule {
            // Network: two-line speed display
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = -3
            paraStyle.paragraphSpacing = -3

            let topAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .light),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            let bottomAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .light),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]

            attrString.append(NSAttributedString(string: "↑ " + networkModule.uploadSpeedText + "\n", attributes: topAttrs))
            attrString.append(NSAttributedString(string: "↓ " + networkModule.downloadSpeedText, attributes: bottomAttrs))
        } else {
            // Other modules: two lines (name + value)
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = -3
            paraStyle.paragraphSpacing = -3

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7, weight: .light),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Tahoma", size: 11)!,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]

            attrString.append(NSAttributedString(string: module.shortName + "\n", attributes: nameAttrs))
            attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
        }

        button.attributedTitle = attrString
    }

    // MARK: - Actions

    private func showPopover(for module: StatusModule, from view: NSView) {
        popover?.close()

        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.delegate = self
        let viewController = NSViewController()
        let contentView = module.makeDetailView()
        viewController.view = contentView
        newPopover.contentViewController = viewController
        newPopover.contentSize = contentView.frame.size

        newPopover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        self.popover = newPopover
        self.currentPopoverModule = module.identifier
        log("Popover shown for: \(module.identifier)")
    }

    @objc private func settingsChanged() {
        // Reload modules
        let previousIdentifiers = Set(modules.map { $0.identifier })
        modules.removeAll()
        loadEnabledModules()

        let newIdentifiers = Set(modules.map { $0.identifier })

        // Remove old modules
        for id in previousIdentifiers.subtracting(newIdentifiers) {
            removeModuleView(id)
        }

        // Add new modules
        for module in modules {
            if !previousIdentifiers.contains(module.identifier) {
                addModuleView(module)
            }
        }

        // Refresh all modules immediately
        for module in modules {
            module.refreshSummary()
            updateModuleLabel(module)
        }
        lastRefreshTimes.removeAll()
    }

    @objc private func moduleDataUpdated(_ notification: Notification) {
        guard let moduleId = notification.userInfo?["module"] as? String else { return }
        if let module = modules.first(where: { $0.identifier == moduleId }) {
            DispatchQueue.main.async {
                self.updateModuleLabel(module)
            }
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let statusModuleSettingsChanged = Notification.Name("statusModuleSettingsChanged")
    static let moduleDataUpdated = Notification.Name("moduleDataUpdated")
}

// MARK: - NSPopoverDelegate

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        currentPopoverModule = nil
    }
}
