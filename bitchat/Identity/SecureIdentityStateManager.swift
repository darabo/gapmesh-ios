//
// SecureIdentityStateManager.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

///
/// # SecureIdentityStateManager
///
/// Manages the persistent storage and retrieval of identity mappings with
/// encryption at rest. This singleton service maintains the relationship between
/// ephemeral peer IDs, cryptographic fingerprints, and social identities.
///
/// ## Overview
/// The SecureIdentityStateManager provides a secure, privacy-preserving way to
/// maintain identity relationships across app launches. It implements:
/// - Encrypted storage of identity mappings
/// - In-memory caching for performance
/// - Thread-safe access patterns
/// - Automatic debounced persistence
///
/// ## Architecture
/// The manager operates at three levels:
/// 1. **In-Memory State**: Fast access to active identities
/// 2. **Encrypted Cache**: Persistent storage in Keychain
/// 3. **Privacy Controls**: User-configurable persistence settings
///
/// ## Security Features
///
/// ### Encryption at Rest
/// - Identity cache encrypted with AES-GCM
/// - Unique 256-bit encryption key per device
/// - Key stored separately in Keychain
/// - No plaintext identity data on disk
///
/// ### Privacy by Design
/// - Persistence is optional (user-controlled)
/// - Minimal data retention
/// - No cloud sync or backup
/// - Automatic cleanup of stale entries
///
/// ### Thread Safety
/// - Concurrent read access via GCD barriers
/// - Write operations serialized
/// - Atomic state updates
/// - No data races or corruption
///
/// ## Data Model
/// Manages three types of identity data:
/// 1. **Ephemeral Sessions**: Current peer connections
/// 2. **Cryptographic Identities**: Public keys and fingerprints
/// 3. **Social Identities**: User-assigned names and trust
///
/// ## Persistence Strategy
/// - Changes batched and debounced (2-second window)
/// - Automatic save on app termination
/// - Crash-resistant with atomic writes
/// - Migration support for schema changes
///
/// ## Usage Patterns
/// ```swift
/// // Register a new peer identity
/// manager.registerPeerIdentity(peerID, publicKey, fingerprint)
/// 
/// // Update social identity
/// manager.updateSocialIdentity(fingerprint, nickname, trustLevel)
/// 
/// // Query identity
/// let identity = manager.resolvePeerIdentity(peerID)
/// ```
///
/// ## Performance Optimizations
/// - In-memory cache eliminates Keychain roundtrips
/// - Debounced saves reduce I/O operations
/// - Efficient data structures for lookups
/// - Background queue for expensive operations
///
/// ## Privacy Considerations
/// - Users can disable all persistence
/// - Identity cache can be wiped instantly
/// - No analytics or telemetry
/// - Ephemeral mode for high-risk users
///
/// ## Future Enhancements
/// - Selective identity export
/// - Cross-device identity sync (optional)
/// - Identity attestation support
/// - Advanced conflict resolution
///

import BitLogger
import Foundation
import CryptoKit

protocol SecureIdentityStateManagerProtocol {
    // MARK: Secure Loading/Saving
    func forceSave()
    
    // MARK: Social Identity Management
    func getSocialIdentity(for fingerprint: String) -> SocialIdentity?
    
    // MARK: Cryptographic Identities
    func upsertCryptographicIdentity(fingerprint: String, noisePublicKey: Data, signingPublicKey: Data?, claimedNickname: String?)
    func getCryptoIdentitiesByPeerIDPrefix(_ peerID: PeerID) -> [CryptographicIdentity]
    func updateSocialIdentity(_ identity: SocialIdentity)
    
    // MARK: Favorites Management
    func getFavorites() -> Set<String>
    func setFavorite(_ fingerprint: String, isFavorite: Bool)
    func isFavorite(fingerprint: String) -> Bool
    
    // MARK: Blocked Users Management
    func isBlocked(fingerprint: String) -> Bool
    func setBlocked(_ fingerprint: String, isBlocked: Bool)
    
    // MARK: Geohash (Nostr) Blocking
    func isNostrBlocked(pubkeyHexLowercased: String) -> Bool
    func setNostrBlocked(_ pubkeyHexLowercased: String, isBlocked: Bool)
    func getBlockedNostrPubkeys() -> Set<String>
    
    // MARK: Ephemeral Session Management
    func registerEphemeralSession(peerID: PeerID, handshakeState: HandshakeState)
    func updateHandshakeState(peerID: PeerID, state: HandshakeState)
    
