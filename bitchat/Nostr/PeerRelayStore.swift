import Foundation

/// In-memory store for relay URLs reported by BLE mesh peers.
///
/// When peers exchange `AnnouncementPacket`s, they include their known-good
/// Nostr relay URLs (TLV type 0x05). This store aggregates those relays
/// with a simple scoring system: each unique peer reporting a relay gives
/// it +1 score. Relays expire after 24 hours if not re-reported.
///
/// Usage:
///     PeerRelayStore.shared.addRelays(from: "peer123", urls: ["wss://relay.damus.io"])
///     let bestRelays = PeerRelayStore.shared.getTopRelays(count: 5)
///
final class PeerRelayStore: ObservableObject {
    static let shared = PeerRelayStore()

    struct PeerRelay {
        let url: String
        var reporters: Set<String>
        var lastReported: Date

        var score: Int { reporters.count }
    }

    @Published private(set) var relayCount: Int = 0

    private var relays: [String: PeerRelay] = [:]
    
    // A concurrent queue is used to make reads fast (allowing multiple reads at once),
    // while writes use a 'barrier' to act exclusively and avoid race conditions.
    private let queue = DispatchQueue(label: "com.gapmesh.peerrelaystore", attributes: .concurrent)
    private let expiryInterval: TimeInterval = 24 * 60 * 60  // 24 hours

    private init() {}

    /// Add relay URLs reported by a specific peer.
    /// - Parameters:
    ///   - peerID: Unique identifier of the reporting peer
    ///   - urls: List of relay URLs reported by this peer
    func addRelays(from peerID: String, urls: [String]) {
        // barrier means this block waits for all prior reads/writes to finish, 
        // and nobody else can read/write until this block completes. Thread safety!
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }

            for url in urls {
                // Normalize the URL so that "WSS://Relay.com " gets treated the same as "wss://relay.com"
                let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                // Only accept websocket URLs
                guard normalized.hasPrefix("wss://") || normalized.hasPrefix("ws://") else { continue }

                if var existing = self.relays[normalized] {
                    existing.reporters.insert(peerID)
                    existing.lastReported = Date()
                    self.relays[normalized] = existing
                } else {
                    self.relays[normalized] = PeerRelay(
                        url: normalized,
                        reporters: [peerID],
                        lastReported: Date()
                    )
                }
            }
            self.purgeExpired()
            let count = self.relays.count
            DispatchQueue.main.async {
                self.relayCount = count
            }
            #if DEBUG
            print("[PeerRelayStore] Added \(urls.count) relays from peer \(peerID), total: \(self.relays.count)")
            #endif
        }
    }

    /// Get the top-scored relays.
    /// - Parameter count: Maximum number of relays to return
    /// - Returns: List of relay URLs sorted by score (highest first)
    func getTopRelays(count: Int = 5) -> [String] {
        var result: [String] = []
        
        // queue.sync runs synchronously on the concurrent queue.
        // It's safe to read from the dictionary concurrently with other reads.
        queue.sync {
            purgeExpired()
            result = relays.values
                .sorted { $0.score > $1.score }
                .prefix(count)
                .map { $0.url }
        }
        return result
    }

    /// Get all known peer-reported relays with their scores.
    func getAllRelays() -> [String: Int] {
        var result: [String: Int] = [:]
        queue.sync {
            purgeExpired()
            result = relays.mapValues { $0.score }
        }
        return result
    }

    /// Clear all stored relays.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.relays.removeAll()
            DispatchQueue.main.async {
                self?.relayCount = 0
            }
        }
    }

    private func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-expiryInterval)
        relays = relays.filter { $0.value.lastReported > cutoff }
    }
}
