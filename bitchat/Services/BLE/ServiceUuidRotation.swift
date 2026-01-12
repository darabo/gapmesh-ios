import Foundation
import CryptoKit
import CommonCrypto

/// Service UUID Rotation for BLE advertisement privacy.
/// Rotates the advertised service UUID hourly using time-based HMAC derivation.
///
/// Ported from Noghteha's ServiceUuidRotation / Android Gap Mesh implementation.
final class ServiceUuidRotation {
    
    static let shared = ServiceUuidRotation()
    
    // MARK: - Constants
    
    /// Rotation timing constants (matching Noghteha/Android)
    private static let rotationIntervalMs: Int64 = 3_600_000  // 1 hour
    private static let overlapWindowMs: Int64 = 300_000       // 5 minutes
    
    /// HMAC prefix for derivation
    private static let hmacPrefix = "gap-mesh-ble-uuid-v1-"
    
    /// Fallback UUID (matches current static UUID for backward compatibility with Bitchat)
    static let fallbackUUID = UUID(uuidString: "7ACD9057-811D-4D17-AB14-DA891780FA3A")!
    
    // MARK: - State
    
    /// Shared rotation secret - MUST match Android for cross-platform discovery
    /// This is a deterministic secret used by all Gap Mesh devices
    private let rotationSecret: Data = {
        // SHA256("gap-mesh-global-rotation-v1") = deterministic 32-byte secret
        let seed = "gap-mesh-global-rotation-v1"
        let data = seed.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: 32)
        _ = data.withUnsafeBytes { ptr in
            CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }()
    
    // MARK: - Initialization
    
    private init() {
        // No per-device secret needed anymore - using shared deterministic secret
    }
    
    // MARK: - Public API
    
    /// Get the current service UUID to advertise
    func getCurrentServiceUUID() -> UUID {
        let bucketIndex = getCurrentBucketIndex()
        return deriveUUIDForBucket(bucketIndex)
    }
    
    /// Get all currently valid service UUIDs (for scanning)
    /// Includes current bucket and ±1 for overlap tolerance, plus fallback for Bitchat
    func getValidServiceUUIDs(includeLegacy: Bool = true) -> [UUID] {
        let currentBucket = getCurrentBucketIndex()
        var uuids: [UUID] = []
        
        // Always include current bucket
        uuids.append(deriveUUIDForBucket(currentBucket))
        
        // Include previous bucket (for devices slightly behind)
        uuids.append(deriveUUIDForBucket(currentBucket - 1))
        
        // Include next bucket if we're in overlap window
        if isInOverlapWindow() {
            uuids.append(deriveUUIDForBucket(currentBucket + 1))
        }
        
        // Always include legacy UUID for Bitchat compatibility (if enabled)
        if includeLegacy {
            uuids.append(Self.fallbackUUID)
        }
        
        return Array(Set(uuids))  // Remove duplicates
    }
    
    /// Validate if a discovered service UUID is from our network
    func isValidServiceUUID(_ uuid: UUID, includeLegacy: Bool = true) -> Bool {
        return getValidServiceUUIDs(includeLegacy: includeLegacy).contains(uuid)
    }
    
    /// Get milliseconds until next rotation
    func getTimeUntilNextRotation() -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let nextRotation = ((now / Self.rotationIntervalMs) + 1) * Self.rotationIntervalMs
        return nextRotation - now
    }
    
    /// Check if we're currently in the overlap window (last 5 minutes of current bucket)
    func isInOverlapWindow() -> Bool {
        return getTimeUntilNextRotation() <= Self.overlapWindowMs
    }
    
    // MARK: - Private Methods
    
    private func getCurrentBucketIndex() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000) / Self.rotationIntervalMs
    }
    
    private func deriveUUIDForBucket(_ bucketIndex: Int64) -> UUID {
        let input = "\(Self.hmacPrefix)\(bucketIndex)"
        guard let inputData = input.data(using: .utf8) else {
            return Self.fallbackUUID
        }
        
        let key = SymmetricKey(data: rotationSecret)
        let mac = HMAC<SHA256>.authenticationCode(for: inputData, using: key)
        var hashBytes = Array(mac)
        
        // Set version 4 and variant bits for RFC 4122 compliance
        hashBytes[6] = (hashBytes[6] & 0x0F) | 0x40  // Version 4
        hashBytes[8] = (hashBytes[8] & 0x3F) | 0x80  // Variant
        
        // Convert first 16 bytes to UUID
        let uuidData = Data(hashBytes.prefix(16))
        let uuidString = uuidData.map { String(format: "%02X", $0) }.joined()
        
        // Format as UUID string
        let formatted = String(
            format: "%@-%@-%@-%@-%@",
            String(uuidString.prefix(8)),
            String(uuidString.dropFirst(8).prefix(4)),
            String(uuidString.dropFirst(12).prefix(4)),
            String(uuidString.dropFirst(16).prefix(4)),
            String(uuidString.dropFirst(20))
        )
        
        return UUID(uuidString: formatted) ?? Self.fallbackUUID
    }
}

// MARK: - Legacy Compatibility Settings

extension UserDefaults {
    private static let legacyCompatibilityKey = "com.gap.mesh.legacyCompatibility"
    
    var isLegacyCompatibilityEnabled: Bool {
        get { return bool(forKey: Self.legacyCompatibilityKey) }
        set { set(newValue, forKey: Self.legacyCompatibilityKey) }
    }
}
