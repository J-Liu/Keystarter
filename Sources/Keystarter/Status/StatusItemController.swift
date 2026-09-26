// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Controller for the status bar item.
final class StatusItemController: NSObject {
    
    static let shared = StatusItemController()
    
    private var statusItem: NSStatusItem?
    private var containerView: NSView?
    private var stackView: NSStackView?
    private var popover: NSPopover?
    
    private var modules: [StatusModule] = []
    private var moduleViews: [String: NSView] = [:]
    
    private var refreshTimer: Timer?
    private var lastRefreshTimes: [String: Date] = [:]
    private let dataQueue = DispatchQueue(label: "com.keystarter.status.data", qos: .utility)
    
    override init() {
        super.init()
        loadEnabledModules()
        setupStatusItem()
        startRefreshTimer()
        
        // Listen for settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .statusModuleSettingsChanged,
            object: nil
        )
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else { return }
        
        // Create container view
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        container.wantsLayer = true
        
        // Create stack view
        let stack = NSStackView(frame: container.bounds)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.autoresizingMask = [.width, .height]
        container.addSubview(stack)
        
        containerView = container
        stackView = stack
        
        // Add module views
        for module in modules {
            addModuleView(module)
        }
        
        // Update status item button with custom view
        if let button = statusItem.button {
            button.addSubview(container)
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                container.topAnchor.constraint(equalTo: button.topAnchor),
                container.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
    }
    
    private func addModuleView(_ module: StatusModule) {
        let view = createModuleView(module)
        stackView?.addArrangedSubview(view)
        moduleViews[module.identifier] = view
    }
    
    private func removeModuleView(_ identifier: String) {
        guard let view = moduleViews[identifier] else { return }
        stackView?.removeArrangedSubview(view)
        view.removeFromSuperview()
        moduleViews.removeValue(forKey: identifier)
    }
    
    private func createModuleView(_ module: StatusModule) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 22))
        
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
        stack.addArrangedSubview(valueLabel)
        
        // Store reference for updating
        view.identifier = NSUserInterfaceItemIdentifier(module.identifier)
        valueLabel.identifier = NSUserInterfaceItemIdentifier("valueLabel")
        
        // Click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(moduleClicked(_:)))
        view.addGestureRecognizer(clickGesture)
        
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
    
    @objc private func moduleClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view,
              let identifier = view.identifier?.rawValue else {
            print("DEBUG: No view or identifier found")
            return
        }
        
        guard let module = modules.first(where: { $0.identifier == identifier }) else {
            print("DEBUG: No module found for identifier: \(identifier), modules: \(modules.map { $0.identifier })")
            return
        }
        
        print("DEBUG: Showing popover for module: \(module.identifier)")
        showPopover(for: module, from: view)
    }
    
    private func showPopover(for module: StatusModule, from view: NSView) {
        popover?.close()
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = module.makeDetailView()
        
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        self.popover = popover
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