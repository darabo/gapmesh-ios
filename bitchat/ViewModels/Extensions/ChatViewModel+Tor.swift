//
// ChatViewModel+Tor.swift
// bitchat
//
// Tor lifecycle handling for ChatViewModel
//

import Foundation
import Combine
import Tor
import BitLogger

extension ChatViewModel {
    
    // MARK: - Tor notifications
    
    @objc func handleTorWillStart() {
        Task { @MainActor in
            if !self.torStatusAnnounced && TorManager.shared.torEnforced {
                self.torStatusAnnounced = true
                self.torStatus = .connecting
                // Post only in geohash channels (queue if not active)
                self.addGeohashOnlySystemMessage(
                    String(localized: "system.tor.starting", comment: "System message when Tor is starting")
                )
            }
        }
    }
    
    @objc func handleTorWillRestart() {
        Task { @MainActor in
            self.torRestartPending = true
            self.torStatus = .connecting
            // Post only in geohash channels (queue if not active)
            self.addGeohashOnlySystemMessage(
                String(localized: "system.tor.restarting", comment: "System message when Tor is restarting")
            )
        }
    }

    @objc func handleTorDidBecomeReady() {
        Task { @MainActor in
            // Only announce "restarted" if we actually restarted this session
            if self.torRestartPending {
                // Post only in geohash channels (queue if not active)
                self.addGeohashOnlySystemMessage(
                    String(localized: "system.tor.restarted", comment: "System message when Tor has restarted")
                )
                self.torStatus = .connected
                self.torRestartPending = false
            } else if TorManager.shared.torEnforced && !self.torInitialReadyAnnounced {
                // Initial start completed
                self.torStatus = .connected
                self.addGeohashOnlySystemMessage(
                    String(localized: "system.tor.started", comment: "System message when Tor has started")
                )
                self.torInitialReadyAnnounced = true
            }
            
            // Resubscribe to geohash channel now that Tor is ready
            // This ensures subscriptions deferred due to Tor not being ready are properly established
            if case .location = self.activeChannel {
                SecureLogger.info("GeoDebug: Tor ready, resubscribing to geohash channel", category: .session)
                self.resubscribeCurrentGeohash()
            }
        }
    }

    @objc func handleTorPreferenceChanged(_ notification: Notification) {
        Task { @MainActor in
            self.torStatusAnnounced = false
            self.torInitialReadyAnnounced = false
            self.torRestartPending = false
            if !TorManager.shared.torEnforced {
                self.torStatus = .off
            } else {
                self.torStatus = .connecting
            }
        }
    }
}
