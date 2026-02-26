import Foundation
import BitLogger

/// Synchronous media cleanup that can run inline during a `.background` scene-phase
/// transition or from a `BGProcessingTask`.
///
/// Deletes **outgoing** media older than 1 hour to reduce the forensic attack surface.
/// Incoming files are left untouched — the user may still want to view them.
///
/// Reference: Noghteha ships `MessageCleanupWorker` + `StaleDataCleanupWorker` on Android.
enum MediaCleanupTask {

    /// Maximum age of outgoing files before deletion (1 hour).
    static let outgoingMaxAge: TimeInterval = 3600

    /// Maximum age for stale temp/cache files (7 days).
    static let staleMaxAge: TimeInterval = 7 * 24 * 3600

    // MARK: - Public API

    /// Deletes outgoing media files older than `outgoingMaxAge`.
    /// Safe to call from any thread.
    static func cleanOutgoingMedia() {
        let fm = FileManager.default

        guard let base = applicationFilesDirectory() else {
            SecureLogger.warning("MediaCleanupTask: could not resolve files directory", category: .session)
            return
        }

        let outgoingSubdirs = [
            "images/outgoing",
            "files/outgoing",
            "voicenotes/outgoing"
        ]

        let cutoff = Date().addingTimeInterval(-outgoingMaxAge)
        var deleted = 0

        for subdir in outgoingSubdirs {
            let dir = base.appendingPathComponent(subdir)
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files {
                guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = attrs.contentModificationDate,
                      modified < cutoff else { continue }
                do {
                    try fm.removeItem(at: file)
                    deleted += 1
                } catch {
                    SecureLogger.warning("MediaCleanupTask: failed to delete \(file.lastPathComponent) – \(error.localizedDescription)", category: .session)
                }
            }
        }

        SecureLogger.info("MediaCleanupTask: deleted \(deleted) outgoing files", category: .session)
    }

    /// Removes zero-byte orphan files and empty directories older than `staleMaxAge`.
    static func cleanStaleData() {
        let fm = FileManager.default
        guard let base = applicationFilesDirectory() else { return }

        let cutoff = Date().addingTimeInterval(-staleMaxAge)
        var cleaned = 0

        let subdirs = ["images", "files", "voicenotes"]
        for subdir in subdirs {
            let root = base.appendingPathComponent(subdir)
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            var emptyDirs: [URL] = []

            while let url = enumerator.nextObject() as? URL {
                guard let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else { continue }

                if vals.isDirectory == true {
                    // Collect for potential empty-dir cleanup
                    emptyDirs.append(url)
                    continue
                }

                // Remove zero-byte files older than threshold
                if vals.fileSize == 0, let mod = vals.contentModificationDate, mod < cutoff {
                    try? fm.removeItem(at: url)
                    cleaned += 1
                }
            }

            // Remove empty dirs bottom-up
            for dir in emptyDirs.reversed() {
                let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                if contents.isEmpty {
                    try? fm.removeItem(at: dir)
                }
            }
        }

        SecureLogger.info("MediaCleanupTask: stale cleanup removed \(cleaned) orphan files", category: .session)
    }

    // MARK: - Private helpers

    private static func applicationFilesDirectory() -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = base.appendingPathComponent("files", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }
}
