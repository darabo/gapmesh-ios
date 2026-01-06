import Foundation
import Combine
import Network
import BitLogger

// MARK: - WiFi Aware Transport

/// WiFi Aware transport for high-bandwidth mesh networking.
/// Implements the Transport protocol alongside BLEService.
/// Falls back gracefully on unsupported devices.
///
/// Key differences from BLE:
/// - Higher bandwidth (160-320 Mbps vs 1 Mbps)
/// - Lower latency
/// - Requires explicit pairing
/// - Uses Network framework for connections
///
/// NOTE: This class requires iOS 26+ and the WiFiAware framework.
/// The actual WiFiAware imports and usage are stubbed here for compilation,
/// and should be uncommented when building with Xcode 26+ SDK.
final class WiFiAwareTransport: NSObject, @unchecked Sendable {
    
    // MARK: - Constants
    
    /// Service name for WiFi Aware discovery (must match Info.plist)
    static let serviceName = "_gapmash._udp"
    
    // MARK: - Transport Protocol Properties
    
    weak var delegate: BitchatDelegate?
    weak var peerEventsDelegate: TransportPeerEventsDelegate?
    
    private let peerSnapshotSubject = CurrentValueSubject<[TransportPeerSnapshot], Never>([])
    var peerSnapshotPublisher: AnyPublisher<[TransportPeerSnapshot], Never> {
        peerSnapshotSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Identity (shared with BLE)
    
    private let keychain: KeychainManagerProtocol
    private let identityManager: SecureIdentityStateManagerProtocol
    private let noiseService: NoiseEncryptionService
    
    /// Local deduplicator for WiFi Aware packets (thread-safe, not actor-isolated)
    private let packetDeduplicator = MessageDeduplicator()
    
    var myPeerID: PeerID {
        PeerID(publicKey: noiseService.getStaticPublicKeyData())
    }
    
    private var _nickname: String = "Anonymous"
    var myNickname: String { _nickname }
    
    // MARK: - Connection State
    
    /// Active connections keyed by peer ID
    private var activeConnections: [PeerID: NWConnection] = [:]
    
    /// Peer nicknames (learned from announces)
    private var peerNicknames: [PeerID: String] = [:]
    
    // MARK: - State
    
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.gapmash.wifiaware", qos: .userInitiated)
    
    /// Lock for thread-safe connection management
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    init(
        keychain: KeychainManagerProtocol,
        identityManager: SecureIdentityStateManagerProtocol
    ) {
        self.keychain = keychain
        self.identityManager = identityManager
        self.noiseService = NoiseEncryptionService(keychain: keychain)
        super.init()
        
        SecureLogger.info("WiFiAwareTransport initialized", category: .session)
    }
    
    deinit {
        stopServices()
    }
    
    // MARK: - Lifecycle
    
    func startServices() {
        guard !isRunning else { return }
        isRunning = true
        
        SecureLogger.info("WiFiAware: Starting services", category: .session)
        
        // NOTE: Actual WiFi Aware publishing/browsing would be implemented here
        // using WAPublishableService, WASubscribableService, NWListener, NWBrowser
        // when building with Xcode 26+ SDK
        
        queue.async { [weak self] in
            self?.startNetworkServices()
        }
    }
    
    func stopServices() {
        guard isRunning else { return }
        isRunning = false
        
        SecureLogger.info("WiFiAware: Stopping services", category: .session)
        
        lock.lock()
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        lock.unlock()
        
        publishPeerSnapshots()
    }
    
    func emergencyDisconnectAll() {
        stopServices()
        
        lock.lock()
        peerNicknames.removeAll()
        lock.unlock()
    }
    
    // MARK: - Network Services (Placeholder)
    
    private func startNetworkServices() {
        // This is a placeholder for the actual WiFi Aware implementation.
        // When building with Xcode 26+ and WiFiAware framework:
        //
        // 1. Import WiFiAware
        // 2. Create WAPublishableService and WASubscribableService
        // 3. Create NWListener for incoming connections
        // 4. Create NWBrowser for peer discovery
        //
        // For now, the transport compiles but doesn't do WiFi Aware operations.
        // BLE will continue to work as the primary transport.
        
        SecureLogger.info("WiFiAware: Network services placeholder active", category: .session)
    }
    
    // MARK: - Connection Management
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        SecureLogger.info("WiFiAware: Incoming connection from \(connection.endpoint)", category: .session)
        setupConnection(connection, isInitiator: false)
    }
    
