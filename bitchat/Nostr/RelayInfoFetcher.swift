import Foundation
import BitLogger
import Tor

// MARK: - NIP-11 Relay Info Fetcher

/// Actor-based fetcher and cache for NIP-11 Relay Information Documents.
/// Uses `TorURLSession.shared.session` for network requests to maintain Tor routing.
actor RelayInfoFetcher {
    static let shared = RelayInfoFetcher()

    private struct CacheEntry {
        let info: RelayInfoDocument
        let fetchedAt: Date
    }

    /// Cache TTL: 30 minutes.
    private let cacheTTLSeconds: TimeInterval = 30 * 60

    /// Request timeout: 10 seconds.
    private let requestTimeoutSeconds: TimeInterval = 10

    /// In-memory cache keyed by relay URL string.
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    // MARK: - Public API

    /// Fetches a NIP-11 document for the given relay URL.
    /// Returns a cached copy if still fresh, otherwise performs a network fetch.
    func fetch(_ relayUrl: String) async -> RelayInfoDocument? {
        // Check cache first
        if let cached = getCached(relayUrl) {
            return cached
        }

        // Convert ws(s):// to http(s):// for the NIP-11 HTTP request
        let httpUrl = relayUrl
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")

        guard let url = URL(string: httpUrl) else {
            SecureLogger.warning("RelayInfoFetcher: invalid URL \(relayUrl)", category: .session)
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeoutSeconds)
        request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")

        do {
            let session = TorURLSession.shared.session
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                SecureLogger.debug("RelayInfoFetcher: non-200 response from \(relayUrl)", category: .session)
                return nil
            }

            let decoder = JSONDecoder()
            let info = try decoder.decode(RelayInfoDocument.self, from: data)

            // Cache it
            cache[relayUrl] = CacheEntry(info: info, fetchedAt: Date())
            SecureLogger.debug("RelayInfoFetcher: cached NIP-11 for \(relayUrl): \(info.capabilitiesSummary)", category: .session)
            return info
        } catch {
            SecureLogger.debug("RelayInfoFetcher: fetch failed for \(relayUrl): \(error.localizedDescription)", category: .session)
            return nil
        }
    }

    /// Returns a cached NIP-11 document if it exists and isn't stale.
    func getCached(_ relayUrl: String) -> RelayInfoDocument? {
        guard let entry = cache[relayUrl] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > cacheTTLSeconds {
            cache.removeValue(forKey: relayUrl)
            return nil
        }
        return entry.info
    }

    /// Fetches NIP-11 for multiple relay URLs concurrently.
    func fetchMultiple(_ relayUrls: [String]) async -> [String: RelayInfoDocument] {
        var results: [String: RelayInfoDocument] = [:]
        await withTaskGroup(of: (String, RelayInfoDocument?).self) { group in
            for url in relayUrls {
                group.addTask { [self] in
                    let info = await self.fetch(url)
                    return (url, info)
                }
            }
            for await (url, info) in group {
                if let info = info {
                    results[url] = info
                }
            }
        }
        return results
    }

    /// Clears the entire cache.
    func clearCache() {
        cache.removeAll()
    }
}