    // MARK: Cleanup
    func clearAllIdentityData()
    func removeEphemeralSession(peerID: PeerID)
    
    // MARK: Verification
    func setVerified(fingerprint: String, verified: Bool)
    func isVerified(fingerprint: String) -> Bool
    func getVerifiedFingerprints() -> Set<String>
}

/// Singleton manager for secure identity state persistence and retrieval.
/// Provides thread-safe access to identity mappings with encryption at rest.
/// All identity data is stored encrypted in the device Keychain for security.
final class SecureIdentityStateManager: SecureIdentityStateManagerProtocol {
    private let keychain: KeychainManagerProtocol
    private let cacheKey = "bitchat.identityCache.v2"
    private let encryptionKeyName = "identityCacheEncryptionKey"
    
    // In-memory state
    private var ephemeralSessions: [PeerID: EphemeralIdentity] = [:]
    private var cryptographicIdentities: [String: CryptographicIdentity] = [:]
    private var cache: IdentityCache = IdentityCache()
    
    // Thread safety
    private let queue = DispatchQueue(label: "bitchat.identity.state", attributes: .concurrent)
    
    // Debouncing for keychain saves
    private var saveTimer: Timer?
    private let saveDebounceInterval: TimeInterval = 2.0  // Save at most once every 2 seconds
    private var pendingSave = false
    
    // Encryption key
    private let encryptionKey: SymmetricKey
    
    init(_ keychain: KeychainManagerProtocol) {
        self.keychain = keychain
        
        // Generate or retrieve encryption key from Secure Enclave wrapper
        self.encryptionKey = Self.getOrGenerateMasterKey(keychain: keychain, tag: self.encryptionKeyName)
        
        // Load identity cache on init
        loadIdentityCache()
    }
    
    // MARK: - Secure Enclave Wrapped Key Management
    
    private static func getOrGenerateMasterKey(keychain: KeychainManagerProtocol, tag: String) -> SymmetricKey {
        let wrappedTag = tag + "_wrapped"
        
        // 1. Try to load Secure Enclave wrapped key
        if let wrappedData = keychain.getIdentityKey(forKey: wrappedTag),
           let decryptedData = decryptWithSecureEnclaveToken(data: wrappedData, tag: tag) {
            SecureLogger.logKeyOperation(.load, keyType: "identity cache Secure Enclave master key", success: true)
            return SymmetricKey(data: decryptedData)
        }
        
        // 2. Try to load legacy software key and migrate it
        if let plaintextKey = keychain.getIdentityKey(forKey: tag) {
            SecureLogger.debug("Migrating identity cache master key to Secure Enclave", category: .security)
            if let targetSecKey = getOrGenerateSecureEnclaveToken(tag: tag),
               let wrapped = wrapDataWithSecKey(data: plaintextKey, key: targetSecKey) {
                _ = keychain.saveIdentityKey(wrapped, forKey: wrappedTag)
                // We keep the old software key as a fallback/backup in case Secure Enclave is wiped or app restoring issues occur
            }
            return SymmetricKey(data: plaintextKey)
        }
        
        // 3. Generate new master key and wrap it
        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data($0) }
        
        if let targetSecKey = getOrGenerateSecureEnclaveToken(tag: tag),
           let wrapped = wrapDataWithSecKey(data: newKeyData, key: targetSecKey) {
            let saved = keychain.saveIdentityKey(wrapped, forKey: wrappedTag)
            SecureLogger.logKeyOperation(.generate, keyType: "identity cache Secure Enclave master key", success: saved)
        } else {
            // Fallback if Secure Enclave is completely unavailable
            let saved = keychain.saveIdentityKey(newKeyData, forKey: tag)
            SecureLogger.logKeyOperation(.generate, keyType: "identity cache software master key", success: saved)
        }
        