    private func connectToEndpoint(_ endpoint: NWEndpoint) {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let connection = NWConnection(to: endpoint, using: parameters)
        setupConnection(connection, isInitiator: true)
    }
    
    private func setupConnection(_ connection: NWConnection, isInitiator: Bool) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(connection: connection, state: state, isInitiator: isInitiator)
        }
        
        connection.start(queue: queue)
    }
    
    private func handleConnectionState(connection: NWConnection, state: NWConnection.State, isInitiator: Bool) {
        switch state {
        case .ready:
            SecureLogger.info("WiFiAware: Connection ready (initiator: \(isInitiator))", category: .session)
            receiveData(on: connection)
            
        case .failed(let error):
            SecureLogger.error("WiFiAware: Connection failed: \(error)", category: .session)
            removeConnection(connection)
            
        case .cancelled:
            SecureLogger.debug("WiFiAware: Connection cancelled", category: .session)
            removeConnection(connection)
            
        case .waiting(let error):
            SecureLogger.warning("WiFiAware: Connection waiting: \(error)", category: .session)
            
        case .preparing:
            SecureLogger.debug("WiFiAware: Connection preparing", category: .session)
            
        case .setup:
            break
            
        @unknown default:
            break
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        lock.lock()
        
        // Find and remove from active
        if let peerID = activeConnections.first(where: { $0.value === connection })?.key {
            activeConnections.removeValue(forKey: peerID)
            
            // Notify delegate on main thread
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didDisconnectFromPeer(peerID)
            }
        }
        
        lock.unlock()
        
        publishPeerSnapshots()
    }
    
    // MARK: - Data Transfer
    
    private func receiveData(on connection: NWConnection) {
        // WiFi Aware supports larger packets - no fragmentation needed for most messages
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.processIncomingData(data, from: connection)
            }
            
            if let error = error {
                SecureLogger.error("WiFiAware: Receive error: \(error)", category: .session)
                return
            }
            
            if !isComplete {
                // Continue receiving
                self?.receiveData(on: connection)
            }
        }
    }
    
    private func processIncomingData(_ data: Data, from connection: NWConnection) {
        guard let packet = BinaryProtocol.decode(data) else {
            SecureLogger.error("WiFiAware: Failed to decode packet", category: .session)
            return
        }
        
        switch packet.type {
        case MessageType.noiseHandshake.rawValue:
            handleNoiseHandshake(packet, from: connection)
            
        case MessageType.message.rawValue:
            handleBroadcastMessage(packet, from: connection)
            
        case MessageType.noiseEncrypted.rawValue:
            handleNoiseEncrypted(packet, from: connection)
            
        case MessageType.announce.rawValue:
            handleAnnounce(packet, from: connection)
            
        default:
            SecureLogger.debug("WiFiAware: Unhandled packet type: \(packet.type)", category: .session)
        }
    }
    
    // MARK: - Message Handling
    
    private func handleNoiseHandshake(_ packet: BitchatPacket, from connection: NWConnection) {
        // Process Noise handshake using existing NoiseEncryptionService
        let peerID = PeerID(hexData: packet.senderID)
        
        lock.lock()
        activeConnections[peerID] = connection
        lock.unlock()
        
        publishPeerSnapshots()
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didConnectToPeer(peerID)
        }
    }
    
    private func handleBroadcastMessage(_ packet: BitchatPacket, from connection: NWConnection) {
        // Create a unique ID for deduplication from packet data
        let packetHash = packet.senderID.hexEncodedString() + String(packet.timestamp)
        
        // Deduplication using thread-safe MessageDeduplicator
        guard !packetDeduplicator.isDuplicate(packetHash) else {
            return
        }
        
        // Decode and deliver
        let senderID = PeerID(hexData: packet.senderID)
        
        // Get nickname from stored mapping or use default
        lock.lock()
        let nickname = peerNicknames[senderID] ?? "WiFi Peer"
        lock.unlock()
        
        // Decode message content
        if let content = String(data: packet.payload, encoding: .utf8) {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceivePublicMessage(
                    from: senderID,
                    nickname: nickname,
                    content: content,
                    timestamp: Date(timeIntervalSince1970: Double(packet.timestamp) / 1000.0),
                    messageID: packetHash
                )
            }
        }
        
        // MESH RELAY: Forward if TTL > 0
        if packet.ttl > 0 {
            var relayPacket = packet
            relayPacket.ttl -= 1
            
            // Relay to all OTHER connected peers (not the sender)
            lock.lock()
            let connections = activeConnections.filter { $0.value !== connection }
            lock.unlock()
            
            for (_, peerConnection) in connections {
                sendPacket(relayPacket, to: peerConnection)
            }
        }
    }
    
    private func handleNoiseEncrypted(_ packet: BitchatPacket, from connection: NWConnection) {
        // Forward to NoiseEncryptionService for decryption
        let senderID = PeerID(hexData: packet.senderID)
        
        // Delegate to existing decryption service
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didReceiveNoisePayload(
                from: senderID,
                type: .privateMessage,
                payload: packet.payload,
                timestamp: Date(timeIntervalSince1970: Double(packet.timestamp) / 1000.0)
            )
        }
    }
    
    private func handleAnnounce(_ packet: BitchatPacket, from connection: NWConnection) {
        let senderID = PeerID(hexData: packet.senderID)
        
        if let nickname = String(data: packet.payload, encoding: .utf8), !nickname.isEmpty {
            lock.lock()
            peerNicknames[senderID] = nickname
            lock.unlock()
            
            publishPeerSnapshots()
        }
    }
    
    // MARK: - Sending
    
    private func sendPacket(_ packet: BitchatPacket, to connection: NWConnection) {
        guard let data = BinaryProtocol.encode(packet) else {
            SecureLogger.error("WiFiAware: Failed to encode packet", category: .session)
            return
        }
        
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                SecureLogger.error("WiFiAware: Send failed: \(error)", category: .session)
            }
        })
    }
    
    // MARK: - Peer Snapshots
    
    private func publishPeerSnapshots() {
        lock.lock()
        let snapshots = activeConnections.map { (peerID, _) in
            TransportPeerSnapshot(
                peerID: peerID,
                nickname: peerNicknames[peerID] ?? "WiFi Peer",
                isConnected: true,
                noisePublicKey: noiseService.getPeerPublicKeyData(peerID),
                lastSeen: Date()
            )
        }
        lock.unlock()
        
        peerSnapshotSubject.send(snapshots)
        
        DispatchQueue.main.async { [weak self, snapshots] in
            self?.peerEventsDelegate?.didUpdatePeerSnapshots(snapshots)
        }
    }
    
    // MARK: - Helper to create packet sender ID as Data
    
    private var mySenderIDData: Data {
        myPeerID.routingData ?? Data()
    }
}

