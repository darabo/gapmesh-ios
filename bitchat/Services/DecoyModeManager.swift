//
// DecoyModeManager.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Security
import CryptoKit

/// Manages decoy calculator mode state and PIN with Keychain persistence.
///
/// Uses an intentionally innocuous Keychain service name that is NOT in the
/// `KeychainManager.deleteAllKeychainData()` sweep list, so the PIN survives
/// the panic wipe. The decoy-active flag is written AFTER the wipe completes.
///
/// **Keychain service**: `app.util.cfg` (not in any known service list or app group)
final class DecoyModeManager: ObservableObject {
    static let shared = DecoyModeManager()

    // Innocuous service name — must NOT appear in KeychainManager's sweep lists
    private let service = "app.util.cfg"
    private let pinAccount = "pin"
    private let activeAccount = "active"

    @Published var isDecoyActive: Bool
    /// Whether a PIN has been configured. Published so SwiftUI can react when
    /// the PIN is first saved (e.g. the post-update onboarding screen).
    @Published var hasPINConfigured: Bool

    private init() {
        // Read persisted decoy-active flag on launch
        isDecoyActive = Self.readFlag(service: "app.util.cfg", account: "active")
        // Read whether a PIN exists
        hasPINConfigured = Self.readExists(service: "app.util.cfg", account: "pin")
        
        // First launch check: clear keychain items if it's a fresh install
        if !UserDefaults.standard.bool(forKey: "hasRunBeforeForDecoy") {
            UserDefaults.standard.set(true, forKey: "hasRunBeforeForDecoy")
            self.deleteItem(account: pinAccount)
            self.deleteItem(account: activeAccount)
            self.isDecoyActive = false
            self.hasPINConfigured = false
        }
    }

    // MARK: - Public API

    /// Generate a cryptographically random 4-digit PIN string (1000-9999).
    static func generateRandomPIN() -> String {
        // Use SecRandomCopyBytes for unpredictable PIN generation
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // Convert to a value in 1000...9999
        let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        let pin = 1000 + Int(raw % 9000) // 1000-9999
        return String(pin)
    }

    /// Save a PIN (plaintext stored as UTF-8 data in Keychain under the isolated service).
    func setPIN(_ pin: String) {
        guard let data = pin.data(using: .utf8) else { return }
        save(account: pinAccount, data: data)
        DispatchQueue.main.async { self.hasPINConfigured = true }
    }

    /// Returns the stored PIN, or nil if none has been set.
    func currentPIN() -> String? {
        guard let data = load(account: pinAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Check whether the input matches the stored PIN.
    func isCorrectPIN(_ input: String) -> Bool {
        guard let stored = currentPIN() else { return false }
        return input == stored
    }

    /// Called at the END of `panicClearAllData()` to activate decoy mode.
    func activateDecoy() {
        save(account: activeAccount, data: Data([1]))
        DispatchQueue.main.async { self.isDecoyActive = true }
    }

    /// Called when the user enters the correct PIN in the calculator.
    func deactivateDecoy() {
        deleteItem(account: activeAccount)
        DispatchQueue.main.async { self.isDecoyActive = false }
    }

    /// Whether a PIN has been configured (set during onboarding or settings).
    var hasPIN: Bool {
        load(account: pinAccount) != nil
    }

    // MARK: - Raw Keychain Helpers (standalone, no dependency on KeychainManager)

    private func save(account: String, data: Data) {
        // Delete first, then add (upsert pattern)
        deleteItem(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func readFlag(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return false }
        return data.first == 1
    }

    /// Check whether any data exists for the given service+account in Keychain.
    private static func readExists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
