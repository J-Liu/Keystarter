// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Watches directories for file changes using FSEvents and updates the index incrementally.
final class IndexWatcher {

    private let db: IndexDatabase
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.keystarter.index.watcher", qos: .utility)
    private let ignoredDirs: Set<String> = [
        "node_modules", "target", ".venv", "venv", "env",
        "__pycache__", ".git", ".pytest_cache", ".mypy_cache",
        ".ruff_cache", "dist", "build", ".build", ".next", ".nuxt",
        "DerivedData", "Pods", "Carthage", ".Trash", "Library"
    ]
    
    // Debounce: collect events and process in batch
    private var pendingEvents: [(path: String, flag: FSEventStreamEventFlags)] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.5

    init(db: IndexDatabase) {
        self.db = db
    }

    deinit {
        stop()
    }

    /// Start watching the given root directories.
    func start(roots: [String]) {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<IndexWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            let flags = eventFlags
            watcher.handleEvents(numEvents: Int(numEvents), paths: paths, flags: flags)
        }

        guard let fsStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            print("[IndexWatcher] Failed to create FSEventStream")
            return
        }

        stream = fsStream
        FSEventStreamSetDispatchQueue(fsStream, queue)
        FSEventStreamStart(fsStream)
        print("[IndexWatcher] Started watching: \(roots)")
    }

    /// Stop watching.
    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        print("[IndexWatcher] Stopped")
    }

    private func handleEvents(numEvents: Int, paths: UnsafePointer<UnsafePointer<CChar>>, flags: UnsafePointer<FSEventStreamEventFlags>) {
        // Collect events with debounce
        queue.sync {
            for i in 0..<numEvents {
                let path = String(cString: paths[i])
                let flag = flags[i]
                
                // Skip events for ignored directories
                if shouldIgnore(path: path) { continue }
                
                pendingEvents.append((path: path, flag: flag))
            }
            
            // Cancel previous debounce work item
            debounceWorkItem?.cancel()
            
            // Schedule batch processing after debounce interval
            let workItem = DispatchWorkItem { [weak self] in
                self?.processPendingEvents()
            }
            debounceWorkItem = workItem
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        }
    }
    
    private func processPendingEvents() {
        var events: [(path: String, flag: FSEventStreamEventFlags)] = []
        queue.sync {
            events = pendingEvents
            pendingEvents.removeAll()
        }
        
        // Process batch
        for event in events {
            let path = event.path
            let flag = event.flag
            
            let isRemoved = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)) != 0
            let isCreated = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
            let isRenamed = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0

            if isRemoved {
                db.delete(path: path)
            } else if isCreated || isRenamed {
                let fm = FileManager.default
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir) {
                    let name = (path as NSString).lastPathComponent
                    if !name.hasPrefix(".") {
                        let modifiedAt = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date)
                        db.upsert(path: path, name: name, isDir: isDir.boolValue, modifiedAt: modifiedAt)
                    }
                }
            }
        }
    }

    private func shouldIgnore(path: String) -> Bool {
        let components = path.split(separator: "/")
        for component in components {
            if ignoredDirs.contains(String(component)) {
                return true
            }
        }
        return false
    }
}