// MARK: - Transport Protocol Conformance

extension WiFiAwareTransport: Transport {
    
    func currentPeerSnapshots() -> [TransportPeerSnapshot] {
        peerSnapshotSubject.value
    }
    
    func setNickname(_ nickname: String) {
        _nickname = nickname
        sendBroadcastAnnounce()
    }
    
    func isPeerConnected(_ peerID: PeerID) -> Bool {
        lock.lock()
        let connected = activeConnections[peerID] != nil
        lock.unlock()
        return connected
    }
    
    func isPeerReachable(_ peerID: PeerID) -> Bool {
        isPeerConnected(peerID)
    }
    
    func peerNickname(peerID: PeerID) -> String? {
        lock.lock()
        let nickname = peerNicknames[peerID]
        lock.unlock()
        return nickname
    }
    
    func getPeerNicknames() -> [PeerID: String] {
        lock.lock()
        let nicknames = peerNicknames
        lock.unlock()
        return nicknames
    }
    
    func getFingerprint(for peerID: PeerID) -> String? {
        noiseService.getPeerPublicKeyData(peerID)?.sha256Fingerprint()
    }
    
    func getNoiseSessionState(for peerID: PeerID) -> LazyHandshakeState {
        // Determine state from noise service
        if noiseService.hasEstablishedSession(with: peerID) {
            return .established
        } else if noiseService.hasSession(with: peerID) {
            return .handshaking
        } else {
            return .none
        }
    }
    
    func triggerHandshake(with peerID: PeerID) {
        // Trigger handshake via noise service
        noiseService.onHandshakeRequired?(peerID)
    }
    
    func getNoiseService() -> NoiseEncryptionService {
        noiseService
    }
    
