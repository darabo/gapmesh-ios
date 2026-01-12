//
// PendingFileManager.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import BitLogger

/// Represents a file transfer that has been received but not yet accepted by the user.
/// Files are held in memory until explicitly accepted, preventing DoS via storage exhaustion.
struct PendingFileTransfer: Identifiable {
    let id: String
    let senderPeerID: PeerID
    let senderNickname: String
    let fileName: String?
    let mimeType: String?
    let content: Data
    let timestamp: Date
    let isPrivate: Bool

    var fileSize: Int { content.count }

    var displayName: String {
        if let name = fileName, !name.isEmpty {
            return name
        }
        let ext = MimeType(mimeType)?.defaultExtension ?? "bin"
        return "file.\(ext)"
    }

    var category: MimeType.Category {
        MimeType(mimeType)?.category ?? .file
    }
}

/// Manages pending file transfers with configurable limits to prevent memory exhaustion.
/// Files must be explicitly accepted before being written to disk.
final class PendingFileManager {

    /// Shared instance for app-wide pending file management
    static let shared = PendingFileManager()

    /// Configuration for pending file limits
    struct Config {
        /// Maximum number of pending files allowed
        let maxPendingCount: Int
        /// Maximum total size of all pending files in bytes
        let maxTotalBytes: Int
        /// Maximum age before automatic expiration (seconds)
        let expirationSeconds: TimeInterval

        static let `default` = Config(
            maxPendingCount: 10,
            maxTotalBytes: 5 * 1024 * 1024, // 5 MiB total
            expirationSeconds: 300 // 5 minutes
        )
    }

    private let config: Config
    private let queue = DispatchQueue(label: "chat.bitchat.pendingfiles", attributes: .concurrent)
    private var pendingFiles: [String: PendingFileTransfer] = [:]
    private var expirationTimer: Timer?

    /// Callback when a pending file is added
    var onPendingFileAdded: ((PendingFileTransfer) -> Void)?
    /// Callback when a pending file expires or is removed
    var onPendingFileRemoved: ((String) -> Void)?

    init(config: Config = .default) {
        self.config = config
        startExpirationTimer()
    }

    deinit {
        expirationTimer?.invalidate()
    }

    // MARK: - Public API

    /// Adds a file to the pending queue. Returns the pending file ID if successful, nil if rejected.
    /// Files may be rejected if limits are exceeded.
    @discardableResult
    func addPendingFile(
        senderPeerID: PeerID,
        senderNickname: String,
        fileName: String?,
        mimeType: String?,
        content: Data,
        isPrivate: Bool
    ) -> PendingFileTransfer? {
        let id = UUID().uuidString
        let pending = PendingFileTransfer(
            id: id,
            senderPeerID: senderPeerID,
            senderNickname: senderNickname,
            fileName: fileName,
            mimeType: mimeType,
            content: content,
            timestamp: Date(),
            isPrivate: isPrivate
        )

        return queue.sync(flags: .barrier) { [self] in
            // Check count limit
            if pendingFiles.count >= config.maxPendingCount {
                SecureLogger.warning("Pending file rejected: max count (\(config.maxPendingCount)) reached", category: .security)
                // Remove oldest file to make room
                if let oldest = pendingFiles.values.min(by: { $0.timestamp < $1.timestamp }) {
                    pendingFiles.removeValue(forKey: oldest.id)
                    SecureLogger.debug("Evicted oldest pending file \(oldest.id.prefix(8))... to make room", category: .session)
                }
            }

            // Check total size limit
            let currentTotal = pendingFiles.values.reduce(0) { $0 + $1.fileSize }
            if currentTotal + content.count > config.maxTotalBytes {
                SecureLogger.warning("Pending file rejected: would exceed max total size (\(config.maxTotalBytes) bytes)", category: .security)
                // Try to evict old files to make room
                var evictedSize = 0
                let sortedByAge = pendingFiles.values.sorted { $0.timestamp < $1.timestamp }
                for old in sortedByAge {
                    if currentTotal - evictedSize + content.count <= config.maxTotalBytes {
                        break
                    }
                    pendingFiles.removeValue(forKey: old.id)
                    evictedSize += old.fileSize
                    SecureLogger.debug("Evicted pending file \(old.id.prefix(8))... (\(old.fileSize) bytes) for space", category: .session)
                }

                // Check again after eviction
                let newTotal = pendingFiles.values.reduce(0) { $0 + $1.fileSize }
                if newTotal + content.count > config.maxTotalBytes {
                    SecureLogger.warning("Cannot accept pending file even after eviction", category: .security)
                    return nil
                }
            }

            pendingFiles[id] = pending
            SecureLogger.debug("Added pending file \(id.prefix(8))... from \(senderPeerID.id.prefix(8))... (\(content.count) bytes)", category: .session)

            DispatchQueue.main.async { [weak self] in
                self?.onPendingFileAdded?(pending)
            }

            return pending
        }
    }

