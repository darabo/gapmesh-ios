import Foundation

// MARK: - Relay Capability Filter

/// Decides whether a relay is worth connecting to based on its NIP-11 information.
/// Uses an optimistic strategy: unknown relays (no NIP-11 info) are always connected.
enum RelayCapabilityFilter {

    /// Returns `true` if the relay should be connected to.
    /// - Unknown relays (nil info) → usable (optimistic)
    /// - Paid relays → not usable
    /// - Auth-required relays → not usable
    static func isUsable(_ info: RelayInfoDocument?) -> Bool {
        guard let info = info else {
            return true // Optimistic: connect if we have no info
        }

        if info.requiresPayment {
            SecureLogger.debug("RelayCapabilityFilter: skipping paid relay", category: .session)
            return false
        }

        if info.requiresAuth {
            SecureLogger.debug("RelayCapabilityFilter: skipping auth-required relay", category: .session)
            return false
        }

        return true
    }

    /// Filters a list of relay URLs to only those that are usable,
    /// using cached NIP-11 info when available.
    static func filterUsable(_ relayUrls: [String], cache: (String) async -> RelayInfoDocument?) async -> [String] {
        var usable: [String] = []
        for url in relayUrls {
            let info = await cache(url)
            if isUsable(info) {
                usable.append(url)
            }
        }
        return usable
    }

    /// Checks whether a relay supports NIP-17 private messaging (gift wrapping).
    static func supportsPrivateMessaging(_ info: RelayInfoDocument?) -> Bool {
        info?.supportsNip(17) ?? true // Assume yes if unknown
    }
}
