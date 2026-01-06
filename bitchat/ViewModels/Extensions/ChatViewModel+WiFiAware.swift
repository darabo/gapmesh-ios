import Foundation
import Combine
import BitLogger

/// ChatViewModel extension for WiFi Aware transport integration.
/// Provides high-bandwidth WiFi mesh networking alongside BLE.
extension ChatViewModel {
    
    // MARK: - WiFi Aware Transport Management
    
    /// Computed property to access WiFi Aware transport if available.
    /// Returns nil if WiFi Aware is not supported on this device.
    @MainActor
    var wifiAwareTransport: WiFiAwareTransport? {
        // Store WiFi Aware transport instance in associated object
        // This allows optional addition without modifying main class
        return objc_getAssociatedObject(self, &AssociatedKeys.wifiAwareTransport) as? WiFiAwareTransport
    }
    
    /// Initialize and start WiFi Aware transport if supported.
    /// Should be called after main initialization.
    @MainActor
    func initializeWiFiAwareIfAvailable() {
        guard WiFiAwareAvailability.isSupported else {
            SecureLogger.info("WiFi Aware not supported on this device", category: .session)
            return
        }
        
        let wifiAware = WiFiAwareTransport(
            keychain: keychain,
            identityManager: identityManager
        )
        
        // Store reference
        objc_setAssociatedObject(
            self,
            &AssociatedKeys.wifiAwareTransport,
            wifiAware,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        
        // Set delegates
        wifiAware.delegate = self
        wifiAware.peerEventsDelegate = unifiedPeerService
        
        // Add to message router for unified routing
        messageRouter.addTransport(wifiAware)
        
        // Start services
        wifiAware.startServices()
        
        SecureLogger.info("WiFi Aware transport initialized and started", category: .session)
    }
    
    /// Stop WiFi Aware transport.
    @MainActor
    func stopWiFiAware() {
        wifiAwareTransport?.stopServices()
    }
    
    // MARK: - Transport Selection
    
    /// Select the best transport for sending to a specific peer.
    /// Priority: WiFi Aware (high bandwidth) > BLE (always available) > Nostr (internet)
    @MainActor
    func bestTransport(for peerID: PeerID) -> Transport {
        // 1. Prefer WiFi Aware for high bandwidth
        if let wifiAware = wifiAwareTransport, wifiAware.isPeerConnected(peerID) {
            return wifiAware
        }
        
        // 2. Fall back to BLE mesh
        if meshService.isPeerConnected(peerID) {
            return meshService
        }
        
        // 3. Default to mesh service (will route via Nostr if needed)
        return meshService
    }
    
    /// Check if WiFi Aware is available and has connected peers.
    @MainActor
    var hasWiFiAwarePeers: Bool {
        guard let wifiAware = wifiAwareTransport else { return false }
        return !wifiAware.currentPeerSnapshots().isEmpty
    }
    
    /// Get all peers connected via WiFi Aware.
    @MainActor
    var wifiAwarePeers: [TransportPeerSnapshot] {
        wifiAwareTransport?.currentPeerSnapshots() ?? []
    }
}

// MARK: - Associated Object Keys

private struct AssociatedKeys {
    static var wifiAwareTransport: UInt8 = 0
}
