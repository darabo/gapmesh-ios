import BitLogger
import Foundation

/// The central routing engine that decides how to deliver a message.
/// It implements the "Dual Transport Architecture" by choosing between
/// Bluetooth Mesh (local/offline) and Nostr (internet/global) based on availability.
/// - Note: This class manages the "smart queuing" logic when no transport is available.
@MainActor
final class MessageRouter {
    // List of available transports (e.g., MeshService, NostrTransport)
    private var transports: [Transport]
    // Queue for messages that cannot be sent immediately (PeerID -> List of Messages)
    private var outbox: [PeerID: [(content: String, nickname: String, messageID: String)]] = [:]

    init(transports: [Transport]) {
        self.transports = transports

        // Observe favorites changes. If we learn a new Nostr key or identity for a peer (via "favorites"),
        // we might now be able to reach them, so we try to flush the outbox.
        NotificationCenter.default.addObserver(
            forName: .favoriteStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            if let data = note.userInfo?["peerPublicKey"] as? Data {
                let peerID = PeerID(publicKey: data)
                Task { @MainActor in
                    self.flushOutbox(for: peerID)
                }
            }
            // Handle key updates
            if let newKey = note.userInfo?["peerPublicKey"] as? Data,
               let _ = note.userInfo?["isKeyUpdate"] as? Bool {
                let peerID = PeerID(publicKey: newKey)
                Task { @MainActor in
                    self.flushOutbox(for: peerID)
                }
            }
        }
    }

    // Registers a new transport method dynamically.
    func addTransport(_ transport: Transport) {
        if !transports.contains(where: { $0 === transport }) {
            transports.append(transport)
        }
    }

    /// Sends a private message to a specific peer.
    /// 1. Checks if the peer is reachable via any transport (Mesh first, then Nostr).
    /// 2. If reachable, sends immediately.
    /// 3. If not, queues the message in the outbox.
    func sendPrivate(_ content: String, to peerID: PeerID, recipientNickname: String, messageID: String) {
        // Try to find a reachable transport
        if let transport = transports.first(where: { $0.isPeerReachable(peerID) }) {
            SecureLogger.debug("Routing PM via \(type(of: transport)) to \(peerID.id.prefix(8))… id=\(messageID.prefix(8))…", category: .session)
            transport.sendPrivateMessage(content, to: peerID, recipientNickname: recipientNickname, messageID: messageID)
        } else {
            // No transport reachable right now. Queue for later.
            if outbox[peerID] == nil { outbox[peerID] = [] }
            outbox[peerID]?.append((content, recipientNickname, messageID))
            SecureLogger.debug("Queued PM for \(peerID.id.prefix(8))… (no reachable transport) id=\(messageID.prefix(8))…", category: .session)
        }
    }

    /// Sends a read receipt to acknowledge that a message was viewed.
    /// - Note: Read receipts are "best effort" and not queued if delivery fails.
    func sendReadReceipt(_ receipt: ReadReceipt, to peerID: PeerID) {
        if let transport = transports.first(where: { $0.isPeerReachable(peerID) }) {
            SecureLogger.debug("Routing READ ack via \(type(of: transport)) to \(peerID.id.prefix(8))… id=\(receipt.originalMessageID.prefix(8))…", category: .session)
            transport.sendReadReceipt(receipt, to: peerID)
        } else if !transports.isEmpty {
            // Fallback strategy could go here, but currently we just log the failure.
            SecureLogger.debug("No reachable transport for READ ack to \(peerID.id.prefix(8))…", category: .session)
        }
    }

    /// Sends a delivery acknowledgment (distinct from read receipt).
    /// Indicates the message arrived at the device, not necessarily read by user.
    func sendDeliveryAck(_ messageID: String, to peerID: PeerID) {
        if let transport = transports.first(where: { $0.isPeerReachable(peerID) }) {
            SecureLogger.debug("Routing DELIVERED ack via \(type(of: transport)) to \(peerID.id.prefix(8))… id=\(messageID.prefix(8))…", category: .session)
            transport.sendDeliveryAck(for: messageID, to: peerID)
        }
    }

    /// Notifies a peer that they have been added/removed as a favorite.
    /// This is often used to exchange public keys or handshake.
    func sendFavoriteNotification(to peerID: PeerID, isFavorite: Bool) {
        if let transport = transports.first(where: { $0.isPeerConnected(peerID) }) {
            transport.sendFavoriteNotification(to: peerID, isFavorite: isFavorite)
        } else if let transport = transports.first(where: { $0.isPeerReachable(peerID) }) {
             transport.sendFavoriteNotification(to: peerID, isFavorite: isFavorite)
        } else {
            // If peer is not reachable, we cannot notify them.
        }
    }

    // MARK: - Outbox Management

    /// Retries sending queued messages for a specific peer.
    /// Called when a peer becomes reachable (e.g., they come into Bluetooth range or we find their Nostr key).
    func flushOutbox(for peerID: PeerID) {
        guard let queued = outbox[peerID], !queued.isEmpty else { return }
        SecureLogger.debug("Flushing outbox for \(peerID.id.prefix(8))… count=\(queued.count)", category: .session)
        var remaining: [(content: String, nickname: String, messageID: String)] = []
        
        for (content, nickname, messageID) in queued {
            if let transport = transports.first(where: { $0.isPeerReachable(peerID) }) {
                SecureLogger.debug("Outbox -> \(type(of: transport)) for \(peerID.id.prefix(8))… id=\(messageID.prefix(8))…", category: .session)
                transport.sendPrivateMessage(content, to: peerID, recipientNickname: nickname, messageID: messageID)
            } else {
                remaining.append((content, nickname, messageID))
            }
        }
        
        if remaining.isEmpty {
            outbox.removeValue(forKey: peerID)
        } else {
            outbox[peerID] = remaining
        }
    }

    /// Flushes the outbox for all peers.
    func flushAllOutbox() {
        for key in Array(outbox.keys) { flushOutbox(for: key) }
    }
}
