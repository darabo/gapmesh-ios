//
//  PanicWipeManager.swift
//  bitchat
//

import Foundation
import BitLogger

/// Coordinates a crash-resilient emergency data wipe.
@MainActor
final class PanicWipeManager {
    static let shared = PanicWipeManager()
    
    // We use standard UserDefaults to track wipe state because it works
    // even without any encryption/keychain access.
    private let prefs = UserDefaults.standard
    private let wipeInProgressKey = "panic_wipe_in_progress"
    
    private init() {}
    
    func isWipeInProgress() -> Bool {
        return prefs.bool(forKey: wipeInProgressKey)
    }
    
    func resumeWipeIfNeeded(chatViewModel: ChatViewModel) {
        if isWipeInProgress() {
            SecureLogger.warning("Resuming interrupted panic wipe...", category: .security)
            executeWipe(chatViewModel: chatViewModel)
        }
    }
    
    func executeWipe(chatViewModel: ChatViewModel) {
        SecureLogger.warning("🚨 STARTING PANIC WIPE 🚨", category: .security)
        
        // Mark wipe as started and force disk sync
        prefs.set(true, forKey: wipeInProgressKey)
        prefs.synchronize()
        
        // Step 1: Memory Wipe (UI State)
        chatViewModel.messages.removeAll()
        chatViewModel.privateChatManager.privateChats.removeAll()
        chatViewModel.privateChatManager.unreadMessages.removeAll()
        chatViewModel.autocompleteSuggestions.removeAll()
        chatViewModel.showAutocomplete = false
        chatViewModel.autocompleteRange = nil
        chatViewModel.selectedAutocompleteIndex = 0
        chatViewModel.selectedPrivateChatPeer = nil
        chatViewModel.selectedPrivateChatFingerprint = nil
        chatViewModel.sentReadReceipts.removeAll()
        chatViewModel.deduplicationService.clearAll()
        chatViewModel.invalidateEncryptionCache()
        
        // Step 2: Delete Keychain Data
        _ = chatViewModel.keychain.deleteAllKeychainData()
        FavoritesPersistenceService.shared.clearAllFavorites()
        chatViewModel.identityManager.clearAllIdentityData()
        
        // Step 3: Delete Identity from Storage
        SecureStorageManager.shared.set(nil, forKey: "bitchat.noiseIdentityKey")
        SecureStorageManager.shared.set(nil, forKey: "bitchat.messageRetentionKey")
        chatViewModel.verifiedFingerprints.removeAll()
        chatViewModel.peerIDToPublicKeyFingerprint.removeAll()
        
        // Step 4: Disconnect Networks
        chatViewModel.nostrRelayManager?.disconnect()
        chatViewModel.nostrRelayManager = nil
        chatViewModel.idBridge.clearAllAssociations()
        chatViewModel.meshService.emergencyDisconnectAll()
        if let bleService = chatViewModel.meshService as? BLEService {
            bleService.resetIdentityForPanic(currentNickname: chatViewModel.nickname)
        }
        
        // Step 5: Delete Media Files synchronously to ensure they are gone before flag clears
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let filesDir = base.appendingPathComponent("files", isDirectory: true)

            // Delete the entire files directory and recreate it
            if FileManager.default.fileExists(atPath: filesDir.path) {
                try FileManager.default.removeItem(at: filesDir)
                SecureLogger.info("🗑️ Deleted all media files during panic clear", category: .session)
            }

            // Recreate empty directory structure
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true, attributes: nil)
            let subdirs = ["voicenotes/incoming", "voicenotes/outgoing", "images/incoming", "images/outgoing", "files/incoming", "files/outgoing"]
            for subdir in subdirs {
                try FileManager.default.createDirectory(at: filesDir.appendingPathComponent(subdir, isDirectory: true), withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            SecureLogger.error("Failed to clear media files during panic: \(error)", category: .session)
        }
        
        // Step 6: Create New Identity
        chatViewModel.nickname = "anon\(Int.random(in: 1000...9999))"
        chatViewModel.saveNickname() // Save to secure storage
        
        // Step 7: Reset Network Services async
        Task { @MainActor in
            // Small delay to ensure cleanup completes
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            chatViewModel.nostrRelayManager = NostrRelayManager()
            chatViewModel.setupNostrMessageHandling()
            chatViewModel.nostrRelayManager?.connect()
            
            // Step 8: Finalize Wipe
            self.prefs.set(false, forKey: wipeInProgressKey)
            self.prefs.synchronize()
            SecureLogger.info("✅ Panic wipe completed successfully", category: .security)
            
            // Step 9: Activate Decoy
            // Mark decoy mode as active in the keychain so the calculator
            // screen is shown on next launch.
            DecoyModeManager.shared.activateDecoy()
            
            // Step 10: Change App Icon to Calculator
            // Switch the home-screen icon to a calculator icon so the app
            // looks like an innocent calculator app to anyone who sees it.
            AppIconManager.shared.switchToDecoyIcon()
        }
    }
}
