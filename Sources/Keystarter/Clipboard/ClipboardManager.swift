// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CommonCrypto

/// Monitors clipboard changes and stores history.
final class ClipboardManager {

    static let shared = ClipboardManager()
    let db = ClipboardDatabase()

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var logFile: URL?

    /// Start monitoring clipboard.
    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        setupLogFile()
        log("ClipboardManager started, initial count: \(lastChangeCount)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func setupLogFile() {
        let dir = NSHomeDirectory() + "/Library/Application Support/Keystarter"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        logFile = URL(fileURLWithPath: dir + "/clipboard.log")
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        guard let file = logFile else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Stop monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
        log("ClipboardManager stopped")
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        log("Change detected: \(currentCount)")
        processClipboard()
    }

    private func processClipboard() {
        let pasteboard = NSPasteboard.general

        // Skip concealed content (passwords)
        if pasteboard.types?.contains(.init(rawValue: "org.nspasteboard.ConcealedType")) == true {
            log("Skipping concealed content")
            return
        }

        // Check for image data first (before text)
        if let image = NSImage(pasteboard: pasteboard) {
            log("Image found in pasteboard")
            // Process image in background to avoid blocking UI
            DispatchQueue.global(qos: .background).async { [weak self] in
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    self?.log("Failed to convert image to PNG")
                    return
                }
                self?.saveImage(pngData)
            }
            return
        }

        // Then text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            log("Text found: \(text.prefix(50))...")
            let hash = sha256(text)
            let inserted = db.insertClipboard(type: "text", content: text, hash: hash)
            log("Inserted: \(inserted)")
            return
        }
    }

    private func saveImage(_ data: Data) {
        let dir = NSHomeDirectory() + "/Library/Application Support/Keystarter/clipboard"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".png"
        let path = dir + "/" + filename
        try? data.write(to: URL(fileURLWithPath: path))
        let hash = sha256(data)
        let inserted = db.insertClipboard(type: "image", content: path, hash: hash)
        log("Image saved: \(filename), inserted: \(inserted)")
    }

    private func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    private func sha256(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { ptr in
            CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}