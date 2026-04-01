import BitLogger
import Foundation
import Combine

/// Routes messages using available transports (Mesh, Nostr, etc.)
@MainActor
final class MessageRouter {
    private var transports: [Transport]
    private var outbox: [PeerID: [(content: String, nickname: String, messageID: String)]] = [:] // peerID -> queued messages

    init(transports: [Transport]) {
        self.transports = transports

        // Observe favorites changes to learn Nostr mapping and flush queued messages
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

    func addTransport(_ transport: Transport) {
        if !transports.contains(where: { $0 === transport }) {
            transports.append(transport)
        }
    }

    func sendPrivate(_ content: String, to peerID: PeerID, recipientNickname: String, messageID: String) {
        if let transport = bestReachableTransport(for: peerID) {
            SecureLogger.debug("Routing PM via \(type(of: transport)) to \(peerID.id.prefix(8))… id=\(messageID.prefix(8))…", category: .session)
            transport.sendPrivateMessage(content, to: peerID, recipientNickname: recipientNickname, messageID: messageID)
        } else {
            // Queue for later
            if outbox[peerID] == nil { outbox[peerID] = [] }
            outbox[peerID]?.append((content, recipientNickname, messageID))
            SecureLogger.debug("Queued PM for \(peerID.id.prefix(8))… (no reachable transport) id=\(messageID.prefix(8))…", category: .session)
        }
    }

    func sendReadReceipt(_ receipt: ReadReceipt, to peerID: PeerID) {
        if let transport = bestReachableTransport(for: peerID) {
            SecureLogger.debug("Routing READ ack via \(type(of: transport)) to \(peerID.id.prefix(8))… id=\(receipt.originalMessageID.prefix(8))…", category: .session)
            transport.sendReadReceipt(receipt, to: peerID)
        } else {
            SecureLogger.debug("No reachable transport for READ ack to \(peerID.id.prefix(8))…", category: .session)
        }
    }

    func sendDeliveryAck(_ messageID: String, to peerID: PeerID) {
        if let transport = bestReachableTransport(for: peerID) {
            SecureLogger.debug("Routing DELIVERED ack via \(type(of: transport)) to \(peerID.id.prefix(8))… id=\(messageID.prefix(8))…", category: .session)
            transport.sendDeliveryAck(for: messageID, to: peerID)
        }
    }

    func sendFavoriteNotification(to peerID: PeerID, isFavorite: Bool) {
        if let transport = bestReachableTransport(for: peerID, requireConnected: true) {
            transport.sendFavoriteNotification(to: peerID, isFavorite: isFavorite)
        } else if let transport = bestReachableTransport(for: peerID) {
            transport.sendFavoriteNotification(to: peerID, isFavorite: isFavorite)
        }
    }

    // MARK: - Outbox Management

    func flushOutbox(for peerID: PeerID) {
        guard let queued = outbox[peerID], !queued.isEmpty else { return }
        SecureLogger.debug("Flushing outbox for \(peerID.id.prefix(8))… count=\(queued.count)", category: .session)
        var remaining: [(content: String, nickname: String, messageID: String)] = []
        
        for (content, nickname, messageID) in queued {
            if let transport = bestReachableTransport(for: peerID) {
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

    func flushAllOutbox() {
        for key in Array(outbox.keys) { flushOutbox(for: key) }
    }

    private enum TransportTier: Int {
        case local = 0
        case p2p = 1
        case nostr = 2
        case other = 3
    }

    private func tier(for transport: Transport) -> TransportTier {
        if transport is NostrTransport { return .nostr }
        if transport is P2PTransport { return .p2p }
        let name = String(describing: type(of: transport))
        if name.contains("BLEService") || name.contains("WiFiAwareTransport") {
            return .local
        }
        return .other
    }

    private func bestReachableTransport(for peerID: PeerID, requireConnected: Bool = false) -> Transport? {
        let candidates = transports.filter { transport in
            requireConnected ? transport.isPeerConnected(peerID) : transport.isPeerReachable(peerID)
        }
        return candidates.min { lhs, rhs in
            tier(for: lhs).rawValue < tier(for: rhs).rawValue
        }
    }
}

/// Lightweight libp2p transport scaffold.
/// This keeps the app integration points stable while native bindings are wired.
final class P2PTransport: Transport {
    static let shared = P2PTransport()

    private enum Constants {
        static let enabledKey = "p2pEnabled"
        static let localPeerIDKey = "p2pLocalPeerID"
    }

    weak var delegate: BitchatDelegate?
    weak var peerEventsDelegate: TransportPeerEventsDelegate?

    var peerSnapshotPublisher: AnyPublisher<[TransportPeerSnapshot], Never> {
        Just([]).eraseToAnyPublisher()
    }

    var myPeerID: PeerID {
        PeerID(str: localPeerID ?? "")
    }

    var myNickname: String { "" }

    private var running = false
    private var localPeerID: String?

    private init() {
        if let existing = UserDefaults.standard.string(forKey: Constants.localPeerIDKey), !existing.isEmpty {
            localPeerID = existing
        }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Constants.enabledKey)
    }

    static func announcementPeerID() -> String? {
        guard isEnabled else { return nil }
        return shared.localPeerID
    }

    func setNickname(_ nickname: String) {}

    func startServices() {
        guard Self.isEnabled else {
            running = false
            return
        }
        guard !running else { return }
        if localPeerID == nil || localPeerID?.isEmpty == true {
            let generated = "gap-p2p-" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            localPeerID = generated
            UserDefaults.standard.set(generated, forKey: Constants.localPeerIDKey)
        }
        running = true
        SecureLogger.info("p2p_node_start_success", category: .session)
    }

    func stopServices() {
        running = false
    }

    func emergencyDisconnectAll() {
        running = false
    }

    func currentPeerSnapshots() -> [TransportPeerSnapshot] { [] }

    func isPeerConnected(_ peerID: PeerID) -> Bool {
        false
    }

    func isPeerReachable(_ peerID: PeerID) -> Bool {
        // Native libp2p send path is intentionally gated off until UniFFI bindings are wired.
        // Returning false guarantees no message loss from premature routing.
        false
    }

    func peerNickname(peerID: PeerID) -> String? { nil }
    func getPeerNicknames() -> [PeerID: String] { [:] }
    func getFingerprint(for peerID: PeerID) -> String? { nil }
    func getNoiseSessionState(for peerID: PeerID) -> LazyHandshakeState { .none }
    func triggerHandshake(with peerID: PeerID) {}
    func getNoiseService() -> NoiseEncryptionService {
        NoiseEncryptionService(keychain: KeychainManager())
    }
    func sendMessage(_ content: String, mentions: [String]) {}
    func sendPrivateMessage(_ content: String, to peerID: PeerID, recipientNickname: String, messageID: String) {}
    func sendReadReceipt(_ receipt: ReadReceipt, to peerID: PeerID) {}
    func sendFavoriteNotification(to peerID: PeerID, isFavorite: Bool) {}
    func sendBroadcastAnnounce() {}
    func sendDeliveryAck(for messageID: String, to peerID: PeerID) {}
}