        return newKey
    }
    
    private static func getOrGenerateSecureEnclaveToken(tag: String) -> SecKey? {
        // Tag needs to be globally unique for the SecItem API
        let fullTag = "\(BitchatApp.bundleID).\(tag).secEnclave"
        guard let tagData = fullTag.data(using: .utf8) else { return nil }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tagData,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess {
            return (item as! SecKey)
        }
        
        // Generate new SecKey
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        ) else { return nil }
        
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
                kSecAttrAccessControl as String: access
            ]
        ]
        
        #if !targetEnvironment(simulator)
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        #endif
        
        var error: Unmanaged<CFError>?
        if let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) {
            return privateKey
        }
        
        // Fallback: try generating without explicitly requiring Secure Enclave
        // (Useful on simulators or older Macs without T2/M-series chips)
        attributes.removeValue(forKey: kSecAttrTokenID as String)
        if let fallbackKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) {
            return fallbackKey
        }
        
        if let err = error?.takeRetainedValue() {
            SecureLogger.error(err as Error, context: "Failed to generate Secure Enclave token", category: .security)
        }
        return nil
    }
    
    private static func wrapDataWithSecKey(data: Data, key: SecKey) -> Data? {
        guard let publicKey = SecKeyCopyPublicKey(key) else { return nil }
        var error: Unmanaged<CFError>?
        let cipherText = SecKeyCreateEncryptedData(publicKey,
                                                   .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
                                                   data as CFData,
                                                   &error)
        if let err = error?.takeRetainedValue() {
            SecureLogger.error(err as Error, context: "Failed to wrap data with Secure Enclave key", category: .security)
        }
        return cipherText as Data?
    }
    
    private static func decryptWithSecureEnclaveToken(data: Data, tag: String) -> Data? {
        guard let privateKey = getOrGenerateSecureEnclaveToken(tag: tag) else { return nil }
        var error: Unmanaged<CFError>?
        let plainText = SecKeyCreateDecryptedData(privateKey,
                                                  .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
                                                  data as CFData,
                                                  &error)
        if let err = error?.takeRetainedValue() {
            SecureLogger.error(err as Error, context: "Failed to decrypt with Secure Enclave key", category: .security)
        }
        return plainText as Data?
    }
    
    deinit {
        forceSave()
    }
    
    // MARK: - Secure Loading/Saving
    
    private func loadIdentityCache() {
        guard let encryptedData = keychain.getIdentityKey(forKey: cacheKey) else {
            // No existing cache, start fresh
            return
        }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
            cache = try JSONDecoder().decode(IdentityCache.self, from: decryptedData)
        } catch {
            // Log error but continue with empty cache
            SecureLogger.error(error, context: "Failed to load identity cache", category: .security)
        }
    }
    
    private func saveIdentityCache() {
        // Mark that we need to save
        pendingSave = true
        
        // Cancel any existing timer
        saveTimer?.invalidate()
        
        // Schedule a new save after the debounce interval
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
            self?.performSave()
        }
    }
    
    private func performSave() {
        guard pendingSave else { return }
        pendingSave = false
        
        do {
            let data = try JSONEncoder().encode(cache)
            let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
            let saved = keychain.saveIdentityKey(sealedBox.combined!, forKey: cacheKey)
            if saved {
                SecureLogger.debug("Identity cache saved to keychain", category: .security)
            }
        } catch {
            SecureLogger.error(error, context: "Failed to save identity cache", category: .security)
        }
    }
    
    // Force immediate save (for app termination)
    func forceSave() {
        saveTimer?.invalidate()
        performSave()
    }
    
    // MARK: - Social Identity Management
    
    func getSocialIdentity(for fingerprint: String) -> SocialIdentity? {
        queue.sync {
            return cache.socialIdentities[fingerprint]
        }
    }

    // MARK: - Cryptographic Identities

    /// Insert or update a cryptographic identity and optionally persist its signing key and claimed nickname.
    /// - Parameters:
    ///   - fingerprint: SHA-256 hex of the Noise static public key
    ///   - noisePublicKey: Noise static public key data
    ///   - signingPublicKey: Optional Ed25519 signing public key for authenticating public messages
    ///   - claimedNickname: Optional latest claimed nickname to persist into social identity
    func upsertCryptographicIdentity(fingerprint: String, noisePublicKey: Data, signingPublicKey: Data?, claimedNickname: String? = nil) {
        queue.async(flags: .barrier) {
            let now = Date()
            if var existing = self.cryptographicIdentities[fingerprint] {
                // Update keys if changed
                if existing.publicKey != noisePublicKey {
                    existing = CryptographicIdentity(
                        fingerprint: fingerprint,
                        publicKey: noisePublicKey,
                        signingPublicKey: signingPublicKey ?? existing.signingPublicKey,
                        firstSeen: existing.firstSeen,
                        lastHandshake: now
                    )
                    self.cryptographicIdentities[fingerprint] = existing
                } else {
                    // Update signing key and lastHandshake
                    existing.signingPublicKey = signingPublicKey ?? existing.signingPublicKey
                    let updated = CryptographicIdentity(
                        fingerprint: existing.fingerprint,
                        publicKey: existing.publicKey,
                        signingPublicKey: existing.signingPublicKey,
                        firstSeen: existing.firstSeen,
                        lastHandshake: now
                    )
                    self.cryptographicIdentities[fingerprint] = updated
                }
                // Persist updated state (already assigned in branches above)
            } else {
                // New entry
                let entry = CryptographicIdentity(
                    fingerprint: fingerprint,
                    publicKey: noisePublicKey,
                    signingPublicKey: signingPublicKey,
                    firstSeen: now,
                    lastHandshake: now
                )
                self.cryptographicIdentities[fingerprint] = entry
            }

            // Optionally persist claimed nickname into social identity
            if let claimed = claimedNickname {
                var identity = self.cache.socialIdentities[fingerprint] ?? SocialIdentity(
                    fingerprint: fingerprint,
                    localPetname: nil,
                    claimedNickname: claimed,
                    trustLevel: .unknown,
                    isFavorite: false,
                    isBlocked: false,
                    notes: nil
                )
                // Update claimed nickname if changed
                if identity.claimedNickname != claimed {
                    identity.claimedNickname = claimed
                    self.cache.socialIdentities[fingerprint] = identity
                } else if self.cache.socialIdentities[fingerprint] == nil {
                    self.cache.socialIdentities[fingerprint] = identity
                }
            }

            self.saveIdentityCache()
        }
    }

    /// Find cryptographic identities whose fingerprint prefix matches a peerID (16-hex) short ID
    func getCryptoIdentitiesByPeerIDPrefix(_ peerID: PeerID) -> [CryptographicIdentity] {
        queue.sync {
            // Defensive: ensure hex and correct length
            guard peerID.isShort else { return [] }
            return cryptographicIdentities.values.filter { $0.fingerprint.hasPrefix(peerID.id) }
        }
    }
    
    func updateSocialIdentity(_ identity: SocialIdentity) {
        queue.async(flags: .barrier) {
            self.cache.socialIdentities[identity.fingerprint] = identity
            
            // Update nickname index
            if let existingIdentity = self.cache.socialIdentities[identity.fingerprint] {
                // Remove old nickname from index if changed
                if existingIdentity.claimedNickname != identity.claimedNickname {
                    self.cache.nicknameIndex[existingIdentity.claimedNickname]?.remove(identity.fingerprint)
                    if self.cache.nicknameIndex[existingIdentity.claimedNickname]?.isEmpty == true {
                        self.cache.nicknameIndex.removeValue(forKey: existingIdentity.claimedNickname)
                    }
                }
            }
            
            // Add new nickname to index
            if self.cache.nicknameIndex[identity.claimedNickname] == nil {
                self.cache.nicknameIndex[identity.claimedNickname] = Set<String>()
            }
            self.cache.nicknameIndex[identity.claimedNickname]?.insert(identity.fingerprint)
            
            // Save to keychain
            self.saveIdentityCache()
        }
    }
    
    // MARK: - Favorites Management
    
    func getFavorites() -> Set<String> {
        queue.sync {
            let favorites = cache.socialIdentities.values
                .filter { $0.isFavorite }
                .map { $0.fingerprint }
            return Set(favorites)
        }
    }
    
    func setFavorite(_ fingerprint: String, isFavorite: Bool) {
        queue.async(flags: .barrier) {
            if var identity = self.cache.socialIdentities[fingerprint] {
                identity.isFavorite = isFavorite
                self.cache.socialIdentities[fingerprint] = identity
            } else {
                // Create new social identity for this fingerprint
                let newIdentity = SocialIdentity(
                    fingerprint: fingerprint,
                    localPetname: nil,
                    claimedNickname: "Unknown",
                    trustLevel: .unknown,
                    isFavorite: isFavorite,
                    isBlocked: false,
                    notes: nil
                )
                self.cache.socialIdentities[fingerprint] = newIdentity
            }
            self.saveIdentityCache()
        }
    }
    
    func isFavorite(fingerprint: String) -> Bool {
        queue.sync {
            return cache.socialIdentities[fingerprint]?.isFavorite ?? false
        }
    }
    
    // MARK: - Blocked Users Management
    
    func isBlocked(fingerprint: String) -> Bool {
        queue.sync {
            return cache.socialIdentities[fingerprint]?.isBlocked ?? false
        }
    }
    
    func setBlocked(_ fingerprint: String, isBlocked: Bool) {
        SecureLogger.info("User \(isBlocked ? "blocked" : "unblocked"): \(fingerprint)", category: .security)
        
        queue.async(flags: .barrier) {
            if var identity = self.cache.socialIdentities[fingerprint] {
                identity.isBlocked = isBlocked
                if isBlocked {
                    identity.isFavorite = false  // Can't be both favorite and blocked
                }
                self.cache.socialIdentities[fingerprint] = identity
            } else {
                // Create new social identity for this fingerprint
                let newIdentity = SocialIdentity(
                    fingerprint: fingerprint,
                    localPetname: nil,
                    claimedNickname: "Unknown",
                    trustLevel: .unknown,
                    isFavorite: false,
                    isBlocked: isBlocked,
                    notes: nil
                )
                self.cache.socialIdentities[fingerprint] = newIdentity
            }
            self.saveIdentityCache()
        }
    }

    // MARK: - Geohash (Nostr) Blocking
    
    func isNostrBlocked(pubkeyHexLowercased: String) -> Bool {
        queue.sync {
            return cache.blockedNostrPubkeys.contains(pubkeyHexLowercased.lowercased())
        }
    }
    
    func setNostrBlocked(_ pubkeyHexLowercased: String, isBlocked: Bool) {
        let key = pubkeyHexLowercased.lowercased()
        queue.async(flags: .barrier) {
            if isBlocked {
                self.cache.blockedNostrPubkeys.insert(key)
            } else {
                self.cache.blockedNostrPubkeys.remove(key)
            }
            self.saveIdentityCache()
        }
    }
    
    func getBlockedNostrPubkeys() -> Set<String> {
        queue.sync { cache.blockedNostrPubkeys }
    }
    
    // MARK: - Ephemeral Session Management
    
    func registerEphemeralSession(peerID: PeerID, handshakeState: HandshakeState = .none) {
        queue.async(flags: .barrier) {
            self.ephemeralSessions[peerID] = EphemeralIdentity(
                peerID: peerID,
                sessionStart: Date(),
                handshakeState: handshakeState
            )
        }
    }
    
    func updateHandshakeState(peerID: PeerID, state: HandshakeState) {
        queue.async(flags: .barrier) {
            self.ephemeralSessions[peerID]?.handshakeState = state
            
            // If handshake completed, update last interaction
            if case .completed(let fingerprint) = state {
                self.cache.lastInteractions[fingerprint] = Date()
                self.saveIdentityCache()
            }
        }
    }
    
    // MARK: - Cleanup
    
    func clearAllIdentityData() {
        SecureLogger.warning("Clearing all identity data", category: .security)
        
        queue.async(flags: .barrier) {
            self.cache = IdentityCache()
            self.ephemeralSessions.removeAll()
            self.cryptographicIdentities.removeAll()
            
            // Delete from keychain
            let deleted = self.keychain.deleteIdentityKey(forKey: self.cacheKey)
            SecureLogger.logKeyOperation(.delete, keyType: "identity cache", success: deleted)
        }
    }
    
    func removeEphemeralSession(peerID: PeerID) {
        queue.async(flags: .barrier) {
            self.ephemeralSessions.removeValue(forKey: peerID)
        }
    }
    
    // MARK: - Verification
    
    func setVerified(fingerprint: String, verified: Bool) {
        SecureLogger.info("Fingerprint \(verified ? "verified" : "unverified"): \(fingerprint)", category: .security)
        
        queue.async(flags: .barrier) {
            if verified {
                self.cache.verifiedFingerprints.insert(fingerprint)
            } else {
                self.cache.verifiedFingerprints.remove(fingerprint)
            }
            
            // Update trust level if social identity exists
            if var identity = self.cache.socialIdentities[fingerprint] {
                identity.trustLevel = verified ? .verified : .casual
                self.cache.socialIdentities[fingerprint] = identity
            }
            
            self.saveIdentityCache()
        }
    }
    
    func isVerified(fingerprint: String) -> Bool {
        queue.sync {
            return cache.verifiedFingerprints.contains(fingerprint)
        }
    }
    
    func getVerifiedFingerprints() -> Set<String> {
        queue.sync {
            return cache.verifiedFingerprints
        }
    }
}
