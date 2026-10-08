// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Controller for the status bar item.
final class StatusItemController: NSObject {

    static let shared = StatusItemController()

    private var statusItems: [String: NSStatusItem] = [:]
    private var popover: NSPopover?
    private var currentPopoverModule: String?
    private var memoryBarView: MemoryBarView?  // Custom view for memory bar

    var modules: [StatusModule] = []

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

        // Monitor clicks outside to close popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.close()
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func log(_ message: String) {
        guard LogSettings.shared.monitorLogEnabled else { return }
        LogSettings.write(message, to: LogSettings.shared.monitorLogPath)
    }

    /// Perform initial refresh immediately on all modules.
    private func initialRefresh() {
        // First call: initialize baseline values
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            for module in self.modules {
                module.refreshSummary()
            }

            // Second call after 0.5s: get actual data (needed for disk/network speed)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [weak self] in
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
    }

    // MARK: - Setup

    private func setupStatusItem() {
        // Create separate status item for each module (reverse order so first module appears leftmost)
        for module in modules.reversed() {
            // Default width: tighter for CPU/GPU/Sensor, wider for network/disk
            let itemWidth: CGFloat
            switch module.identifier {
            case "cpu", "gpu":
                itemWidth = 16  // 2 digits, narrow
            case "sensor":
                itemWidth = 15  // 2 digits + unit
            case "memory":
                itemWidth = 7   // Segmented bar
            case "network", "disk":
                itemWidth = 50  // Speed format like "123.4K"
            default:
                itemWidth = 16
            }

            let item = NSStatusBar.system.statusItem(withLength: itemWidth)

            // Memory module: custom segmented bar view
            if module.identifier == "memory", let memoryModule = module as? MemoryModule {
                let barView = MemoryBarView(color: memoryModule.barColor)
                barView.setPercentage(memoryModule.usedPercentage)

                // Add to button as subview
                item.button?.addSubview(barView)
                item.button?.target = self
                item.button?.action = #selector(statusItemClicked(_:))
                item.button?.identifier = NSUserInterfaceItemIdentifier(module.identifier)
                item.button?.toolTip = module.displayName

                memoryBarView = barView
            } else {
                // Other modules: use attributed text
                let attrString = NSMutableAttributedString()

                if module.identifier == "sensor" {
                    // Single line for sensor
                    let paraStyle = NSMutableParagraphStyle()
                    paraStyle.alignment = .center
                    paraStyle.lineSpacing = 0
                    paraStyle.paragraphSpacing = 0

                    let valueAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont(name: "Tahoma", size: 10)!,
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
                        .font: NSFont(name: "Tahoma", size: 10)!,
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
            }

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
        memoryBarView = nil

        // Recreate status items for current modules (reverse order so first module appears leftmost)
        for module in modules.reversed() {
            // Default width: tighter for CPU/GPU/Sensor, wider for network/disk
            let itemWidth: CGFloat
            switch module.identifier {
            case "cpu", "gpu":
                itemWidth = 16  // 2 digits, narrow
            case "sensor":
                itemWidth = 15  // 2 digits + unit
            case "memory":
                itemWidth = 7  // Segmented bar
            case "network", "disk":
                itemWidth = 50  // Speed format like "123.4K"
            default:
                itemWidth = 16
            }

            let item = NSStatusBar.system.statusItem(withLength: itemWidth)

            // Memory module: custom segmented bar view
            if module.identifier == "memory", let memoryModule = module as? MemoryModule {
                let barView = MemoryBarView(color: memoryModule.barColor)
                barView.setPercentage(memoryModule.usedPercentage)

                // Add to button as subview
                item.button?.addSubview(barView)
                item.button?.target = self
                item.button?.action = #selector(statusItemClicked(_:))
                item.button?.identifier = NSUserInterfaceItemIdentifier(module.identifier)
                item.button?.toolTip = module.displayName

                memoryBarView = barView
            } else {
                // Other modules: use attributed text
                let attrString = NSMutableAttributedString()

                if module.identifier == "sensor" {
                    // Single line for sensor
                    let paraStyle = NSMutableParagraphStyle()
                    paraStyle.alignment = .center
                    paraStyle.lineSpacing = 0
                    paraStyle.paragraphSpacing = 0

                    let valueAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont(name: "Tahoma", size: 10)!,
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
                        .font: NSFont(name: "Tahoma", size: 10)!,
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
            }

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

        // Memory module: update segmented bar view
        if module.identifier == "memory", let memoryModule = module as? MemoryModule {
            memoryBarView?.setPercentage(memoryModule.usedPercentage)
            memoryBarView?.setColor(memoryModule.barColor)
            return
        }

        let attrString = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 9, weight: .light)

        // Calculate adaptive width
        var calculatedWidth: CGFloat = 28  // Default width for CPU/GPU/Sensor

        // Sensor module: single line
        if module.identifier == "sensor" {
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = 0
            paraStyle.paragraphSpacing = 0

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Tahoma", size: 10)!,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            attrString.append(NSAttributedString(string: module.summaryValue, attributes: valueAttrs))
        } else if module.identifier == "disk", let diskModule = module as? DiskModule {
            // Disk: two colored dots + speed values
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = -3
            paraStyle.paragraphSpacing = -3

            // Colors: orange for write (top), blue for read (bottom)
            let writeColor = NSColor.systemOrange
            let readColor = NSColor.systemBlue

            // Write line: ● + speed (smaller dot)
            let dotFont = NSFont.systemFont(ofSize: 5, weight: .regular)
            let writeAttrs: [NSAttributedString.Key: Any] = [
                .font: dotFont,
                .foregroundColor: writeColor,
                .paragraphStyle: paraStyle
            ]
            let writeValueAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            attrString.append(NSAttributedString(string: "● ", attributes: writeAttrs))
            attrString.append(NSAttributedString(string: diskModule.writeSpeedText + "\n", attributes: writeValueAttrs))

            // Read line: ● + speed (smaller dot)
            let readAttrs: [NSAttributedString.Key: Any] = [
                .font: dotFont,
                .foregroundColor: readColor,
                .paragraphStyle: paraStyle
            ]
            let readValueAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            attrString.append(NSAttributedString(string: "● ", attributes: readAttrs))
            attrString.append(NSAttributedString(string: diskModule.readSpeedText, attributes: readValueAttrs))

            // Calculate adaptive width for disk (similar to Stats Speed widget)
            let writeWidth = ("● " + diskModule.writeSpeedText).size(withAttributes: [.font: font]).width
            let readWidth = ("● " + diskModule.readSpeedText).size(withAttributes: [.font: font]).width
            calculatedWidth = max(writeWidth, readWidth) + 8  // Add padding
            calculatedWidth = max(calculatedWidth, 50)  // Minimum width for "123.4K" format
        } else if module.identifier == "network", let networkModule = module as? NetworkModule {
            // Network: colored arrows + speed values
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.alignment = .center
            paraStyle.lineSpacing = -3
            paraStyle.paragraphSpacing = -3

            // Colors: red for upload, blue for download
            let uploadColor = NSColor.systemRed
            let downloadColor = NSColor.systemBlue

            // Upload line: colored ↑ + speed (bolder arrow)
            let arrowFont = NSFont.systemFont(ofSize: 10, weight: .bold)
            let uploadAttrs: [NSAttributedString.Key: Any] = [
                .font: arrowFont,
                .foregroundColor: uploadColor,
                .paragraphStyle: paraStyle
            ]
            let uploadValueAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            attrString.append(NSAttributedString(string: "↑ ", attributes: uploadAttrs))
            attrString.append(NSAttributedString(string: networkModule.uploadSpeedText + "\n", attributes: uploadValueAttrs))

            // Download line: colored ↓ + speed (bolder arrow)
            let downloadAttrs: [NSAttributedString.Key: Any] = [
                .font: arrowFont,
                .foregroundColor: downloadColor,
                .paragraphStyle: paraStyle
            ]
            let downloadValueAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paraStyle
            ]
            attrString.append(NSAttributedString(string: "↓ ", attributes: downloadAttrs))
            attrString.append(NSAttributedString(string: networkModule.downloadSpeedText, attributes: downloadValueAttrs))

            // Calculate adaptive width for network (similar to Stats Speed widget)
            let uploadWidth = ("↑ " + networkModule.uploadSpeedText).size(withAttributes: [.font: font]).width
            let downloadWidth = ("↓ " + networkModule.downloadSpeedText).size(withAttributes: [.font: font]).width
            calculatedWidth = max(uploadWidth, downloadWidth) + 8  // Add padding
            calculatedWidth = max(calculatedWidth, 50)  // Minimum width for "123.4K" format
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

        // Update width if needed (adaptive for network/disk)
        if module.identifier == "network" || module.identifier == "disk" {
            let roundedWidth = (calculatedWidth * 2).rounded() / 2  // Round to nearest 0.5
            if item.length != roundedWidth {
                item.length = roundedWidth
            }
        }
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