    /// Retrieves a pending file by ID
    func getPendingFile(id: String) -> PendingFileTransfer? {
        queue.sync {
            pendingFiles[id]
        }
    }

    /// Retrieves all pending files
    func getAllPendingFiles() -> [PendingFileTransfer] {
        queue.sync {
            Array(pendingFiles.values).sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Accepts a pending file, saving it to disk and removing from pending queue.
    /// Returns the saved file URL, or nil if the file was not found or save failed.
    func acceptFile(id: String, saveHandler: (PendingFileTransfer) -> URL?) -> URL? {
        let pending = queue.sync(flags: .barrier) { () -> PendingFileTransfer? in
            pendingFiles.removeValue(forKey: id)
        }

        guard let pending = pending else {
            SecureLogger.warning("Cannot accept file \(id.prefix(8))...: not found in pending queue", category: .session)
            return nil
        }

        guard let url = saveHandler(pending) else {
            SecureLogger.error("Failed to save accepted file \(id.prefix(8))...", category: .session)
            return nil
        }

        SecureLogger.debug("Accepted and saved pending file \(id.prefix(8))... to \(url.lastPathComponent)", category: .session)
        return url
    }

    /// Declines/removes a pending file without saving
    func declineFile(id: String) {
        queue.sync(flags: .barrier) {
            if let removed = pendingFiles.removeValue(forKey: id) {
                SecureLogger.debug("Declined pending file \(id.prefix(8))... from \(removed.senderNickname)", category: .session)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPendingFileRemoved?(id)
        }
    }

    /// Clears all pending files (e.g., for panic mode)
    func clearAll() {
        let ids = queue.sync(flags: .barrier) { () -> [String] in
            let ids = Array(pendingFiles.keys)
            pendingFiles.removeAll()
            return ids
        }
        SecureLogger.debug("Cleared \(ids.count) pending files", category: .session)
        for id in ids {
            DispatchQueue.main.async { [weak self] in
                self?.onPendingFileRemoved?(id)
            }
        }
    }

    /// Returns current statistics
    var stats: (count: Int, totalBytes: Int) {
        queue.sync {
            (pendingFiles.count, pendingFiles.values.reduce(0) { $0 + $1.fileSize })
        }
    }

    // MARK: - Private

    private func startExpirationTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.expirationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.expireOldFiles()
            }
        }
    }

    private func expireOldFiles() {
        let now = Date()
        let expiredIDs = queue.sync(flags: .barrier) { () -> [String] in
            var expired: [String] = []
            for (id, pending) in pendingFiles {
                if now.timeIntervalSince(pending.timestamp) > config.expirationSeconds {
                    expired.append(id)
                    pendingFiles.removeValue(forKey: id)
                }
            }
            return expired
        }

        if !expiredIDs.isEmpty {
            SecureLogger.debug("Expired \(expiredIDs.count) pending files", category: .session)
            for id in expiredIDs {
                DispatchQueue.main.async { [weak self] in
                    self?.onPendingFileRemoved?(id)
                }
            }
        }
    }
}
