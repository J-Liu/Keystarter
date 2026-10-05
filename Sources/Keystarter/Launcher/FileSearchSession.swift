// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import CoreServices
import Foundation

/// File search result.
struct FileSearchResult: Hashable {
    let url: URL
    let isDirectory: Bool
    var id: String { url.path }
}

/// Async file search using Spotlight.
@MainActor
final class FileSearchSession {
    enum State: Equatable {
        case idle
        case searching
        case ready
        case failed
    }

    enum SearchMode {
        case fileName
        case content
    }

    private(set) var results: [FileSearchResult] = []
    private(set) var state: State = .idle

    private var revision = 0
    private var pendingQuery: String?
    private var workerTask: Task<Void, Never>?

    private let homeDirectory: URL
    private let debounce: Duration

    init() {
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        debounce = .milliseconds(150)
    }

    /// Search files asynchronously. Results delivered via callback.
    func search(
        query: String,
        mode: SearchMode = .fileName,
        scopes: [URL] = [],
        callback: @escaping @MainActor ([FileSearchResult]) -> Void
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancel()
            return
        }

        revision &+= 1
        let thisRevision = revision
        state = .searching

        // Cancel previous task
        workerTask?.cancel()

        // Debounce (shorter for content search)
        let debounceTime = mode == .content ? .milliseconds(100) : debounce

        workerTask = Task { [weak self] in
            guard let self else { return }

            let deadline = ContinuousClock.now.advanced(by: debounceTime)
            let delay = ContinuousClock.now.duration(to: deadline)
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            guard !Task.isCancelled, self.revision == thisRevision else { return }

            // Run Spotlight search in background
            let results = await Task.detached(priority: .userInitiated) {
                Self.spotlightSearch(query: trimmed, mode: mode, scopes: scopes, homeDirectory: self.homeDirectory)
            }.value

            guard self.revision == thisRevision else { return }

            self.results = results
            self.state = .ready
            callback(results)
        }
    }

    func cancel() {
        revision &+= 1
        workerTask?.cancel()
        workerTask = nil
        results = []
        state = .idle
    }

    /// Spotlight search (runs on background thread).
    private nonisolated static func spotlightSearch(
        query: String,
        mode: SearchMode,
        scopes: [URL],
        homeDirectory: URL
    ) -> [FileSearchResult] {
        // Build Spotlight query
        let expression: String
        if mode == .fileName {
            expression = "kMDItemFSName == '*\(query)*'c"
        } else {
            // Content search: search in file contents
            expression = "kMDItemTextContent == '*\(query)*'c"
        }

        // Default scopes: home directory
        let searchScopes = scopes.isEmpty ? [homeDirectory] : scopes

        // Create query
        guard let queryRef = MDQueryCreate(
            nil,
            expression as CFString,
            nil,
            [kMDItemFSName] as CFArray
        ) else {
            return []
        }

        MDQuerySetSearchScope(queryRef, searchScopes as CFArray, 0)
        MDQuerySetMaxCount(queryRef, mode == .content ? 20 : 50)

        // Execute synchronously (but we're in background thread)
        guard MDQueryExecute(queryRef, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            return []
        }

        // Collect results
        let count = MDQueryGetResultCount(queryRef)
        var results: [FileSearchResult] = []

        for i in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(queryRef, i) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }

            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isHiddenKey, .contentTypeKey
            ]),
            values.isHidden != true,
            values.contentType?.conforms(to: .application) != true
            else { continue }

            results.append(FileSearchResult(
                url: url,
                isDirectory: values.isDirectory == true
            ))
        }

        return results
    }
}