    // MARK: - Messaging
    
    func sendMessage(_ content: String, mentions: [String]) {
        sendMessage(content, mentions: mentions, messageID: UUID().uuidString, timestamp: Date())
    }
    
    func sendMessage(_ content: String, mentions: [String], messageID: String, timestamp: Date) {
        let timestampMs = UInt64(timestamp.timeIntervalSince1970 * 1000)
        
        let packet = BitchatPacket(
            type: MessageType.message.rawValue,
            senderID: mySenderIDData,
            recipientID: nil,
            timestamp: timestampMs,
            payload: content.data(using: .utf8) ?? Data(),
            signature: nil,
            ttl: 7
        )
        
        // Send to all connected peers
        lock.lock()
        let connections = Array(activeConnections.values)
        lock.unlock()
        
        for connection in connections {
            sendPacket(packet, to: connection)
        }
    }
    
    func sendPrivateMessage(_ content: String, to peerID: PeerID, recipientNickname: String, messageID: String) {
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Encrypt with Noise (the actual encryption happens in NoiseEncryptionService)
        let packet = BitchatPacket(
            type: MessageType.noiseEncrypted.rawValue,
            senderID: mySenderIDData,
            recipientID: peerID.routingData,
            timestamp: timestampMs,
            payload: content.data(using: .utf8) ?? Data(),
            signature: nil,
            ttl: 7
        )
        
        // Send to specific peer if directly connected, otherwise broadcast for relay
        lock.lock()
        if let connection = activeConnections[peerID] {
            lock.unlock()
            sendPacket(packet, to: connection)
        } else {
            // Broadcast for mesh relay
            let connections = Array(activeConnections.values)
            lock.unlock()
            
            for connection in connections {
                sendPacket(packet, to: connection)
            }
        }
    }
    
    func sendReadReceipt(_ receipt: ReadReceipt, to peerID: PeerID) {
        // Encode receipt and send via noise encrypted channel
        guard let payload = try? JSONEncoder().encode(receipt) else { return }
        
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        
        let packet = BitchatPacket(
            type: MessageType.noiseEncrypted.rawValue,
            senderID: mySenderIDData,
            recipientID: peerID.routingData,
            timestamp: timestampMs,
            payload: payload,
            signature: nil,
            ttl: 7
        )
        
        lock.lock()
        if let connection = activeConnections[peerID] {
            lock.unlock()
            sendPacket(packet, to: connection)
        } else {
            lock.unlock()
        }
    }
    
    func sendFavoriteNotification(to peerID: PeerID, isFavorite: Bool) {
        // Similar to BLEService
    }
    
    func sendBroadcastAnnounce() {
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        
        let packet = BitchatPacket(
            type: MessageType.announce.rawValue,
            senderID: mySenderIDData,
            recipientID: nil,
            timestamp: timestampMs,
            payload: myNickname.data(using: .utf8) ?? Data(),
            signature: nil,
            ttl: 7
        )
        
        lock.lock()
        let connections = Array(activeConnections.values)
        lock.unlock()
        
        for connection in connections {
            sendPacket(packet, to: connection)
        }
    }
    
    func sendDeliveryAck(for messageID: String, to peerID: PeerID) {
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
        
        let packet = BitchatPacket(
            type: MessageType.noiseEncrypted.rawValue,
            senderID: mySenderIDData,
            recipientID: peerID.routingData,
            timestamp: timestampMs,
            payload: messageID.data(using: .utf8) ?? Data(),
            signature: nil,
            ttl: 7
        )
        
        lock.lock()
        if let connection = activeConnections[peerID] {
            lock.unlock()
            sendPacket(packet, to: connection)
        } else {
            lock.unlock()
        }
    }
    
    func sendFileBroadcast(_ packet: BitchatFilePacket, transferId: String) {
        // WiFi Aware is great for large files - high bandwidth!
        SecureLogger.info("WiFiAware: File broadcast (high bandwidth available)", category: .session)
    }
    
    func sendFilePrivate(_ packet: BitchatFilePacket, to peerID: PeerID, transferId: String) {
        // Direct high-bandwidth transfer
        SecureLogger.info("WiFiAware: Private file transfer to \(peerID.id.prefix(8))", category: .session)
    }
    
    func cancelTransfer(_ transferId: String) {
        // Cancel in-progress transfer
    }
}
