// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CommonCrypto

/// Monitors clipboard changes and stores history.
final class ClipboardManager {

    static let shared = ClipboardManager()

    private var timer: Timer?
    private var lastChangeCount: Int = 0

    private var db: IndexDatabase? {
        (NSApp.delegate as? AppDelegate)?.indexDB
    }

    /// Start monitoring clipboard.
    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    /// Stop monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        print("[Clipboard] Change detected: \(currentCount)")
        processClipboard()
    }

    private func processClipboard() {
        let pasteboard = NSPasteboard.general

        // Skip concealed content (passwords)
        if pasteboard.types?.contains(.init(rawValue: "org.nspasteboard.ConcealedType")) == true {
            print("[Clipboard] Skipping concealed content")
            return
        }

        // Prefer text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            print("[Clipboard] Text found: \(text.prefix(50))...")
            let hash = sha256(text)
            guard let database = db else {
                print("[Clipboard] Database not ready")
                return
            }
            let inserted = database.insertClipboard(type: "text", content: text, hash: hash)
            print("[Clipboard] Inserted: \(inserted)")
            return
        }

        // Then image
        if UserDefaults.standard.bool(forKey: "clipboard.recordImages") {
            if let image = NSImage(pasteboard: pasteboard) {
                print("[Clipboard] Image found")
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
                saveImage(pngData)
            }
        }
    }

    private func saveImage(_ data: Data) {
        let dir = NSHomeDirectory() + "/Library/Application Support/Keystarter/clipboard"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".png"
        let path = dir + "/" + filename
        try? data.write(to: URL(fileURLWithPath: path))
        let hash = sha256(data)
        _ = db?.insertClipboard(type: "image", content: path, hash: hash)
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

    // MARK: - Config

    private var maxCount: Int {
        UserDefaults.standard.integer(forKey: "clipboard.maxCount")
    }

    private var maxDays: Int {
        UserDefaults.standard.integer(forKey: "clipboard.maxDays")
    }
}