//
// NostrTransportTests.swift
// GapTests
//
// Tests for NostrTransport thread safety.
// This is free and unencumbered software released into the public domain.
//

import Testing
import Foundation
@testable import Gap_Mash

@Suite("NostrTransport Thread Safety")
struct NostrTransportTests {

    // MARK: - Thread Safety Tests

    @MainActor
    @Test func concurrentReadReceiptEnqueue() async throws {
        let keychain = MockKeychain()
        let idBridge = NostrIdentityBridge(keychain: keychain)
        let transport = NostrTransport(keychain: keychain, idBridge: idBridge)

        // Create multiple receipts
        let receiptCount = 100
        let receipts = (0..<receiptCount).map { i in
            ReadReceipt(
                originalMessageID: "msg-\(i)",
                readerID: PeerID(str: "reader-\(i)"),
                readerNickname: "Reader \(i)"
            )
        }

        // Enqueue all receipts concurrently
        await withTaskGroup(of: Void.self) { group in
            for (i, receipt) in receipts.enumerated() {
                group.addTask {
                    transport.sendReadReceipt(receipt, to: PeerID(str: "peer-\(i % 10)"))
                }
            }
        }

        // Allow processing time
        try await Task.sleep(for: .milliseconds(100))

        // Test passes if no crashes occurred during concurrent enqueue
        // The barrier-based synchronization should prevent race conditions
    }

    @MainActor
    @Test func readQueueProcessingUnderLoad() async throws {
        let keychain = MockKeychain()
        let idBridge = NostrIdentityBridge(keychain: keychain)
        let transport = NostrTransport(keychain: keychain, idBridge: idBridge)

        // Rapidly enqueue and let the queue process
        for i in 0..<50 {
            let receipt = ReadReceipt(
                originalMessageID: "rapid-msg-\(i)",
                readerID: PeerID(str: "rapid-reader-\(i)"),
                readerNickname: "Rapid Reader \(i)"
            )
            transport.sendReadReceipt(receipt, to: PeerID(str: "rapid-peer"))

            // Small delay to allow some processing
            if i % 10 == 0 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        // Allow full processing
        try await Task.sleep(for: .milliseconds(200))

        // Test passes if no crashes or deadlocks occurred
    }

    @MainActor
    @Test func isPeerReachableThreadSafety() async throws {
        let keychain = MockKeychain()
        let idBridge = NostrIdentityBridge(keychain: keychain)
        let transport = NostrTransport(keychain: keychain, idBridge: idBridge)

        let testPeerID = PeerID(str: "test-peer-12345678")

        // Concurrently check peer reachability
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    transport.isPeerReachable(testPeerID)
                }
            }

            // Collect results (we don't care about the values, just that it doesn't crash)
            for await _ in group {
                // Consume results
            }
        }

        // Test passes if no crashes occurred during concurrent access
    }

    @MainActor
    @Test func mixedOperationsThreadSafety() async throws {
        let keychain = MockKeychain()
        let idBridge = NostrIdentityBridge(keychain: keychain)
        let transport = NostrTransport(keychain: keychain, idBridge: idBridge)

        // Perform mixed operations concurrently
        await withTaskGroup(of: Void.self) { group in
            // Read receipts
            group.addTask {
                for i in 0..<20 {
                    let receipt = ReadReceipt(
                        originalMessageID: "mixed-msg-\(i)",
                        readerID: PeerID(str: "mixed-reader-\(i)"),
                        readerNickname: "Mixed Reader \(i)"
                    )
                    transport.sendReadReceipt(receipt, to: PeerID(str: "mixed-peer"))
                }
            }

            // Reachability checks
            group.addTask {
                for i in 0..<20 {
                    _ = transport.isPeerReachable(PeerID(str: "check-peer-\(i)"))
                }
            }

            // More read receipts from different "thread"
            group.addTask {
                for i in 20..<40 {
                    let receipt = ReadReceipt(
                        originalMessageID: "mixed-msg-\(i)",
                        readerID: PeerID(str: "mixed-reader-\(i)"),
                        readerNickname: "Mixed Reader \(i)"
                    )
                    transport.sendReadReceipt(receipt, to: PeerID(str: "mixed-peer-2"))
                }
            }
        }

        // Allow processing
        try await Task.sleep(for: .milliseconds(100))

        // Test passes if no crashes or race conditions occurred
    }
}
