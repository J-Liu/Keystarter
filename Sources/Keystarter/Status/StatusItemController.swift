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
    private let refreshInterval: TimeInterval = 2.0
    
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
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        
        // Stack for icon + text
        let stack = NSStackView(frame: view.bounds)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.autoresizingMask = [.width, .height]
        view.addSubview(stack)
        
        // Icon (if available)
        if let icon = module.icon {
            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyDown
            stack.addArrangedSubview(imageView)
        }
        
        // Text
        let label = NSTextField(labelWithString: module.summaryText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .left
        stack.addArrangedSubview(label)
        
        // Store reference for updating
        view.identifier = NSUserInterfaceItemIdentifier(module.identifier)
        view.subviews.first?.subviews.compactMap { $0 as? NSTextField }.first?.identifier = NSUserInterfaceItemIdentifier("label")
        
        // Click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(moduleClicked(_:)))
        view.addGestureRecognizer(clickGesture)
        
        return view
    }
    
    // MARK: - Module Management
    
    private func loadEnabledModules() {
        let defaults = UserDefaults.standard
        
        // CPU module
        if defaults.bool(forKey: "status.cpu.enabled") {
            modules.append(CPUModule())
        }
        
        // Memory module
        if defaults.bool(forKey: "status.memory.enabled") {
            modules.append(MemoryModule())
        }
        
        // Network module
        if defaults.bool(forKey: "status.network.enabled") {
            modules.append(NetworkModule())
        }
        
        // Disk module
        if defaults.bool(forKey: "status.disk.enabled") {
            modules.append(DiskModule())
        }
        
        // GPU module
        if defaults.bool(forKey: "status.gpu.enabled") {
            modules.append(GPUModule())
        }
        
        // Sensor module
        if defaults.bool(forKey: "status.sensor.enabled") {
            modules.append(SensorModule())
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
        module.refreshSummary()
        updateModuleLabel(module)
    }
    
    func disableModule(_ identifier: String) {
        modules.removeAll { $0.identifier == identifier }
        removeModuleView(identifier)
    }
    
    // MARK: - Refresh
    
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }
    
    private func refreshAll() {
        for module in modules {
            module.refreshSummary()
            updateModuleLabel(module)
        }
    }
    
    private func updateModuleLabel(_ module: StatusModule) {
        guard let view = moduleViews[module.identifier],
              let stack = view.subviews.first as? NSStackView else { return }
        
        for subview in stack.arrangedSubviews {
            if let label = subview as? NSTextField {
                label.stringValue = module.summaryText
                break
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func moduleClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view,
              let identifier = view.identifier?.rawValue,
              let module = modules.first(where: { $0.identifier == identifier }) else { return }
        
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
        
        // Refresh all
        refreshAll()
    }
}

// MARK: - Notification

extension Notification.Name {
    static let statusModuleSettingsChanged = Notification.Name("statusModuleSettingsChanged")
}