// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Controller for the status bar item.
final class StatusItemController: NSObject {
    
    static let shared = StatusItemController()
    
    private var statusItems: [String: NSStatusItem] = [:]
    private var popover: NSPopover?
    private var moduleFrames: [String: NSRect] = [:]
    
    private var modules: [StatusModule] = []
    private var moduleViews: [String: NSView] = [:]
    
    private var refreshTimer: Timer?
    private var lastRefreshTimes: [String: Date] = [:]
    private let dataQueue = DispatchQueue(label: "com.keystarter.status.data", qos: .utility)
    
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
        // Create separate status item for each module
        for module in modules {
            let item = NSStatusBar.system.statusItem(withLength: 40)
            item.button?.title = ""
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier(module.identifier)

            // Create view inside button
            let view = createModuleView(module, frame: NSRect(x: 0, y: 0, width: 40, height: 22))
            item.button?.addSubview(view)
            item.button?.isBordered = false

            statusItems[module.identifier] = item
            moduleViews[module.identifier] = view
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let identifier = sender.identifier?.rawValue else {
            log("Click: no identifier")
            return
        }

        log("Status item clicked: \(identifier)")
        guard let module = modules.first(where: { $0.identifier == identifier }) else {
            log("No module found: \(identifier)")
            return
        }
        showPopover(for: module, from: sender)
    }

    private func handleContainerClick(at location: NSPoint) {
        // Find which module was clicked based on position
        for (identifier, frame) in moduleFrames {
            if frame.contains(location) {
                log("Click at \(location) -> module: \(identifier)")
                if let module = modules.first(where: { $0.identifier == identifier }),
                   let view = moduleViews[identifier] {
                    showPopover(for: module, from: view)
                }
                return
            }
        }
        log("Click at \(location) -> no module found")
    }

    private func addModuleView(_ module: StatusModule) {
        // Recalculate layout
        relayoutModuleViews()
    }

    private func removeModuleView(_ identifier: String) {
        moduleViews.removeValue(forKey: identifier)
        relayoutModuleViews()
    }

    private func relayoutModuleViews() {
        // Remove old status items
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()

        // Recreate status items for current modules
        for module in modules {
            let item = NSStatusBar.system.statusItem(withLength: 40)
            item.button?.title = ""
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier(module.identifier)

            let view = createModuleView(module, frame: NSRect(x: 0, y: 0, width: 40, height: 22))
            item.button?.addSubview(view)
            item.button?.isBordered = false

            statusItems[module.identifier] = item
            moduleViews[module.identifier] = view
        }
    }

    private func createModuleView(_ module: StatusModule, frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        // Vertical stack: name on top, value below
        let stack = NSStackView(frame: view.bounds)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.autoresizingMask = [.width, .height]
        view.addSubview(stack)

        // Name label (top)
        let nameLabel = NSTextField(labelWithString: module.shortName)
        nameLabel.font = .systemFont(ofSize: 9, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(nameLabel)

        // Value label (bottom)
        let valueLabel = NSTextField(labelWithString: module.summaryValue)
        valueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .center
        valueLabel.identifier = NSUserInterfaceItemIdentifier("valueLabel")
        stack.addArrangedSubview(valueLabel)

        return view
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
        guard let view = moduleViews[module.identifier],
              let stack = view.subviews.first as? NSStackView else { return }
        
        for subview in stack.arrangedSubviews {
            if let label = subview as? NSTextField, label.identifier?.rawValue == "valueLabel" {
                label.stringValue = module.summaryValue
                break
            }
        }
    }
    
    // MARK: - Actions

    private func showPopover(for module: StatusModule, from view: NSView) {
        popover?.close()

        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.contentViewController = NSViewController()
        newPopover.contentViewController?.view = module.makeDetailView()

        newPopover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        self.popover = newPopover
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
}

// MARK: - Notification

extension Notification.Name {
    static let statusModuleSettingsChanged = Notification.Name("statusModuleSettingsChanged")
}