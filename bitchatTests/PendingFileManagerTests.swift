//
// PendingFileManagerTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
import Foundation
@testable import bitchat

/// Tests for BCH-01-002 fix: PendingFileManager prevents DoS via storage exhaustion
struct PendingFileManagerTests {

    @Test("addPendingFile stores file in memory")
    func addPendingFile_storesInMemory() {
        let manager = PendingFileManager(config: .default)
        defer { manager.clearAll() }

        let content = Data(repeating: 0x42, count: 1024)
        let pending = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223344"),
            senderNickname: "TestUser",
            fileName: "test.bin",
            mimeType: "application/octet-stream",
            content: content,
            isPrivate: false
        )

        #expect(pending != nil)
        #expect(pending?.fileSize == 1024)
        #expect(pending?.fileName == "test.bin")
        #expect(manager.stats.count == 1)
        #expect(manager.stats.totalBytes == 1024)
    }

    @Test("getPendingFile retrieves stored file")
    func getPendingFile_retrievesStoredFile() {
        let manager = PendingFileManager(config: .default)
        defer { manager.clearAll() }

        let content = Data(repeating: 0x42, count: 512)
        let pending = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223344"),
            senderNickname: "TestUser",
            fileName: "test.bin",
            mimeType: "image/png",
            content: content,
            isPrivate: false
        )

        guard let id = pending?.id else {
            Issue.record("Failed to add pending file")
            return
        }

        let retrieved = manager.getPendingFile(id: id)
        #expect(retrieved != nil)
        #expect(retrieved?.content == content)
    }

    @Test("declineFile removes file from queue")
    func declineFile_removesFromQueue() {
        let manager = PendingFileManager(config: .default)
        defer { manager.clearAll() }

        let content = Data(repeating: 0x42, count: 256)
        let pending = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223344"),
            senderNickname: "TestUser",
            fileName: "test.bin",
            mimeType: "application/octet-stream",
            content: content,
            isPrivate: false
        )

        guard let id = pending?.id else {
            Issue.record("Failed to add pending file")
            return
        }

        #expect(manager.stats.count == 1)
        manager.declineFile(id: id)
        #expect(manager.stats.count == 0)
        #expect(manager.getPendingFile(id: id) == nil)
    }

    @Test("clearAll removes all pending files")
    func clearAll_removesAllFiles() {
        let manager = PendingFileManager(config: .default)

        for i in 0..<5 {
            _ = manager.addPendingFile(
                senderPeerID: PeerID(str: "AABBCCDD1122334\(i)"),
                senderNickname: "User\(i)",
                fileName: "file\(i).bin",
                mimeType: "application/octet-stream",
                content: Data(repeating: UInt8(i), count: 100),
                isPrivate: false
            )
        }

        #expect(manager.stats.count == 5)
        manager.clearAll()
        #expect(manager.stats.count == 0)
    }

    @Test("count limit evicts oldest files")
    func countLimit_evictsOldestFiles() {
        let config = PendingFileManager.Config(
            maxPendingCount: 3,
            maxTotalBytes: 1_000_000,
            expirationSeconds: 300
        )
        let manager = PendingFileManager(config: config)
        defer { manager.clearAll() }

        // Add 3 files (at limit)
        var ids: [String] = []
        for i in 0..<3 {
            if let pending = manager.addPendingFile(
                senderPeerID: PeerID(str: "AABBCCDD1122334\(i)"),
                senderNickname: "User\(i)",
                fileName: "file\(i).bin",
                mimeType: "application/octet-stream",
                content: Data(repeating: UInt8(i), count: 100),
                isPrivate: false
            ) {
                ids.append(pending.id)
            }
        }

        #expect(manager.stats.count == 3)

        // Add 4th file - should evict oldest
        let fourth = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223349"),
            senderNickname: "User9",
            fileName: "file9.bin",
            mimeType: "application/octet-stream",
            content: Data(repeating: 0x99, count: 100),
            isPrivate: false
        )

        #expect(fourth != nil)
        #expect(manager.stats.count == 3) // Still at limit
        #expect(manager.getPendingFile(id: ids[0]) == nil) // Oldest evicted
        #expect(manager.getPendingFile(id: ids[1]) != nil) // Second still exists
    }

    @Test("size limit evicts files to make room")
    func sizeLimit_evictsFilesToMakeRoom() {
        let config = PendingFileManager.Config(
            maxPendingCount: 100,
            maxTotalBytes: 500, // Very small limit for testing
            expirationSeconds: 300
        )
        let manager = PendingFileManager(config: config)
        defer { manager.clearAll() }

        // Add 2 files totaling 400 bytes (under limit)
        let first = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223340"),
            senderNickname: "User0",
            fileName: "file0.bin",
            mimeType: "application/octet-stream",
            content: Data(repeating: 0x00, count: 200),
            isPrivate: false
        )

        _ = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223341"),
            senderNickname: "User1",
            fileName: "file1.bin",
            mimeType: "application/octet-stream",
            content: Data(repeating: 0x01, count: 200),
            isPrivate: false
        )

        #expect(manager.stats.count == 2)
        #expect(manager.stats.totalBytes == 400)

        // Add 300-byte file - needs to evict to fit
        let third = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223342"),
            senderNickname: "User2",
            fileName: "file2.bin",
            mimeType: "application/octet-stream",
            content: Data(repeating: 0x02, count: 300),
            isPrivate: false
        )

        #expect(third != nil)
        // First file should be evicted to make room
        #expect(manager.getPendingFile(id: first!.id) == nil)
        #expect(manager.stats.totalBytes <= 500)
    }

    @Test("acceptFile saves and removes from queue")
    func acceptFile_savesAndRemovesFromQueue() {
        let manager = PendingFileManager(config: .default)
        defer { manager.clearAll() }

        let content = Data(repeating: 0x42, count: 128)
        let pending = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223344"),
            senderNickname: "TestUser",
            fileName: "test.bin",
            mimeType: "application/octet-stream",
            content: content,
            isPrivate: false
        )

        guard let id = pending?.id else {
            Issue.record("Failed to add pending file")
            return
        }

        #expect(manager.stats.count == 1)

        var savedURL: URL?
        let resultURL = manager.acceptFile(id: id) { pending in
            // Simulate saving - just return a fake URL for testing
            savedURL = URL(fileURLWithPath: "/tmp/test-\(pending.id).bin")
            return savedURL
        }

        #expect(resultURL == savedURL)
        #expect(manager.stats.count == 0) // Removed from queue
        #expect(manager.getPendingFile(id: id) == nil)
    }

    @Test("getAllPendingFiles returns sorted by timestamp descending")
    func getAllPendingFiles_sortedByTimestampDescending() async throws {
        let manager = PendingFileManager(config: .default)
        defer { manager.clearAll() }

        // Add files with small delays to ensure different timestamps
        for i in 0..<3 {
            _ = manager.addPendingFile(
                senderPeerID: PeerID(str: "AABBCCDD1122334\(i)"),
                senderNickname: "User\(i)",
                fileName: "file\(i).bin",
                mimeType: "application/octet-stream",
                content: Data(repeating: UInt8(i), count: 50),
                isPrivate: false
            )
            try await Task.sleep(for: .milliseconds(10))
        }

        let all = manager.getAllPendingFiles()
        #expect(all.count == 3)

        // Should be sorted newest first
        for i in 0..<(all.count - 1) {
            #expect(all[i].timestamp >= all[i + 1].timestamp)
        }
    }

    @Test("displayName returns fileName or generates default")
    func displayName_returnsFileNameOrGeneratesDefault() {
        let manager = PendingFileManager(config: .default)
        defer { manager.clearAll() }

        // With fileName
        let withName = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223344"),
            senderNickname: "TestUser",
            fileName: "custom.png",
            mimeType: "image/png",
            content: Data(repeating: 0x42, count: 100),
            isPrivate: false
        )
        #expect(withName?.displayName == "custom.png")

        // Without fileName - should use extension from MIME
        let withoutName = manager.addPendingFile(
            senderPeerID: PeerID(str: "AABBCCDD11223345"),
            senderNickname: "TestUser2",
            fileName: nil,
            mimeType: "audio/mp3",
            content: Data(repeating: 0x43, count: 100),
            isPrivate: false
        )
        #expect(withoutName?.displayName == "file.mp3")
    }
}
